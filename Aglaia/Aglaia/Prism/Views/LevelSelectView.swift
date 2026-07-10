//
//  LevelSelectView.swift
//  Aglaia
//
//  ステージ選択画面。パック別(無料/スタンダード/Extra)に一覧表示し、
//  未購入パックは内部課金で解放する。
//

import SwiftUI

struct LevelSelectView: View {
    @Environment(PrismStore.self) private var store
    @Environment(ProgressStore.self) private var progress
    @State private var catalog = LevelCatalog(levels: [])
    @State private var loaded = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.12).ignoresSafeArea()
            List {
                ForEach(LevelPack.allCases) { pack in
                    packSection(pack)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("ステージ選択")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("購入を復元") {
                    Task { await store.restorePurchases() }
                }
                .font(.caption)
                .tint(.white.opacity(0.7))
                .disabled(store.isBusy)
            }
        }
        .alert("エラー", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            if !loaded {
                catalog = LevelCatalog(levels: LevelLoader.loadAll())
                loaded = true
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
    }

    // MARK: - パックごとのセクション

    @ViewBuilder
    private func packSection(_ pack: LevelPack) -> some View {
        let entries = catalog.entries(in: pack)
        Section {
            if store.isUnlocked(pack) {
                ForEach(entries) { entry in
                    stageRow(entry)
                }
                if entries.count < pack.stageRange.count {
                    Text("続きのステージは今後のアップデートで配信予定")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .listRowBackground(Color.white.opacity(0.03))
                }
            } else {
                purchaseRow(pack, stageCount: entries.count)
            }
        } header: {
            HStack {
                Text(pack.displayName)
                if store.isUnlocked(pack), !entries.isEmpty {
                    // パック内のクリア進捗
                    let cleared = progress.clearedCount(in: entries.map(\.level.id))
                    Text("クリア \(cleared)/\(entries.count)")
                        .foregroundStyle(cleared == entries.count ? .yellow : .white.opacity(0.6))
                }
                Spacer()
                Text(pack.summary)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func stageRow(_ entry: CatalogEntry) -> some View {
        let playable = catalog.playableLevels(unlockedPacks: store.unlockedPacks)
        let startIndex = playable.firstIndex { $0.id == entry.level.id } ?? 0
        return NavigationLink {
            PrismGameView(levels: playable, startIndex: startIndex)
        } label: {
            HStack(spacing: 16) {
                Text("\(entry.number)")
                    .font(.title3.bold().monospacedDigit())
                    .frame(width: 40, alignment: .leading)
                    .foregroundStyle(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.level.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(entry.level.size)×\(entry.level.size)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if progress.isCleared(entry.level.id) {
                    // クリア済みマーク
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    // MARK: - 購入UI

    private func purchaseRow(_ pack: LevelPack, stageCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(pack.summary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.yellow)
            }
            Button {
                Task { await store.purchase(pack) }
            } label: {
                HStack {
                    Image(systemName: "cart")
                    if let product = store.product(for: pack) {
                        Text("\(product.displayPrice) で解放する")
                    } else {
                        Text("解放する")
                    }
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.yellow.opacity(0.25), in: Capsule())
                .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy || store.product(for: pack) == nil)
            if store.product(for: pack) == nil {
                Text("現在ストア情報を取得できません")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.white.opacity(0.06))
    }
}

#Preview {
    NavigationStack {
        LevelSelectView()
    }
    .environment(PrismStore())
    .environment(ProgressStore())
    .preferredColorScheme(.dark)
}
