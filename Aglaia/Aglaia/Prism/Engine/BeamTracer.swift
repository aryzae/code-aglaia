//
//  BeamTracer.swift
//  Aglaia
//
//  光線(ビーム)のレイキャスト計算。盤面が変化したときだけ呼び出す。
//  アルゴリズムの詳細は spec_prism.md §7 を参照。
//

import Foundation

/// レイキャストの結果
struct TraceResult {
    /// 描画用の線分一覧
    var segments: [BeamSegment] = []
    /// 各ゴールが受け取った色(加法混色済み)
    var goalColors: [GridPosition: BeamColor] = [:]
    /// 全ゴールが目標色を許容誤差内で受け取ったか
    var solved: Bool = false
}

enum BeamTracer {
    /// 追跡中のビーム。origin(発射元セル)から direction へ進む
    private struct Beam {
        var origin: GridPosition
        var direction: Direction
        var color: BeamColor
    }

    /// ループ検出用キー(発射セル・方向・量子化色)
    private struct VisitKey: Hashable {
        var position: GridPosition
        var direction: Direction
        var quantizedColor: Int
    }

    /// 合成器の全入力が出そろうまで再計算を繰り返すための上限回数
    private static let maxCombinerIterations = 8

    /// 固定配置とプレイヤー配置を合成した盤面でビームを計算する
    static func trace(level: Level, placements: [GridPosition: PlacedComponent]) -> TraceResult {
        var board = level.grid
        board.merge(placements) { fixed, _ in fixed }

        // 合成器は「全入力の合算」を出力するため、入力が確定するまで
        // 盤面全体の追跡を繰り返す(入力は単調に増えるため必ず収束する)
        var combinerInputs: [GridPosition: BeamColor] = [:]
        var result = TraceResult()

        for _ in 0 ..< maxCombinerIterations {
            let pass = tracePass(level: level, board: board, combinerInputs: combinerInputs)
            let quantize = { (inputs: [GridPosition: BeamColor]) in
                inputs.mapValues(\.quantized)
            }
            let converged = quantize(pass.combinerInputs) == quantize(combinerInputs)
            combinerInputs = pass.combinerInputs
            result = pass.result
            if converged { break }
        }

        // クリア判定: 全ゴールが目標色を許容誤差内で受け取っている
        result.solved = board.allSatisfy { position, component in
            guard component.kind == .goal else { return true }
            guard let target = component.color, let received = result.goalColors[position] else {
                return component.kind != .goal
            }
            return received.distance(to: target) <= level.tolerance
        } && board.contains { $0.value.kind == .goal }

        return result
    }

    /// 1回分の全ビーム追跡。合成器の出力には前回パスの入力合算を使う
    private static func tracePass(
        level: Level,
        board: [GridPosition: PlacedComponent],
        combinerInputs: [GridPosition: BeamColor]
    ) -> (result: TraceResult, combinerInputs: [GridPosition: BeamColor]) {
        var result = TraceResult()
        var newCombinerInputs: [GridPosition: BeamColor] = [:]
        var visited = Set<VisitKey>()
        var queue: [Beam] = []

        func enqueue(_ beam: Beam) {
            guard !beam.color.isNegligible else { return }
            let key = VisitKey(position: beam.origin, direction: beam.direction,
                               quantizedColor: beam.color.quantized)
            guard visited.insert(key).inserted else { return }
            queue.append(beam)
        }

        // 光源からの発射
        for (position, component) in board where component.kind == .source {
            enqueue(Beam(origin: position, direction: component.direction,
                         color: component.color ?? .white))
        }
        // 前回パスまでに入力を受け取った合成器からの出力
        for (position, input) in combinerInputs {
            guard let combiner = board[position], combiner.kind == .combiner else { continue }
            enqueue(Beam(origin: position, direction: combiner.direction, color: input))
        }

        while let beam = queue.popLast() {
            var current = beam.origin
            while true {
                let next = current.advanced(beam.direction)

                // 盤外へ抜けた
                guard level.contains(next) else {
                    result.segments.append(BeamSegment(from: beam.origin, to: current,
                                                       exitsBoard: true, color: beam.color))
                    break
                }
                // 空セルなら直進
                guard let component = board[next] else {
                    current = next
                    continue
                }

                // 部品に到達: ここまでの線分を確定して部品ごとの挙動へ
                result.segments.append(BeamSegment(from: beam.origin, to: next,
                                                   exitsBoard: false, color: beam.color))
                switch component.kind {
                case .wall, .source:
                    break // 吸収して停止

                case .goal:
                    let mixed = result.goalColors[next].map { $0.mixed(with: beam.color) } ?? beam.color
                    result.goalColors[next] = mixed

                case .mirror:
                    let reflected = reflect(beam.direction, mirrorRotation: component.rotation)
                    enqueue(Beam(origin: next, direction: reflected, color: beam.color))

                case .filter:
                    let filtered = beam.color.filtered(by: component.color ?? .white)
                    enqueue(Beam(origin: next, direction: beam.direction, color: filtered))

                case .prism:
                    // 分光: R は直進、G は左折、B は右折(入射方向基準)
                    enqueue(Beam(origin: next, direction: beam.direction,
                                 color: BeamColor(r: beam.color.r, g: 0, b: 0)))
                    enqueue(Beam(origin: next, direction: beam.direction.turnedLeft,
                                 color: BeamColor(r: 0, g: beam.color.g, b: 0)))
                    enqueue(Beam(origin: next, direction: beam.direction.turnedRight,
                                 color: BeamColor(r: 0, g: 0, b: beam.color.b)))

                case .splitter:
                    // ハーフミラー: 鏡と同じ向き規則で半分を反射し、残り半分は直進
                    let reflected = reflect(beam.direction, mirrorRotation: component.rotation)
                    enqueue(Beam(origin: next, direction: reflected, color: beam.color.scaled(by: 0.5)))
                    enqueue(Beam(origin: next, direction: beam.direction, color: beam.color.scaled(by: 0.5)))

                case .combiner:
                    // 出力面(rotation の向き)へ入射した光は吸収。それ以外の面は入力として蓄積
                    if beam.direction != component.direction.opposite {
                        let mixed = newCombinerInputs[next].map { $0.mixed(with: beam.color) } ?? beam.color
                        newCombinerInputs[next] = mixed
                    }
                }
                break
            }
        }

        return (result, newCombinerInputs)
    }

    /// 鏡の反射。rotation 0/180 = "/"(右→上)、90/270 = "\"(右→下)
    static func reflect(_ direction: Direction, mirrorRotation: Int) -> Direction {
        let isSlash = (mirrorRotation / 90) % 2 == 0
        if isSlash {
            switch direction {
            case .right: return .up
            case .up: return .right
            case .left: return .down
            case .down: return .left
            }
        } else {
            switch direction {
            case .right: return .down
            case .down: return .right
            case .left: return .up
            case .up: return .left
            }
        }
    }
}
