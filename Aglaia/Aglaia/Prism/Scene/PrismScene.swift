//
//  PrismScene.swift
//  Aglaia
//
//  盤面・部品・ビームの描画と、タップ/ドラッグ操作を担う SpriteKit シーン。
//  状態は GameModel を共有し、変更検知は revision の比較で行う。
//

import SpriteKit
import SwiftUI

// MARK: - 盤面ジオメトリ

/// 盤面のレイアウト計算。SKScene と SwiftUI のドロップ処理で共有する
struct BoardGeometry {
    let gridCount: Int
    let cellSize: CGFloat
    /// 盤面左下のシーン座標
    let origin: CGPoint

    init(canvasSize: CGSize, gridCount: Int) {
        self.gridCount = gridCount
        let boardLength = min(canvasSize.width, canvasSize.height) * 0.94
        cellSize = gridCount > 0 ? boardLength / CGFloat(gridCount) : 0
        origin = CGPoint(x: (canvasSize.width - boardLength) / 2,
                         y: (canvasSize.height - boardLength) / 2)
    }

    /// セル中心のシーン座標(盤面ローカルではなくシーン全体の座標)
    func center(of position: GridPosition) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(position.x) + 0.5) * cellSize,
                y: origin.y + (CGFloat(position.y) + 0.5) * cellSize)
    }

    /// シーン座標(y は上向き)からセルを求める。盤外は nil
    func cell(atScenePoint point: CGPoint) -> GridPosition? {
        guard cellSize > 0 else { return nil }
        let x = Int(floor((point.x - origin.x) / cellSize))
        let y = Int(floor((point.y - origin.y) / cellSize))
        guard x >= 0, x < gridCount, y >= 0, y < gridCount else { return nil }
        return GridPosition(x: x, y: y)
    }

    /// SwiftUI のビュー座標(y は下向き)からセルを求める。盤外は nil
    func cell(atViewPoint point: CGPoint, viewSize: CGSize) -> GridPosition? {
        cell(atScenePoint: CGPoint(x: point.x, y: viewSize.height - point.y))
    }
}

// MARK: - シーン

final class PrismScene: SKScene {
    private let model: GameModel

    private let boardNode = SKNode()
    private let gridNode = SKNode()
    private let beamsNode = SKNode()
    private let componentsNode = SKNode()
    private let effectsNode = SKNode()

    private var geometry = BoardGeometry(canvasSize: .zero, gridCount: 1)
    private var renderedRevision = -1
    private var wasSolved = false

    // ドラッグ状態
    private enum DragMode {
        case none
        /// 配置済み部品の移動(元セルを保持)
        case moveComponent(from: GridPosition)
        /// 選択中アイテムの配置プレビュー
        case placePreview
    }

    private var dragMode: DragMode = .none
    private var dragGhost: SKNode?
    private var ghostHighlight: SKShapeNode?
    private var touchStartPoint: CGPoint = .zero
    private var isDragging = false

    init(model: GameModel) {
        self.model = model
        super.init(size: .zero)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to _: SKView) {
        addChild(boardNode)
        boardNode.addChild(gridNode)
        boardNode.addChild(beamsNode)
        boardNode.addChild(componentsNode)
        boardNode.addChild(effectsNode)
        effectsNode.zPosition = 50
        layoutBoard()
        wasSolved = model.solved
    }

    override func didChangeSize(_: CGSize) {
        guard boardNode.parent != nil else { return }
        layoutBoard()
    }

    override func update(_: TimeInterval) {
        if model.revision != renderedRevision {
            renderedRevision = model.revision
            renderComponents()
            renderBeams()
            // 未クリア → クリアに変わった瞬間だけ祝福パーティクルを出す
            if model.solved, !wasSolved {
                emitClearBurst()
            }
            wasSolved = model.solved
        }
    }

    // MARK: - レイアウト

    private func layoutBoard() {
        geometry = BoardGeometry(canvasSize: size, gridCount: model.level.size)
        boardNode.position = geometry.origin
        renderGrid()
        renderedRevision = -1 // セルサイズが変わったので部品とビームも再描画
    }

    /// 盤面ローカル座標でのセル中心
    private func point(of position: GridPosition) -> CGPoint {
        CGPoint(x: (CGFloat(position.x) + 0.5) * geometry.cellSize,
                y: (CGFloat(position.y) + 0.5) * geometry.cellSize)
    }

    private var cellSize: CGFloat { geometry.cellSize }

    // MARK: - 描画

    private func renderGrid() {
        gridNode.removeAllChildren()
        let count = model.level.size
        let length = CGFloat(count) * cellSize
        let path = CGMutablePath()
        for index in 0 ... count {
            let offset = CGFloat(index) * cellSize
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset, y: length))
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: length, y: offset))
        }
        let lines = SKShapeNode(path: path)
        lines.strokeColor = SKColor(white: 1, alpha: 0.12)
        lines.lineWidth = 1
        gridNode.addChild(lines)
    }

    private func renderBeams() {
        beamsNode.removeAllChildren()
        for segment in model.beams {
            var end = point(of: segment.to)
            if segment.exitsBoard {
                let from = point(of: segment.from)
                // 盤外へ抜けるビームはセル半分だけ先へ伸ばす
                let dx = end.x - from.x, dy = end.y - from.y
                let length = max(1, hypot(dx, dy))
                let step = segment.from == segment.to
                    ? directionUnit(segment: segment)
                    : CGVector(dx: dx / length, dy: dy / length)
                end = CGPoint(x: end.x + step.dx * cellSize / 2, y: end.y + step.dy * cellSize / 2)
            }
            beamsNode.addChild(beamNode(from: point(of: segment.from), to: end, color: segment.color))
        }
    }

    /// from == to の線分(光源が盤端で外向きの場合など)の向きを推定する
    private func directionUnit(segment: BeamSegment) -> CGVector {
        if let component = model.level.grid[segment.from] ?? model.placements[segment.from] {
            let direction = component.direction
            return CGVector(dx: CGFloat(direction.dx), dy: CGFloat(direction.dy))
        }
        return .zero
    }

    private func beamNode(from: CGPoint, to: CGPoint, color: BeamColor) -> SKNode {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        let skColor = skColor(of: color)

        let container = SKNode()
        // 外側のにじみ(加算合成で発光風)
        let glow = SKShapeNode(path: path)
        glow.strokeColor = skColor.withAlphaComponent(0.35)
        glow.lineWidth = cellSize * 0.22
        glow.lineCap = .round
        glow.blendMode = .add
        container.addChild(glow)
        // 中心線
        let core = SKShapeNode(path: path)
        core.strokeColor = skColor
        core.lineWidth = cellSize * 0.07
        core.lineCap = .round
        core.blendMode = .add
        container.addChild(core)

        // 光の粒子(2層): 進行方向へ流れるストリーム+ビーム全体で舞う飛沫
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        if length > cellSize * 0.3 {
            let cells = length / cellSize
            let angle = atan2(dy, dx)
            // 進行方向と直交する単位ベクトル(ビームは軸平行なので positionRange に使える)
            let perp = CGVector(dx: -sin(angle), dy: cos(angle))

            // 層1: 光源→先端へ流れるストリーム(指向性の表現)
            let flow = SKEmitterNode()
            flow.particleTexture = Self.particleTexture
            flow.position = from
            flow.emissionAngle = angle
            flow.emissionAngleRange = 0.06
            let speed = cellSize * 2.4
            flow.particleSpeed = speed
            flow.particleLifetime = length / speed
            flow.particleBirthRate = 6 * cells
            // ビームの太さぶんだけ発生位置を散らす
            flow.particlePositionRange = CGVector(dx: abs(perp.dx) * cellSize * 0.16,
                                                  dy: abs(perp.dy) * cellSize * 0.16)
            flow.particleScale = cellSize / 240
            flow.particleScaleRange = cellSize / 300
            flow.particleAlpha = 0.9
            flow.particleAlphaRange = 0.3
            flow.particleColor = skColor
            flow.particleColorBlendFactor = 0.6
            flow.particleBlendMode = .add
            // 生成直後からビーム全体に粒が行き渡った状態にする
            flow.advanceSimulationTime(TimeInterval(flow.particleLifetime + 0.3))
            container.addChild(flow)

            // 層2: ビーム全域でランダムに弾ける飛沫(粒子が飛んでいる質感)
            let sparks = SKEmitterNode()
            sparks.particleTexture = Self.particleTexture
            sparks.position = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            // ビームに沿った細長い箱から発生させる
            sparks.particlePositionRange = CGVector(dx: abs(dx) + abs(perp.dx) * cellSize * 0.1,
                                                    dy: abs(dy) + abs(perp.dy) * cellSize * 0.1)
            sparks.emissionAngleRange = .pi * 2
            sparks.particleSpeed = cellSize * 0.55
            sparks.particleSpeedRange = cellSize * 0.4
            sparks.particleLifetime = 0.45
            sparks.particleLifetimeRange = 0.25
            sparks.particleBirthRate = 5 * cells
            sparks.particleScale = cellSize / 320
            sparks.particleScaleRange = cellSize / 400
            sparks.particleAlpha = 0.8
            sparks.particleAlphaSpeed = -1.6
            sparks.particleColor = skColor
            sparks.particleColorBlendFactor = 0.5
            sparks.particleBlendMode = .add
            sparks.advanceSimulationTime(0.7)
            container.addChild(sparks)
        }
        return container
    }

    private func renderComponents() {
        componentsNode.removeAllChildren()
        effectsNode.children.filter { $0.name == "goalSparkle" }.forEach { $0.removeFromParent() }

        var board = model.level.grid
        board.merge(model.placements) { fixed, _ in fixed }
        let satisfied = model.satisfiedGoals
        for (position, component) in board {
            let node = componentNode(for: component, at: position)
            node.position = point(of: position)
            componentsNode.addChild(node)
            // 作動中のゴールにはきらめきを添える
            if component.kind == .goal, satisfied.contains(position) {
                let sparkle = Self.makeSparkleEmitter(
                    color: skColor(of: component.color ?? .white), cellSize: cellSize)
                sparkle.name = "goalSparkle"
                sparkle.position = point(of: position)
                effectsNode.addChild(sparkle)
            }
        }
    }

    private func skColor(of color: BeamColor) -> SKColor {
        SKColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1)
    }

    private func componentNode(for component: PlacedComponent, at position: GridPosition) -> SKNode {
        let node = SKNode()
        let unit = cellSize * 0.36
        let color = component.color.map { skColor(of: $0) }

        switch component.kind {
        case .source:
            let body = SKShapeNode(circleOfRadius: unit * 0.8)
            body.fillColor = SKColor(red: 1, green: 0.95, blue: 0.75, alpha: 1)
            body.strokeColor = .white
            node.addChild(body)
            node.addChild(arrowNode(length: unit * 1.4, color: .white, direction: component.direction))

        case .goal:
            let diamond = polygonNode(points: [
                CGPoint(x: 0, y: unit), CGPoint(x: unit, y: 0),
                CGPoint(x: 0, y: -unit), CGPoint(x: -unit, y: 0),
            ])
            let satisfied = model.satisfiedGoals.contains(position)
            diamond.strokeColor = color ?? .white
            diamond.lineWidth = 3
            diamond.fillColor = satisfied ? (color ?? .white).withAlphaComponent(0.85) : .clear
            node.addChild(diamond)

        case .wall:
            let block = SKShapeNode(rectOf: CGSize(width: cellSize * 0.86, height: cellSize * 0.86),
                                    cornerRadius: cellSize * 0.08)
            block.fillColor = SKColor(white: 0.35, alpha: 1)
            block.strokeColor = SKColor(white: 0.5, alpha: 1)
            node.addChild(block)

        case .mirror:
            node.addChild(diagonalNode(rotation: component.rotation, unit: unit,
                                       color: SKColor(red: 0.7, green: 0.9, blue: 1, alpha: 1),
                                       lineWidth: 4))

        case .splitter:
            // ハーフミラー: 鏡より薄い色の斜線+透過を示す点線
            let line = diagonalNode(rotation: component.rotation, unit: unit,
                                    color: SKColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.55),
                                    lineWidth: 4)
            node.addChild(line)
            let dashed = CGMutablePath()
            dashed.move(to: CGPoint(x: -unit, y: 0))
            dashed.addLine(to: CGPoint(x: unit, y: 0))
            let through = SKShapeNode(path: dashed.copy(dashingWithPhase: 0,
                                                        lengths: [unit * 0.25, unit * 0.2]))
            through.strokeColor = SKColor(white: 1, alpha: 0.5)
            through.lineWidth = 2
            node.addChild(through)

        case .shifter:
            // カラーシフタ: 円環+R/G/Bの3点で「色が巡回する」ことを表す
            let ring = SKShapeNode(circleOfRadius: unit * 0.8)
            ring.strokeColor = SKColor(white: 1, alpha: 0.7)
            ring.lineWidth = 2
            node.addChild(ring)
            let dotColors: [SKColor] = [.red, .green, .blue]
            for (index, dotColor) in dotColors.enumerated() {
                // 上から時計回りに R→G→B を配置
                let angle = CGFloat.pi / 2 - CGFloat(index) * 2 * CGFloat.pi / 3
                let dot = SKShapeNode(circleOfRadius: unit * 0.18)
                dot.fillColor = dotColor
                dot.strokeColor = .clear
                dot.blendMode = .add
                dot.position = CGPoint(x: cos(angle) * unit * 0.8, y: sin(angle) * unit * 0.8)
                node.addChild(dot)
            }

        case .warp:
            // ワープゲート: ペア色の二重リング+回転する破線で「渦」を表す
            let tint = color ?? SKColor.cyan
            let outer = SKShapeNode(circleOfRadius: unit * 0.85)
            outer.strokeColor = tint
            outer.lineWidth = 3
            outer.glowWidth = 2
            node.addChild(outer)
            let dashed = SKShapeNode(
                path: CGPath(ellipseIn: CGRect(x: -unit * 0.5, y: -unit * 0.5,
                                               width: unit, height: unit), transform: nil)
                    .copy(dashingWithPhase: 0, lengths: [unit * 0.35, unit * 0.25]))
            dashed.strokeColor = tint.withAlphaComponent(0.8)
            dashed.lineWidth = 2
            dashed.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4)))
            node.addChild(dashed)

        case .prism:
            let triangle = polygonNode(points: [
                CGPoint(x: 0, y: unit), CGPoint(x: unit, y: -unit), CGPoint(x: -unit, y: -unit),
            ])
            triangle.strokeColor = .white
            triangle.fillColor = SKColor(white: 1, alpha: 0.2)
            node.addChild(triangle)

        case .filter:
            let pane = SKShapeNode(rectOf: CGSize(width: cellSize * 0.7, height: cellSize * 0.7),
                                   cornerRadius: cellSize * 0.1)
            pane.fillColor = (color ?? .white).withAlphaComponent(0.45)
            pane.strokeColor = color ?? .white
            pane.lineWidth = 2
            node.addChild(pane)

        case .combiner:
            let accent = SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
            let body = SKShapeNode(circleOfRadius: unit * 0.9)
            body.strokeColor = accent
            body.lineWidth = 3
            body.fillColor = accent.withAlphaComponent(0.15)
            node.addChild(body)
            let cross = CGMutablePath()
            cross.move(to: CGPoint(x: -unit * 0.4, y: 0))
            cross.addLine(to: CGPoint(x: unit * 0.4, y: 0))
            cross.move(to: CGPoint(x: 0, y: -unit * 0.4))
            cross.addLine(to: CGPoint(x: 0, y: unit * 0.4))
            let plus = SKShapeNode(path: cross)
            plus.strokeColor = accent
            plus.lineWidth = 2
            node.addChild(plus)
            node.addChild(arrowNode(length: unit * 1.5, color: accent, direction: component.direction))
        }

        if !component.fixed {
            // プレイヤー配置の部品はうっすら台座を敷いて区別する
            let base = SKShapeNode(rectOf: CGSize(width: cellSize * 0.92, height: cellSize * 0.92),
                                   cornerRadius: cellSize * 0.12)
            base.fillColor = SKColor(white: 1, alpha: 0.06)
            base.strokeColor = SKColor(white: 1, alpha: 0.25)
            base.zPosition = -1
            node.addChild(base)
        }
        return node
    }

    /// 鏡/スプリッタの斜線("/" または "\")
    private func diagonalNode(rotation: Int, unit: CGFloat, color: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let isSlash = (rotation / 90) % 2 == 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -unit, y: isSlash ? -unit : unit))
        path.addLine(to: CGPoint(x: unit, y: isSlash ? unit : -unit))
        let line = SKShapeNode(path: path)
        line.strokeColor = color
        line.lineWidth = lineWidth
        line.lineCap = .round
        return line
    }

    /// 出力方向を示す矢印
    private func arrowNode(length: CGFloat, color: SKColor, direction: Direction) -> SKNode {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: length, y: 0))
        path.move(to: CGPoint(x: length * 0.6, y: length * 0.25))
        path.addLine(to: CGPoint(x: length, y: 0))
        path.addLine(to: CGPoint(x: length * 0.6, y: -length * 0.25))
        let arrow = SKShapeNode(path: path)
        arrow.strokeColor = color
        arrow.lineWidth = 2
        arrow.lineCap = .round
        // Direction は up=0 から時計回り。ノード回転は反時計回り正なので変換する
        arrow.zRotation = CGFloat.pi / 2 - CGFloat(direction.rawValue) * CGFloat.pi / 2
        return arrow
    }

    private func polygonNode(points: [CGPoint]) -> SKShapeNode {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return SKShapeNode(path: path)
    }

    // MARK: - パーティクル

    /// パーティクル用の丸いテクスチャ(放射状グラデーション)
    private static let particleTexture: SKTexture = {
        let diameter: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray, locations: [0, 1]) else { return }
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                                 endCenter: center, endRadius: diameter / 2, options: [])
        }
        return SKTexture(image: image)
    }()

    /// 作動中ゴールの継続的なきらめき
    private static func makeSparkleEmitter(color: SKColor, cellSize: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = particleTexture
        emitter.particleBirthRate = 18
        emitter.particleLifetime = 0.7
        emitter.particleLifetimeRange = 0.3
        emitter.particleSpeed = cellSize * 0.5
        emitter.particleSpeedRange = cellSize * 0.3
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.2
        emitter.particleScale = cellSize / 220
        emitter.particleScaleRange = cellSize / 400
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        return emitter
    }

    /// クリア時のバースト(全ゴールから一斉に放出)
    private func emitClearBurst() {
        for position in model.satisfiedGoals {
            let target = model.level.grid[position]?.color ?? .white
            let emitter = SKEmitterNode()
            emitter.particleTexture = Self.particleTexture
            emitter.particleBirthRate = 400
            emitter.numParticlesToEmit = 90
            emitter.particleLifetime = 1.2
            emitter.particleLifetimeRange = 0.4
            emitter.particleSpeed = cellSize * 2.2
            emitter.particleSpeedRange = cellSize * 1.2
            emitter.emissionAngleRange = .pi * 2
            emitter.yAcceleration = -cellSize * 1.5
            emitter.particleAlpha = 1
            emitter.particleAlphaSpeed = -0.8
            emitter.particleScale = cellSize / 160
            emitter.particleScaleSpeed = -cellSize / 500
            emitter.particleColor = skColor(of: target)
            emitter.particleColorBlendFactor = 0.8
            emitter.particleBlendMode = .add
            emitter.position = point(of: position)
            effectsNode.addChild(emitter)
            emitter.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
        }
    }

    // MARK: - タップ / ドラッグ操作

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first else { return }
        let scenePoint = touch.location(in: self)
        touchStartPoint = scenePoint
        isDragging = false
        if let cell = geometry.cell(atScenePoint: scenePoint), model.placements[cell] != nil {
            // プレイヤーが置いた部品の上 → 移動ドラッグ候補
            dragMode = .moveComponent(from: cell)
        } else if model.canPlaceSelectedItem {
            // 部品選択中 → ドラッグで配置場所のプレビュー
            dragMode = .placePreview
        } else {
            dragMode = .none
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first else { return }
        let scenePoint = touch.location(in: self)

        if !isDragging {
            let moved = hypot(scenePoint.x - touchStartPoint.x, scenePoint.y - touchStartPoint.y)
            guard moved > cellSize * 0.25 else { return }
            switch dragMode {
            case .moveComponent(let source):
                isDragging = true
                beginMoveGhost(for: source)
            case .placePreview:
                isDragging = true
                beginPlacementGhost()
            case .none:
                return
            }
        }
        updateGhost(at: scenePoint)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first else { return }
        let scenePoint = touch.location(in: self)
        defer { endDrag() }

        guard isDragging else {
            // ドラッグでなければタップ: 空セルは選択部品の配置、配置済みは回転
            if let cell = geometry.cell(atScenePoint: scenePoint) {
                model.handleTap(at: cell)
            }
            return
        }
        switch dragMode {
        case .moveComponent(let source):
            if let target = geometry.cell(atScenePoint: scenePoint) {
                model.moveComponent(from: source, to: target)
            } else {
                // 盤外へドラッグ → 在庫へ回収
                model.removeComponent(at: source)
            }
        case .placePreview:
            if let item = model.selectedItem,
               let target = geometry.cell(atScenePoint: scenePoint) {
                model.placeItem(item, at: target)
            }
        case .none:
            break
        }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        endDrag()
    }

    /// 配置済み部品の移動ゴースト(元の部品は薄くする)
    private func beginMoveGhost(for cell: GridPosition) {
        guard let component = model.placements[cell] else { return }
        makeGhost(for: component)
        dragGhost?.position = point(of: cell)
        for node in componentsNode.children where node.position == point(of: cell) {
            node.alpha = 0.25
        }
    }

    /// 選択中アイテムの配置プレビューゴースト
    private func beginPlacementGhost() {
        guard let item = model.selectedItem else { return }
        makeGhost(for: PlacedComponent(kind: item.kind, rotation: 0, color: item.color, fixed: false))
    }

    /// 半透明ゴースト+配置可否ハイライトを生成する
    private func makeGhost(for component: PlacedComponent) {
        let ghost = componentNode(for: component, at: GridPosition(x: -1, y: -1))
        ghost.alpha = 0.55
        ghost.zPosition = 100
        boardNode.addChild(ghost)
        dragGhost = ghost

        let highlight = SKShapeNode(rectOf: CGSize(width: cellSize, height: cellSize))
        highlight.lineWidth = 2
        highlight.zPosition = 90
        highlight.isHidden = true
        boardNode.addChild(highlight)
        ghostHighlight = highlight
    }

    /// ゴーストを指の位置に追従させ、セル上ではスナップ+配置可否を色で示す
    private func updateGhost(at scenePoint: CGPoint) {
        guard let ghost = dragGhost else { return }
        if let cell = geometry.cell(atScenePoint: scenePoint) {
            ghost.position = point(of: cell)
            let placeable: Bool
            switch dragMode {
            case .moveComponent(let source):
                placeable = cell == source ||
                    (model.level.grid[cell] == nil && model.placements[cell] == nil)
            case .placePreview:
                placeable = model.level.grid[cell] == nil && model.placements[cell] == nil
            case .none:
                placeable = false
            }
            if let highlight = ghostHighlight {
                highlight.isHidden = false
                highlight.position = point(of: cell)
                let tint: SKColor = placeable
                    ? SKColor(red: 0.4, green: 1, blue: 0.6, alpha: 1)
                    : SKColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
                highlight.strokeColor = tint
                highlight.fillColor = tint.withAlphaComponent(0.18)
            }
        } else {
            // 盤外: 指に追従(移動ドラッグでは「回収」の合図になる)
            ghost.position = convert(scenePoint, to: boardNode)
            ghostHighlight?.isHidden = true
        }
    }

    private func endDrag() {
        dragGhost?.removeFromParent()
        dragGhost = nil
        ghostHighlight?.removeFromParent()
        ghostHighlight = nil
        dragMode = .none
        isDragging = false
        renderedRevision = -1 // 薄くした表示を元に戻すため再描画
    }
}
