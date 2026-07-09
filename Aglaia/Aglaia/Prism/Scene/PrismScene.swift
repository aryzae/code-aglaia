//
//  PrismScene.swift
//  Aglaia
//
//  盤面・部品・ビームの描画とタップ操作を担う SpriteKit シーン。
//  状態は GameModel を共有し、変更検知は revision の比較で行う。
//

import SpriteKit
import SwiftUI

final class PrismScene: SKScene {
    private let model: GameModel

    private let boardNode = SKNode()
    private let gridNode = SKNode()
    private let beamsNode = SKNode()
    private let componentsNode = SKNode()

    private var cellSize: CGFloat = 0
    private var renderedRevision = -1

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
        layoutBoard()
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
        }
    }

    // MARK: - レイアウト

    private func layoutBoard() {
        let gridCount = CGFloat(model.level.size)
        let boardLength = min(size.width, size.height) * 0.94
        cellSize = boardLength / gridCount
        boardNode.position = CGPoint(x: (size.width - boardLength) / 2,
                                     y: (size.height - boardLength) / 2)
        renderGrid()
        renderedRevision = -1 // セルサイズが変わったので部品とビームも再描画
    }

    private func point(of position: GridPosition) -> CGPoint {
        CGPoint(x: (CGFloat(position.x) + 0.5) * cellSize,
                y: (CGFloat(position.y) + 0.5) * cellSize)
    }

    private func cell(at location: CGPoint) -> GridPosition? {
        let local = convert(location, to: boardNode)
        let position = GridPosition(x: Int(floor(local.x / cellSize)),
                                    y: Int(floor(local.y / cellSize)))
        return model.level.contains(position) ? position : nil
    }

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
        let skColor = SKColor(red: CGFloat(color.r), green: CGFloat(color.g),
                              blue: CGFloat(color.b), alpha: 1)

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
        var board = model.level.grid
        board.merge(model.placements) { fixed, _ in fixed }
        for (position, component) in board {
            let node = componentNode(for: component, at: position)
            node.position = point(of: position)
            componentsNode.addChild(node)
        }
    }

    private func componentNode(for component: PlacedComponent, at position: GridPosition) -> SKNode {
        let node = SKNode()
        let unit = cellSize * 0.36
        let color = component.color.map {
            SKColor(red: CGFloat($0.r), green: CGFloat($0.g), blue: CGFloat($0.b), alpha: 1)
        }

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
            let isSlash = (component.rotation / 90) % 2 == 0
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -unit, y: isSlash ? -unit : unit))
            path.addLine(to: CGPoint(x: unit, y: isSlash ? unit : -unit))
            let line = SKShapeNode(path: path)
            line.strokeColor = SKColor(red: 0.7, green: 0.9, blue: 1, alpha: 1)
            line.lineWidth = 4
            line.lineCap = .round
            node.addChild(line)

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
            let body = SKShapeNode(circleOfRadius: unit * 0.9)
            body.strokeColor = SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
            body.lineWidth = 3
            body.fillColor = SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 0.15)
            node.addChild(body)
            let cross = CGMutablePath()
            cross.move(to: CGPoint(x: -unit * 0.4, y: 0))
            cross.addLine(to: CGPoint(x: unit * 0.4, y: 0))
            cross.move(to: CGPoint(x: 0, y: -unit * 0.4))
            cross.addLine(to: CGPoint(x: 0, y: unit * 0.4))
            let plus = SKShapeNode(path: cross)
            plus.strokeColor = SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
            plus.lineWidth = 2
            node.addChild(plus)
            node.addChild(arrowNode(length: unit * 1.5,
                                    color: SKColor(red: 1, green: 0.8, blue: 0.4, alpha: 1),
                                    direction: component.direction))
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

    // MARK: - タップ操作

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first,
              let position = cell(at: touch.location(in: self)) else { return }
        model.handleTap(at: position)
    }
}
