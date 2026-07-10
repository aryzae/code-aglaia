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
            id: "level_001", title: "はじめての光", size: 6, tolerance: 0.15,
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
            id: "level_002", title: "あかい光だけを", size: 6, tolerance: 0.15,
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
            id: "level_003", title: "むらさきの結晶", size: 7, tolerance: 0.15,
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
        XCTAssertEqual(levels.count, 26)
        XCTAssertEqual(levels.first?.id, "level_001")
        XCTAssertEqual(levels.last?.id, "level_051")
    }

    // MARK: - カラーシフタ

    func testShifter_成分がRGBRと巡回する() {
        XCTAssertEqual(BeamColor.red.shifted, .green)
        XCTAssertEqual(BeamColor.green.shifted, .blue)
        XCTAssertEqual(BeamColor.blue.shifted, .red)
        // 白は巡回しても白のまま
        XCTAssertEqual(BeamColor.white.shifted, .white)
        // 半端な強度も成分ごとに巡回する
        XCTAssertEqual(BeamColor(r: 0.5, g: 0, b: 1).shifted, BeamColor(r: 1, g: 0.5, b: 0))
    }

    func testShifter_赤い光源から緑を作る() {
        // ステージ22「くるりと色がわり」と同じ構成
        let level = Level(
            id: "level_022", title: "くるりと色がわり", size: 8, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 4): PlacedComponent(kind: .source, rotation: 90,
                                                          color: .red, fixed: true),
                GridPosition(x: 7, y: 4): PlacedComponent(kind: .goal, color: .green, fixed: true),
            ],
            inventory: [InventoryItem(kind: .shifter, color: nil, count: 1)]
        )
        // 赤のままでは未クリア
        XCTAssertFalse(BeamTracer.trace(level: level, placements: [:]).solved)

        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 3, y: 4): PlacedComponent(kind: .shifter, rotation: 0),
        ]
        let result = BeamTracer.trace(level: level, placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 7, y: 4)], .green)
    }

    func testShifter_スプリッタと合成器で半黄を作る() {
        // ステージ24「まわしてあわせて」と同じ構成:
        // 赤をスプリッタで割り、片方をシフトして緑にし、合成して (0.5, 0.5, 0)
        let halfYellow = BeamColor(r: 0.5, g: 0.5, b: 0)
        let level = Level(
            id: "level_024", title: "まわしてあわせて", size: 9, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 4): PlacedComponent(kind: .source, rotation: 90,
                                                          color: .red, fixed: true),
                GridPosition(x: 8, y: 4): PlacedComponent(kind: .goal, color: halfYellow, fixed: true),
            ],
            inventory: [
                InventoryItem(kind: .splitter, color: nil, count: 1),
                InventoryItem(kind: .shifter, color: nil, count: 1),
                InventoryItem(kind: .combiner, color: nil, count: 1),
                InventoryItem(kind: .mirror, color: nil, count: 3),
            ]
        )
        XCTAssertFalse(BeamTracer.trace(level: level, placements: [:]).solved)

        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 4): PlacedComponent(kind: .splitter, rotation: 0),
            GridPosition(x: 2, y: 6): PlacedComponent(kind: .mirror, rotation: 0),
            GridPosition(x: 4, y: 6): PlacedComponent(kind: .shifter, rotation: 0),
            GridPosition(x: 5, y: 6): PlacedComponent(kind: .mirror, rotation: 90),
            GridPosition(x: 5, y: 4): PlacedComponent(kind: .combiner, rotation: 90),
        ]
        let result = BeamTracer.trace(level: level, placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 8, y: 4)], halfYellow)
    }

    func test固定部品はプレイヤー配置と衝突しない() {
        // ステージ13「うごかせない鏡」: 固定鏡が経路を強制する
        let level = Level(
            id: "level_013", title: "うごかせない鏡", size: 7, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 3): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 3, y: 3): PlacedComponent(kind: .mirror, rotation: 0, fixed: true),
                GridPosition(x: 6, y: 5): PlacedComponent(kind: .goal, color: .white, fixed: true),
            ],
            inventory: [InventoryItem(kind: .mirror, color: nil, count: 2)]
        )
        let model = GameModel(level: level)
        // 固定鏡のセルには配置できない
        XCTAssertFalse(model.placeItem(model.level.inventory[0], at: GridPosition(x: 3, y: 3)))
        // 固定鏡で曲がった先に鏡を置いてクリア
        XCTAssertTrue(model.placeItem(model.level.inventory[0], at: GridPosition(x: 3, y: 5)))
        XCTAssertTrue(model.solved)
    }

    // MARK: - スプリッタ(ハーフミラー)

    func testSplitter_半分反射半分透過() {
        // ステージ11「わけあう光」と同じ構成:
        // スプリッタ1枚で白色光を半分ずつ2つのゴールへ分ける
        let halfWhite = BeamColor(r: 0.5, g: 0.5, b: 0.5)
        let level = Level(
            id: "level_011", title: "わけあう光", size: 7, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 3): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 1, y: 5): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 5, y: 1): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 6, y: 3): PlacedComponent(kind: .goal, color: halfWhite, fixed: true),
                GridPosition(x: 3, y: 6): PlacedComponent(kind: .goal, color: halfWhite, fixed: true),
            ],
            inventory: [InventoryItem(kind: .splitter, color: nil, count: 1)]
        )
        // 初期状態: 白色光がそのままゴールに入るが強すぎて未クリア
        XCTAssertFalse(BeamTracer.trace(level: level, placements: [:]).solved)

        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 3, y: 3): PlacedComponent(kind: .splitter, rotation: 0),
        ]
        let result = BeamTracer.trace(level: level, placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 6, y: 3)], halfWhite)
        XCTAssertEqual(result.goalColors[GridPosition(x: 3, y: 6)], halfWhite)
    }

    func testSplitter_合成器と組み合わせてオレンジを作る() {
        // ステージ51「オレンジの結晶」と同じ構成:
        // 分光した G をスプリッタで半減させ、R と合成して (1, 0.5, 0) を作る
        let orange = BeamColor(r: 1, g: 0.5, b: 0)
        let level = Level(
            id: "level_051", title: "オレンジの結晶", size: 8, tolerance: 0.15,
            grid: [
                GridPosition(x: 0, y: 4): PlacedComponent(kind: .source, rotation: 90, fixed: true),
                GridPosition(x: 1, y: 1): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 6, y: 6): PlacedComponent(kind: .wall, fixed: true),
                GridPosition(x: 7, y: 4): PlacedComponent(kind: .goal, color: orange, fixed: true),
            ],
            inventory: [
                InventoryItem(kind: .prism, color: nil, count: 1),
                InventoryItem(kind: .splitter, color: nil, count: 1),
                InventoryItem(kind: .combiner, color: nil, count: 1),
                InventoryItem(kind: .mirror, color: nil, count: 3),
            ]
        )
        XCTAssertFalse(BeamTracer.trace(level: level, placements: [:]).solved)

        let placements: [GridPosition: PlacedComponent] = [
            GridPosition(x: 2, y: 4): PlacedComponent(kind: .prism, rotation: 0),
            GridPosition(x: 2, y: 6): PlacedComponent(kind: .mirror, rotation: 0),
            GridPosition(x: 4, y: 6): PlacedComponent(kind: .splitter, rotation: 0),
            GridPosition(x: 5, y: 6): PlacedComponent(kind: .mirror, rotation: 90),
            GridPosition(x: 5, y: 4): PlacedComponent(kind: .combiner, rotation: 90),
        ]
        let result = BeamTracer.trace(level: level, placements: placements)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.goalColors[GridPosition(x: 7, y: 4)], orange)
    }

    // MARK: - ステージパック

    func testLevelPack_番号からパックを判定する() {
        XCTAssertEqual(LevelPack.pack(forStageNumber: 1), .free)
        XCTAssertEqual(LevelPack.pack(forStageNumber: 10), .free)
        XCTAssertEqual(LevelPack.pack(forStageNumber: 11), .standard)
        XCTAssertEqual(LevelPack.pack(forStageNumber: 50), .standard)
        XCTAssertEqual(LevelPack.pack(forStageNumber: 51), .extra)
        XCTAssertEqual(LevelPack.pack(forStageNumber: 100), .extra)
        XCTAssertNil(LevelPack.pack(forStageNumber: 101))
    }

    func testLevelCatalog_パック別の振り分けと解放判定() {
        let catalog = LevelCatalog(levels: LevelLoader.loadAll())
        XCTAssertEqual(catalog.entries(in: .free).count, 10)
        XCTAssertEqual(catalog.entries(in: .standard).count, 15)
        XCTAssertEqual(catalog.entries(in: .extra).count, 1)

        // 無料のみ → 10ステージ、全パック解放 → 26ステージ
        XCTAssertEqual(catalog.playableLevels(unlockedPacks: [.free]).count, 10)
        XCTAssertEqual(catalog.playableLevels(unlockedPacks: [.free, .standard, .extra]).count, 26)
        // 並び順はステージ番号順
        XCTAssertEqual(catalog.playableLevels(unlockedPacks: [.free, .standard]).last?.id, "level_025")
    }

    func testLevelCatalog_IDから番号を取り出す() {
        XCTAssertEqual(LevelCatalog.stageNumber(fromID: "level_001"), 1)
        XCTAssertEqual(LevelCatalog.stageNumber(fromID: "level_051"), 51)
        XCTAssertNil(LevelCatalog.stageNumber(fromID: "broken"))
    }

    // MARK: - D&D 用の盤面操作

    func testGameModel_部品の移動と回収() {
        let model = GameModel(level: makeStage1())
        let mirrorItem = model.level.inventory[0]

        XCTAssertTrue(model.placeItem(mirrorItem, at: GridPosition(x: 2, y: 2)))
        // 移動
        XCTAssertTrue(model.moveComponent(from: GridPosition(x: 2, y: 2),
                                          to: GridPosition(x: 1, y: 1)))
        XCTAssertNil(model.placements[GridPosition(x: 2, y: 2)])
        XCTAssertNotNil(model.placements[GridPosition(x: 1, y: 1)])
        // 固定部品の上には移動できない
        XCTAssertFalse(model.moveComponent(from: GridPosition(x: 1, y: 1),
                                           to: GridPosition(x: 3, y: 2)))
        // 回収すると在庫が戻る
        model.removeComponent(at: GridPosition(x: 1, y: 1))
        XCTAssertEqual(model.remainingCount(of: mirrorItem), 2)
    }

    func testBoardGeometry_ビュー座標からセルを求める() {
        // 600pt 四方に 6x6 グリッド。盤面は 564pt(94%)で余白 18pt
        let geometry = BoardGeometry(canvasSize: CGSize(width: 600, height: 600), gridCount: 6)
        // 左下セル(ビュー座標は y が下向きなので下端近く)
        XCTAssertEqual(geometry.cell(atViewPoint: CGPoint(x: 60, y: 540),
                                     viewSize: CGSize(width: 600, height: 600)),
                       GridPosition(x: 0, y: 0))
        // 右上セル
        XCTAssertEqual(geometry.cell(atViewPoint: CGPoint(x: 540, y: 60),
                                     viewSize: CGSize(width: 600, height: 600)),
                       GridPosition(x: 5, y: 5))
        // 盤外(余白部分)
        XCTAssertNil(geometry.cell(atViewPoint: CGPoint(x: 5, y: 5),
                                   viewSize: CGSize(width: 600, height: 600)))
    }
}
