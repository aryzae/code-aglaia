//
//  PrismGameView.swift
//  Aglaia
//
//  ゲーム画面。SpriteKit の盤面を SpriteView で埋め込み、
//  下部に在庫パレット、上部に操作ボタンを置く。
//

import SpriteKit
import SwiftUI

struct PrismGameView: View {
    let levels: [Level]
    @State private var index: Int

    init(levels: [Level], startIndex: Int) {
        self.levels = levels
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        GameBoardView(level: levels[index],
                      stageNumber: index + 1,
                      hasNext: index + 1 < levels.count,
                      onNext: { index += 1 })
            .id(levels[index].id) // ステージが変わったら盤面を作り直す
    }
}

/// 1ステージ分の盤面とUI
private struct GameBoardView: View {
    let stageNumber: Int
    let hasNext: Bool
    let onNext: () -> Void

    @State private var model: GameModel
    @State private var scene: PrismScene
    @Environment(\.dismiss) private var dismiss

    init(level: Level, stageNumber: Int, hasNext: Bool, onNext: @escaping () -> Void) {
        self.stageNumber = stageNumber
        self.hasNext = hasNext
        self.onNext = onNext
        let model = GameModel(level: level)
        _model = State(initialValue: model)
        _scene = State(initialValue: PrismScene(model: model))
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                SpriteView(scene: scene)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 4)
                palette
            }
            if model.solved {
                clearOverlay
            }
        }
        .navigationTitle("Stage \(stageNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - 上部バー

    private var header: some View {
        HStack {
            Text(model.level.title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            Button {
                model.reset()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model.placements.isEmpty)
        }
        .font(.title3)
        .tint(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 在庫パレット

    private var palette: some View {
        VStack(spacing: 8) {
            Text(model.eraseMode
                ? "回収したい部品をタップ"
                : "部品を選んで空きマスをタップ / 配置済みはタップで回転")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 12) {
                ForEach(model.level.inventory) { item in
                    paletteButton(for: item)
                }
                Spacer()
                Button {
                    model.eraseMode.toggle()
                } label: {
                    Image(systemName: "eraser")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(model.eraseMode ? Color.red.opacity(0.5) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .tint(.white)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private func paletteButton(for item: InventoryItem) -> some View {
        let remaining = model.remainingCount(of: item)
        let isSelected = model.selectedItem == item && !model.eraseMode
        return Button {
            model.eraseMode = false
            model.selectedItem = item
        } label: {
            VStack(spacing: 2) {
                itemIcon(for: item)
                    .font(.title2)
                Text("×\(remaining)")
                    .font(.caption2.monospacedDigit())
            }
            .frame(width: 52, height: 52)
            .background(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2)
                }
            }
        }
        .tint(.white)
        .disabled(remaining == 0)
        .opacity(remaining == 0 ? 0.35 : 1)
    }

    @ViewBuilder
    private func itemIcon(for item: InventoryItem) -> some View {
        switch item.kind {
        case .mirror:
            Image(systemName: "line.diagonal")
        case .prism:
            Image(systemName: "triangle")
        case .filter:
            Image(systemName: "camera.filters")
                .foregroundStyle(item.color.map {
                    Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b))
                } ?? .white)
        case .combiner:
            Image(systemName: "plus.circle")
        default:
            Image(systemName: "questionmark")
        }
    }

    // MARK: - クリア演出

    private var clearOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("クリア!")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                VStack(spacing: 12) {
                    if hasNext {
                        Button {
                            onNext()
                        } label: {
                            Text("次のステージへ")
                                .font(.headline)
                                .frame(maxWidth: 220)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text("ステージ選択へ")
                            .font(.headline)
                            .frame(maxWidth: 220)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                .tint(.white)
            }
        }
    }
}
