//
//  LevelCatalog.swift
//  Aglaia
//
//  ステージのパック分け(無料/スタンダード/Extra)と番号管理。
//  課金でパックを解放すると、そのパックに属するステージが遊べるようになる。
//

import Foundation

/// ステージパック。番号帯で所属が決まる
enum LevelPack: String, CaseIterable, Identifiable {
    /// 無料: ステージ 1〜10
    case free
    /// 内部課金: ステージ 11〜50
    case standard
    /// 追加課金: ステージ 51〜100(新要素で高難度化)
    case extra

    var id: String { rawValue }

    var stageRange: ClosedRange<Int> {
        switch self {
        case .free: return 1 ... 10
        case .standard: return 11 ... 50
        case .extra: return 51 ... 100
        }
    }

    var displayName: String {
        switch self {
        case .free: return "ベーシック"
        case .standard: return "スタンダードパック"
        case .extra: return "Extraパック"
        }
    }

    var summary: String {
        switch self {
        case .free: return "ステージ 1〜10(無料)"
        case .standard: return "ステージ 11〜50・新部品スプリッタ登場"
        case .extra: return "ステージ 51〜100・複合ギミックの高難度ステージ"
        }
    }

    /// App Store Connect に登録する非消耗型プロダクトID。無料パックは nil。
    /// バンドルID(jp.aryzae.Aglaia)を接頭辞に揃えている。
    /// 注意: App Store Connect で一度作成したプロダクトIDは変更・再利用できないため、
    ///       登録前にこの値で確定していること。
    var productID: String? {
        switch self {
        case .free: return nil
        case .standard: return "jp.aryzae.Aglaia.prism.pack.standard"
        case .extra: return "jp.aryzae.Aglaia.prism.pack.extra"
        }
    }

    /// ステージ番号から所属パックを求める
    static func pack(forStageNumber number: Int) -> LevelPack? {
        allCases.first { $0.stageRange.contains(number) }
    }
}

/// 読み込んだステージと番号・所属パックの対応
struct CatalogEntry: Identifiable {
    let number: Int
    let pack: LevelPack
    let level: Level

    var id: String { level.id }
}

/// バンドルの全ステージをパック別に整理するカタログ
struct LevelCatalog {
    let entries: [CatalogEntry]

    init(levels: [Level]) {
        entries = levels
            .compactMap { level in
                guard let number = Self.stageNumber(fromID: level.id),
                      let pack = LevelPack.pack(forStageNumber: number)
                else { return nil }
                return CatalogEntry(number: number, pack: pack, level: level)
            }
            .sorted { $0.number < $1.number }
    }

    /// "level_001" 形式の ID からステージ番号を取り出す
    static func stageNumber(fromID id: String) -> Int? {
        id.split(separator: "_").last.flatMap { Int($0) }
    }

    func entries(in pack: LevelPack) -> [CatalogEntry] {
        entries.filter { $0.pack == pack }
    }

    /// 解放済みパックのステージを番号順に並べたリスト(「次のステージへ」の遷移順)
    func playableLevels(unlockedPacks: Set<LevelPack>) -> [Level] {
        entries.filter { unlockedPacks.contains($0.pack) }.map(\.level)
    }
}
