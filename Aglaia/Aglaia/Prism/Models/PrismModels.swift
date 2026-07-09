//
//  PrismModels.swift
//  Aglaia
//
//  Prism(光と色のパズル)のコアデータモデル。
//  詳細仕様は spec_prism.md を参照。
//

import Foundation

// MARK: - 部品種別

enum ComponentKind: String, Codable, Hashable {
    case source, mirror, prism, filter, combiner, wall, goal
}

// MARK: - 方向

/// 盤面上の進行方向。rawValue は時計回り(up=0, right=1, down=2, left=3)。
/// 部品の rotation(0/90/180/270)は `Direction(degrees:)` で方向に変換する。
enum Direction: Int, Codable, CaseIterable, Hashable {
    case up = 0, right = 1, down = 2, left = 3

    init(degrees: Int) {
        self = Direction(rawValue: ((degrees / 90) % 4 + 4) % 4) ?? .up
    }

    /// 進行方向の増分(y は上向きが正。SpriteKit 座標系に合わせる)
    var dx: Int { [0, 1, 0, -1][rawValue] }
    var dy: Int { [1, 0, -1, 0][rawValue] }

    var turnedLeft: Direction { Direction(rawValue: (rawValue + 3) % 4)! }
    var turnedRight: Direction { Direction(rawValue: (rawValue + 1) % 4)! }
    var opposite: Direction { Direction(rawValue: (rawValue + 2) % 4)! }
}

// MARK: - 色

/// ビームの色(RGB 各成分 0...1)。合流は加法混色(加算してクランプ)。
struct BeamColor: Codable, Hashable {
    var r: Float
    var g: Float
    var b: Float

    static let white = BeamColor(r: 1, g: 1, b: 1)
    static let red = BeamColor(r: 1, g: 0, b: 0)
    static let green = BeamColor(r: 0, g: 1, b: 0)
    static let blue = BeamColor(r: 0, g: 0, b: 1)
    static let black = BeamColor(r: 0, g: 0, b: 0)

    /// 加法混色(成分ごとに加算し 1 でクランプ)
    func mixed(with other: BeamColor) -> BeamColor {
        BeamColor(r: min(1, r + other.r), g: min(1, g + other.g), b: min(1, b + other.b))
    }

    /// フィルタ通過(成分ごとの積)
    func filtered(by filter: BeamColor) -> BeamColor {
        BeamColor(r: r * filter.r, g: g * filter.g, b: b * filter.b)
    }

    /// 目標色とのユークリッド距離
    func distance(to other: BeamColor) -> Float {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// ほぼ黒(光がない)とみなせるか
    var isNegligible: Bool { r < 0.01 && g < 0.01 && b < 0.01 }

    /// ループ検出用の量子化キー(1/16 刻み)
    var quantized: Int {
        let qr = Int((r * 16).rounded()), qg = Int((g * 16).rounded()), qb = Int((b * 16).rounded())
        return (qr << 10) | (qg << 5) | qb
    }
}

// MARK: - 座標

/// 盤面セル座標。x は右方向、y は上方向に増加(SpriteKit 座標系)。
struct GridPosition: Codable, Hashable {
    var x: Int
    var y: Int

    func advanced(_ direction: Direction) -> GridPosition {
        GridPosition(x: x + direction.dx, y: y + direction.dy)
    }
}

// MARK: - 配置部品

struct PlacedComponent: Codable, Hashable {
    var kind: ComponentKind
    /// 0/90/180/270。source/combiner は出力方向、mirror は向き(0/180="/", 90/270="\")
    var rotation: Int
    /// filter の透過色、goal の目標色、source の発色(省略時は白)
    var color: BeamColor?
    /// true ならプレイヤーは動かせない(source/goal/wall 等)
    var fixed: Bool

    init(kind: ComponentKind, rotation: Int = 0, color: BeamColor? = nil, fixed: Bool = false) {
        self.kind = kind
        self.rotation = rotation
        self.color = color
        self.fixed = fixed
    }

    var direction: Direction { Direction(degrees: rotation) }

    mutating func rotate90() {
        rotation = (rotation + 90) % 360
    }
}

// MARK: - 在庫

/// プレイヤーが配置できる部品の在庫1枠。filter は透過色を持つ。
struct InventoryItem: Codable, Hashable, Identifiable {
    var kind: ComponentKind
    var color: BeamColor?
    var count: Int

    var id: String { "\(kind.rawValue)-\(color.map { "\($0.quantized)" } ?? "none")" }
}

// MARK: - ステージ

struct Level: Codable, Hashable {
    var id: String
    var title: String
    /// グリッド一辺のセル数
    var size: Int
    /// 目標色との一致判定の許容誤差
    var tolerance: Float
    /// 固定配置(source/goal/wall など)。JSON では "x,y" 文字列キー
    var grid: [GridPosition: PlacedComponent]
    /// プレイヤーが置ける部品の在庫
    var inventory: [InventoryItem]

    enum CodingKeys: String, CodingKey {
        case id, title, size, tolerance, grid, inventory
    }

    init(id: String, title: String, size: Int, tolerance: Float,
         grid: [GridPosition: PlacedComponent], inventory: [InventoryItem]) {
        self.id = id
        self.title = title
        self.size = size
        self.tolerance = tolerance
        self.grid = grid
        self.inventory = inventory
    }

    // grid の辞書キーを "x,y" 文字列としてエンコード/デコードする
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        size = try container.decode(Int.self, forKey: .size)
        tolerance = try container.decode(Float.self, forKey: .tolerance)
        inventory = try container.decode([InventoryItem].self, forKey: .inventory)

        let rawGrid = try container.decode([String: PlacedComponent].self, forKey: .grid)
        var parsed: [GridPosition: PlacedComponent] = [:]
        for (key, component) in rawGrid {
            let parts = key.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .grid, in: container,
                                                       debugDescription: "不正な座標キー: \(key)")
            }
            parsed[GridPosition(x: parts[0], y: parts[1])] = component
        }
        grid = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(size, forKey: .size)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(inventory, forKey: .inventory)
        let rawGrid = Dictionary(uniqueKeysWithValues: grid.map { ("\($0.key.x),\($0.key.y)", $0.value) })
        try container.encode(rawGrid, forKey: .grid)
    }

    func contains(_ position: GridPosition) -> Bool {
        position.x >= 0 && position.x < size && position.y >= 0 && position.y < size
    }
}

// MARK: - 描画用ビーム線分

/// レイキャスト結果の1本の線分(セル座標)。描画時にシーン座標へ変換する。
struct BeamSegment: Hashable {
    var from: GridPosition
    var to: GridPosition
    /// 盤外へ抜ける場合、to のさらに半セル先まで描画する
    var exitsBoard: Bool
    var color: BeamColor
}
