//
//  PrismTitleView.swift
//  Aglaia
//
//  タイトル画面。ここからステージ選択へ遷移する。
//

import SwiftUI

struct PrismTitleView: View {
    /// アプリ全体で共有する課金ストア
    @State private var store = PrismStore()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12).ignoresSafeArea()
                VStack(spacing: 32) {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "light.max")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(colors: [.red, .green, .blue],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text("Prism")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("光を導き、色をつくるパズル")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    NavigationLink {
                        LevelSelectView()
                    } label: {
                        Text("はじめる")
                            .font(.title3.bold())
                            .frame(maxWidth: 240)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer().frame(height: 60)
                }
            }
        }
        .environment(store)
        .task {
            await store.loadProducts()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    PrismTitleView()
}
