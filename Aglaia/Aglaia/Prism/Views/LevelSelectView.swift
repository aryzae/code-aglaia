//
//  LevelSelectView.swift
//  Aglaia
//
//  ステージ選択画面。バンドル内の Levels/*.json を一覧表示する。
//

import SwiftUI

struct LevelSelectView: View {
    @State private var levels: [Level] = []

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.12).ignoresSafeArea()
            List {
                ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                    NavigationLink {
                        PrismGameView(levels: levels, startIndex: index)
                    } label: {
                        HStack(spacing: 16) {
                            Text("\(index + 1)")
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("\(level.size)×\(level.size)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("ステージ選択")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if levels.isEmpty {
                levels = LevelLoader.loadAll()
            }
        }
    }
}

#Preview {
    NavigationStack {
        LevelSelectView()
    }
    .preferredColorScheme(.dark)
}
