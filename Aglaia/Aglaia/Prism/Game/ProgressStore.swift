//
//  ProgressStore.swift
//  Aglaia
//
//  ステージのクリア状況を UserDefaults に永続化する。
//

import Foundation
import Observation

@Observable
final class ProgressStore {
    private static let defaultsKey = "prism.clearedLevelIDs"

    @ObservationIgnored private let defaults: UserDefaults
    /// クリア済みステージの ID 集合
    private(set) var clearedLevelIDs: Set<String>

    /// - Parameter defaults: テストでは専用スイートを差し込む
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clearedLevelIDs = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func isCleared(_ levelID: String) -> Bool {
        clearedLevelIDs.contains(levelID)
    }

    /// クリアを記録する(既にクリア済みなら何もしない)
    func markCleared(_ levelID: String) {
        guard clearedLevelIDs.insert(levelID).inserted else { return }
        defaults.set(clearedLevelIDs.sorted(), forKey: Self.defaultsKey)
    }

    /// 指定ステージ群のうちクリア済みの数(パック別の進捗表示用)
    func clearedCount(in levelIDs: [String]) -> Int {
        levelIDs.filter { clearedLevelIDs.contains($0) }.count
    }
}
