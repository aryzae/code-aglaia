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
    @Environment(ProgressStore.self) private var progress

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
                board
                palette
            }
            if model.solved {
                clearOverlay
            }
        }
        .navigationTitle("Stage \(stageNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: model.solved) { _, solved in
            if solved {
                progress.markCleared(model.level.id)
            }
        }
    }

    // MARK: - 盤面

    /// SpriteKit の盤面。パレットからのドロップを受け付ける
    private var board: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene)
                .dropDestination(for: String.self) { itemIDs, location in
                    guard let id = itemIDs.first, let item = model.item(withID: id) else { return false }
                    let geometry = BoardGeometry(canvasSize: proxy.size, gridCount: model.level.size)
                    guard let cell = geometry.cell(atViewPoint: location, viewSize: proxy.size) else {
                        return false
                    }
                    return model.placeItem(item, at: cell)
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 4)
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
            // 選択中の部品の説明(盤面とパレットの間に控えめに表示)
            Text(selectionHint)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 28)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.15), value: selectionHint)
            HStack(spacing: 12) {
                ForEach(model.level.inventory) { item in
                    paletteButton(for: item)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private func paletteButton(for item: InventoryItem) -> some View {
        let remaining = model.remainingCount(of: item)
        let isSelected = model.selectedItem == item
        return Button {
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
        .draggable(item.id) // 盤面へのドラッグ&ドロップ配置
    }

    /// 選択中の部品名+説明。未選択時は基本操作のヒントを出す
    private var selectionHint: String {
        guard let item = model.selectedItem else {
            return "部品をタップで選択 / 盤面をドラッグで配置場所をプレビュー"
        }
        return "【\(displayName(for: item.kind))】\(explanation(for: item.kind))"
    }

    private func displayName(for kind: ComponentKind) -> String {
        switch kind {
        case .mirror: return "鏡"
        case .splitter: return "スプリッタ"
        case .prism: return "プリズム"
        case .filter: return "フィルタ"
        case .combiner: return "合成器"
        case .shifter: return "カラーシフタ"
        case .source: return "光源"
        case .goal: return "結晶"
        case .wall: return "壁"
        case .warp: return "ワープゲート"
        }
    }

    private func explanation(for kind: ComponentKind) -> String {
        switch kind {
        case .mirror: return "光を直角にはね返す。タップで向きを回転"
        case .splitter: return "半分をはね返し、半分をそのまま通す"
        case .prism: return "光を赤(直進)・緑(左折)・青(右折)に分ける"
        case .filter: return "フィルタと同じ色の成分だけを通す"
        case .combiner: return "入ってきた光を足し合わせ、矢印の向きへ出す。タップで回転"
        case .shifter: return "色を 赤→緑→青→赤 の順にひとつ回す"
        case .source: return "ここから光が出る"
        case .goal: return "目標の色の光を当てるとクリア"
        case .wall: return "光を止める"
        case .warp: return "同じ色の対のゲートへ光がワープする"
        }
    }

    @ViewBuilder
    private func itemIcon(for item: InventoryItem) -> some View {
        switch item.kind {
        case .mirror:
            Image(systemName: "line.diagonal")
        case .splitter:
            Image(systemName: "square.split.diagonal")
        case .shifter:
            Image(systemName: "arrow.triangle.2.circlepath")
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
