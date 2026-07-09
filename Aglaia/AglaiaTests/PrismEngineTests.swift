//
//  PrismEngineTests.swift
//  AglaiaTests
//
//  BeamTracer(レイキャスト)とステージJSONデコードのテスト。
//  各ステージの想定解が実際にクリアになることを確認する。
//

import XCTest
@testable import Aglaia

final class PrismEngineTests: XCTestCase {
    // MARK: - ステージ定義(Resources/Levels/*.json と同内容)

    private func makeStage1() -> Level {
        Level(
            id: "level_01", title: "はじめての光", size: 6, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 2): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 3, y: 2): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 5, y: 4): PlacedComponent(kind: .goal, color: .white, fixed: true),
            ],
            inventory: [InventoryItem(kind: .mirror, color: nil, count: 2)]
        )
    }

    private func makeStage2() -> Level {
        Level(
            id: "level_02", title: "あかい光だけを", size: 6, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 2): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 2, y: 4): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 3, y: 0): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 5, y: 2): PlacedComponent(kind: .goal, color: .red, fixed: true),
            ],
            inventory: [
                InventoryItem(kind: .filter, color: .red, count: 1),
                InventoryItem(kind: .mirror, color: nil, count: 2),
            ]
        )
    }

    private func makeStage3() -> Level {
        Level(
            id: "level_03", title: "むらさきの結晶", size: 7, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 3): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 3, y: 2): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 5, y: 1): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 6, y: 3): PlacedComponent(
                    kind: .goal, color: BeamColor(r: 1, g: 0, b: 1), fixed: true),
            ],
            inventory: [
                InventoryItem(kind: .prism, color: nil, count: 1),
                InventoryItem(kind: .combiner, color: nil, count: 1),
                InventoryItem(kind: .mirror, color: nil, count: 3),
            ]
        )
    }

    // MARK: - Stage 1: 鏡で光を導く

    func testStage1_初期状態は未クリア() {
        let result = BeamTracer.trace(level: makeStage1(), placements: [:])
        XCTAssertFalse(result.solved)
        XCTAssertTrue(result.goalColors.isEmpty)
    }

    func testStage1_鏡2枚でクリア() {
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 2): PlacedComponent(kind: .mirror, rotation: 0),
            GridPosition(x: 2, y: 4): PlacedComponent(kind: .mirror, rotation: 0),
        ]
        let result = BeamTracer.trace(level: makeStage1(), placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 5, y: 4)], .white)
    }

    func testStage1_鏡の向きが誤っていると未クリア() {
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 2): PlacedComponent(kind: .mirror, rotation: 90),
            GridPosition(x: 2, y: 4): PlacedComponent(kind: .mirror, rotation: 0),
        ]
        let result = BeamTracer.trace(level: makeStage1(), placements: placements)
        XCTAssertFalse(result.solved)
    }

    // MARK: - Stage 2: 赤フィルタ

    func testStage2_白のままでは未クリア() {
        let result = BeamTracer.trace(level: makeStage2(), placements: [:])
        XCTAssertFalse(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 5, y: 2)], .white)
    }

    func testStage2_赤フィルタでクリア() {
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 2): PlacedComponent(kind: .filter, rotation: 0, color: .red),
        ]
        let result = BeamTracer.trace(level: makeStage2(), placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 5, y: 2)], .red)
    }

    // MARK: - Stage 3: 分光と合成

    func testStage3_プリズムと合成器で紫を作りクリア() {
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 3): PlacedComponent(kind: .prism, rotation: 0),
            GridPosition(x: 2, y: 1): PlacedComponent(kind: .mirror, rotation: 90),
            GridPosition(x: 4, y: 1): PlacedComponent(kind: .mirror, rotation: 0),
            GridPosition(x: 4, y: 3): PlacedComponent(kind: .combiner, rotation: 90),
        ]
        let result = BeamTracer.trace(level: makeStage3(), placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 6, y: 3)], BeamColor(r: 1, g: 0, b: 1))
    }

    func testStage3_赤成分だけでは未クリア() {
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 3): PlacedComponent(kind: .prism, rotation: 0),
        ]
        let result = BeamTracer.trace(level: makeStage3(), placements: placements)
        XCTAssertFalse(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 6, y: 3)], .red)
    }

    // MARK: - 個別部品の挙動

    func testMirror_反射方向() {
        XCTAssertEqual(BeamTracer.reflect(.right, mirrorRotation: 0), .up)
        XCTAssertEqual(BeamTracer.reflect(.up, mirrorRotation: 0), .right)
        XCTAssertEqual(BeamTracer.reflect(.down, mirrorRotation: 90), .right)
        XCTAssertEqual(BeamTracer.reflect(.right, mirrorRotation: 90), .down)
    }

    func testCombiner_出力が自分の入力に戻るループでも停止する() {
        // 合成器の出力を鏡3枚で自分の入力面へ戻すフィードバック構成。
        // trace が完了すること自体が無限ループ対策の確認になる
        let level = Level(
            id: "loop", title: "loop", size: 5, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 2): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 4, y: 4): PlacedComponent(kind: .goal, color: .white, fixed: true),
            ],
            inventory: []
        )
        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 2): PlacedComponent(kind: .combiner, rotation: 0), // 出力: 上
            GridPosition(x: 2, y: 3): PlacedComponent(kind: .mirror, rotation: 90),  // 上→左
            GridPosition(x: 1, y: 3): PlacedComponent(kind: .mirror, rotation: 0),   // 左→下
            GridPosition(x: 1, y: 2): PlacedComponent(kind: .mirror, rotation: 90),  // 下→右(入力面へ)
        ]
        let result = BeamTracer.trace(level: level, placements: placements)
        XCTAssertFalse(result.solved)
        XCTAssertTrue(result.goalColors.isEmpty)
    }

    func testGoal_加法混色で判定される() {
        // 2つの光源から R と B を同じゴールに入れて紫になる
        let level = Level(
            id: "mix", title: "mix", size: 5, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 2): PlacedComponent(kind: .source, rotation: 90, color: .red, fixed: true),
                GridPosition(x: 2, y: 0): PlacedComponent(kind: .source, rotation: 0, color: .blue, fixed: true),
                GridPosition(x: 2, y: 2): PlacedComponent(kind: .goal, color: BeamColor(r: 1, g: 0, b: 1), fixed: true),
            ],
            inventory: []
        )
        let result = BeamTracer.trace(level: level, placements: [:])
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 2, y: 2)], BeamColor(r: 1, g: 0, b: 1))
    }

    // MARK: - JSON デコード

    func testLevel_JSONデコード() throws {
        let json = """
        {
          "id": "test",
          "title": "テスト",
          "size": 6,
          "tolerance": 0.15,
          "grid": {
            "0,2": { "kind": "source", "rotation": 90, "fixed": true },
            "5,2": { "kind": "goal", "rotation": 0, "fixed": true,
                     "color": { "r": 1, "g": 0, "b": 0 } }
          },
          "inventory": [
            { "kind": "filter", "color": { "r": 1, "g": 0, "b": 0 }, "count": 1 },
            { "kind": "mirror", "count": 2 }
          ]
        }
        """
        let level = try JSONDecoder().decode(Level.self, from: Data(json.utf8))
        XCTAssertEqual(level.size, 6)
        XCTAssertEqual(level.grid[GridPosition(x: 0, y: 2)]?.kind, .source)
        XCTAssertEqual(level.grid[GridPosition(x: 5, y: 2)]?.color, .red)
        XCTAssertEqual(level.inventory.count, 2)
        XCTAssertEqual(level.inventory[0].color, .red)
    }

    func testバンドルの全ステージが読み込める() {
        let levels = LevelLoader.loadAll()
        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(levels.map(\.id), ["level_01", "level_02", "level_03"])
    }
}
