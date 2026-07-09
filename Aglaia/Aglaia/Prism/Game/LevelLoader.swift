//
//  LevelLoader.swift
//  Aglaia
//
//  Resources/Levels/*.json からステージ定義を読み込む。
//

import Foundation

enum LevelLoader {
    /// バンドル内の全ステージをファイル名順に読み込む
    static func loadAll(bundle: Bundle = .main) -> [Level] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Levels") ?? []
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    let data = try Data(contentsOf: url)
                    return try JSONDecoder().decode(Level.self, from: data)
                } catch {
                    assertionFailure("ステージの読み込みに失敗: \(url.lastPathComponent) — \(error)")
                    return nil
                }
            }
    }
}
