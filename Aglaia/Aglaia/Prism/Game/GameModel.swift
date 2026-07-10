//
//  GameModel.swift
//  Aglaia
//
//  ゲーム進行の状態管理。SwiftUI と SKScene の双方から共有される。
//

import Foundation
import Observation

@Observable
final class GameModel {
    let level: Level

    /// プレイヤーが配置した部品
    private(set) var placements: [GridPosition: PlacedComponent] = [:]
    /// レイキャストの再計算結果(描画用)
    private(set) var traceResult = TraceResult()
    /// パレットで選択中の在庫アイテム
    var selectedItem: InventoryItem?
    /// 盤面変更のたびに増える世代番号。SKScene 側の再描画トリガに使う
    private(set) var revision = 0

    /// アンドゥ用の配置履歴
    private var history: [[GridPosition: PlacedComponent]] = []

    var solved: Bool { traceResult.solved }
    var beams: [BeamSegment] { traceResult.segments }

    /// 目標色を許容誤差内で受け取っているゴールの集合
    var satisfiedGoals: Set<GridPosition> {
        Set(level.grid.compactMap { position, component in
            guard component.kind == .goal, let target = component.color,
                  let received = traceResult.goalColors[position],
                  received.distance(to: target) <= level.tolerance
            else { return nil }
            return position
        })
    }

    init(level: Level) {
        self.level = level
        selectedItem = level.inventory.first
        recomputeBeams()
    }

    // MARK: - 在庫

    /// 指定アイテムの残数(在庫総数 − 配置済み数)
    func remainingCount(of item: InventoryItem) -> Int {
        let placed = placements.values.filter { $0.kind == item.kind && $0.color == item.color }.count
        return max(0, item.count - placed)
    }

    /// パレットのドラッグ&ドロップで使う ID からの逆引き
    func item(withID id: String) -> InventoryItem? {
        level.inventory.first { $0.id == id }
    }

    /// 選択中アイテムが(在庫的に)配置可能か
    var canPlaceSelectedItem: Bool {
        selectedItem.map { remainingCount(of: $0) > 0 } ?? false
    }

    // MARK: - 盤面操作

    /// 在庫アイテムをセルに配置する。配置できたら true
    @discardableResult
    func placeItem(_ item: InventoryItem, at position: GridPosition) -> Bool {
        guard level.contains(position),
              level.grid[position] == nil,
              placements[position] == nil,
              remainingCount(of: item) > 0
        else { return false }

        pushHistory()
        placements[position] = PlacedComponent(kind: item.kind, rotation: 0, color: item.color, fixed: false)
        recomputeBeams()
        return true
    }

    /// 選択中の部品をセルに配置する。配置できたら true
    @discardableResult
    func placeSelectedItem(at position: GridPosition) -> Bool {
        guard let item = selectedItem else { return false }
        return placeItem(item, at: position)
    }

    /// 配置済み部品をドラッグで別セルへ移動する。移動できたら true
    @discardableResult
    func moveComponent(from: GridPosition, to: GridPosition) -> Bool {
        guard from != to,
              let component = placements[from],
              level.contains(to),
              level.grid[to] == nil,
              placements[to] == nil
        else { return false }

        pushHistory()
        placements[from] = nil
        placements[to] = component
        recomputeBeams()
        return true
    }

    /// 配置済み部品を90°回転する
    func rotateComponent(at position: GridPosition) {
        guard placements[position] != nil else { return }
        pushHistory()
        placements[position]?.rotate90()
        recomputeBeams()
    }

    /// 配置済み部品を回収する(在庫に戻る)
    func removeComponent(at position: GridPosition) {
        guard placements[position] != nil else { return }
        pushHistory()
        placements[position] = nil
        recomputeBeams()
    }

    /// セルタップの共通ハンドラ(配置済みは回転、空セルは選択中アイテムを配置)
    func handleTap(at position: GridPosition) {
        if placements[position] != nil {
            rotateComponent(at: position)
        } else {
            placeSelectedItem(at: position)
        }
    }

    // MARK: - リセット / アンドゥ

    func reset() {
        guard !placements.isEmpty else { return }
        pushHistory()
        placements = [:]
        recomputeBeams()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        placements = previous
        recomputeBeams()
    }

    var canUndo: Bool { !history.isEmpty }

    // MARK: - 再計算

    private func pushHistory() {
        history.append(placements)
    }

    private func recomputeBeams() {
        traceResult = BeamTracer.trace(level: level, placements: placements)
        revision += 1
    }
}
