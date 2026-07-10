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
    private var dragSourceCell: GridPosition?
    private var dragGhost: SKNode?
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
        // プレイヤーが置いた部品の上ならドラッグ候補にする
        if let cell = geometry.cell(atScenePoint: scenePoint), model.placements[cell] != nil {
            dragSourceCell = cell
        } else {
            dragSourceCell = nil
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first, let sourceCell = dragSourceCell else { return }
        let scenePoint = touch.location(in: self)
        if !isDragging {
            let moved = hypot(scenePoint.x - touchStartPoint.x, scenePoint.y - touchStartPoint.y)
            guard moved > cellSize * 0.25 else { return }
            isDragging = true
            beginDragGhost(for: sourceCell)
        }
        dragGhost?.position = convert(scenePoint, to: boardNode)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first else { return }
        let scenePoint = touch.location(in: self)
        defer { endDrag() }

        guard isDragging, let sourceCell = dragSourceCell else {
            // ドラッグでなければタップ: 配置 or 回転
            if let cell = geometry.cell(atScenePoint: scenePoint) {
                model.handleTap(at: cell)
            }
            return
        }
        if let target = geometry.cell(atScenePoint: scenePoint) {
            model.moveComponent(from: sourceCell, to: target)
        } else {
            // 盤外へドラッグ → 在庫へ回収
            model.removeComponent(at: sourceCell)
        }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        endDrag()
    }

    /// ドラッグ中のゴースト表示を作る(元の部品は半透明にする)
    private func beginDragGhost(for cell: GridPosition) {
        guard let component = model.placements[cell] else { return }
        let ghost = componentNode(for: component, at: cell)
        ghost.alpha = 0.75
        ghost.zPosition = 100
        ghost.setScale(1.1)
        ghost.position = point(of: cell)
        boardNode.addChild(ghost)
        dragGhost = ghost
        // 元の位置のノードを薄くする(次の再描画で復元される)
        for node in componentsNode.children where node.position == point(of: cell) {
            node.alpha = 0.25
        }
    }

    private func endDrag() {
        dragGhost?.removeFromParent()
        dragGhost = nil
        dragSourceCell = nil
        isDragging = false
        renderedRevision = -1 // 薄くした表示を元に戻すため再描画
    }
}
