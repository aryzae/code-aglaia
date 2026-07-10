# Prism 設計仕様書

## 1. コンセプト
光源(太陽光=白色ビーム)から出た光を、グリッド上に配置した部品で反射・分光・
ろ過・合成し、ゴールの結晶に「指定色の光」を届けるとクリア。限られた在庫の部品を
どう配置するかを考える制約パズル。

「単に繋ぐ」だけでなく **色を作る/選ぶ** という次元があるのが最大の特徴。
（例：白を分光して赤だけ通す／赤と青を別ルートで作って合成して紫にする）

## 2. コアメカニクス
- 盤面は正方グリッド(例 8×8)。各セルに部品を1つ置ける。
- 光は「線分の集合」。光源から発射し、部品/壁に当たるまで直進する。
- 光は **色(RGB)** を持つ。部品を通ると色や方向が変わる。
- ゴールが要求色を受け取ったらクリア。複数の光がゴールに入る場合は加法混色で合算。

## 3. 部品一覧(初期セット)
| 部品 | 挙動 |
|---|---|
| Source(光源) | 固定。指定方向へ白色 (1,1,1) のビームを発射 |
| Mirror(鏡) | 45°/135°。入射ビームを直角に反射(向きを変える) |
| Prism(プリズム) | 白色光を R/G/B の3本に分光し、それぞれ別方向へ出力 |
| Filter(色フィルタ) | 指定色成分だけ通す(入射色 × フィルタ色。例: 赤フィルタは R成分のみ通す) |
| Combiner(合成器) | 複数方向から入った光を加算し、1方向へ出力 |
| Wall(壁) | 光を吸収して停止させる。障害物・固定 |
| Goal(結晶) | 固定。受け取った色が目標色と誤差閾値内なら作動=クリア |

※ 部品には回転(0/90/180/270)を持たせ、入出力の辺を回転で決める。
※ 拡張候補: レンズ(集光/拡散)、分岐ミラー(ハーフミラー)、色を強めるブースター。

## 4. クリア条件
- 全ゴールが「作動」状態になったらステージクリア。
- 目標色との一致判定: `distance(received, target) <= tolerance`(例 tolerance = 0.15)。

## 5. 技術構成
- SwiftUI: タイトル / ステージ選択 / 設定。
- SpriteKit: 盤面描画・ビーム描画・部品ドラッグ。`SpriteView` でSwiftUIに埋め込む。
- 状態管理: `@Observable` な GameModel を SwiftUI と SKScene で共有。

## 6. データモデル(骨格)
```swift
enum ComponentKind: String, Codable {
    case source, mirror, prism, filter, combiner, wall, goal
}

enum Direction: Int, Codable { case up, right, down, left }

struct BeamColor: Codable {          // RGB 0...1
    var r, g, b: Float
    static let white = BeamColor(r: 1, g: 1, b: 1)
    func mixed(with o: BeamColor) -> BeamColor {  // 加法混色
        BeamColor(r: min(1, r+o.r), g: min(1, g+o.g), b: min(1, b+o.b))
    }
}

struct Position: Codable, Hashable { var x, y: Int }

struct PlacedComponent: Codable {
    var kind: ComponentKind
    var rotation: Int            // 0/90/180/270
    var color: BeamColor?        // filter/goal/source が使う目標色や発色
    var fixed: Bool              // true ならプレイヤーは動かせない(source/goal/wall等)
}

struct Level: Codable {
    var size: Int                       // グリッド一辺
    var grid: [Position: PlacedComponent]  // 固定配置(source/goal/wall/初期部品)
    var inventory: [ComponentKind: Int]    // プレイヤーが置ける部品の在庫
    var tolerance: Float
}

@Observable
final class GameModel {
    var level: Level
    var placements: [Position: PlacedComponent] = [:]  // プレイヤー配置
    var beams: [BeamSegment] = []                       // 再計算結果(描画用)
    var solved: Bool = false
    // 配置変更 → recomputeBeams() → クリア判定
}

struct BeamSegment {                 // 描画用の1本の線分
    var from: CGPoint
    var to: CGPoint
    var color: BeamColor
}
```

## 7. レイキャスト(光線計算)の流れ
盤面が変化したら `recomputeBeams()` を呼ぶ:
1. 全 Source を起点に、発射方向・白色でビームを1本ずつキューに入れる。
2. キューからビームを取り出し、現在セルから発射方向へ **1セルずつ前進**。
3. 次セルの部品を見て分岐:
   - なし → さらに前進(線分を延長)。盤外に出たら終了。
   - Wall / Goal → そのセルで停止。Goal なら「そのセルに入った色」を集計に加算。
   - Mirror → 反射方向を計算し、そのセルを新たな起点として続行。
   - Filter → 色を `received × filterColor` に更新して直進。
   - Prism → 白色なら R/G/B の3本に分割し、それぞれ別方向で新規ビームとしてキューに追加。
   - Combiner → 入射を一時保持。全入力が出そろったら加算して1本を出力。
4. 無限ループ対策: 「(セル, 進行方向, 色の丸め値)」の訪問済みセットを持ち、
   同一状態に再訪したら打ち切る(ミラーのループ対策)。
5. 各ゴールで受け取った色を合算し、目標色との距離でクリア判定。

## 8. ステージ定義(JSON例)
```json
{
  "size": 6,
  "tolerance": 0.15,
  "grid": {
    "0,2": { "kind": "source", "rotation": 90, "fixed": true },
    "5,2": { "kind": "goal", "rotation": 0, "fixed": true,
             "color": { "r": 1, "g": 0, "b": 0 } },
    "2,0": { "kind": "wall", "rotation": 0, "fixed": true }
  },
  "inventory": { "mirror": 2, "prism": 1, "filter": 1 }
}
```
※ 実装時は `[Position: ...]` を JSON化しやすいよう "x,y" 文字列キーで持つか、
  配列 `[{x,y,component}]` 形式にするか、どちらかに統一する(下記オープン事項)。

## 9. 実装マイルストーン(この順で1つずつ動く状態にする)
1. Xcode プロジェクト雛形 + `SpriteView` で SKScene を表示 + グリッド描画。
2. Source から1本のビームをレイキャストし、壁/盤外で停止するところまで描画。
3. Mirror(反射)を実装。ドラッグではなく、まずコードで固定配置してテスト。
4. Prism(白→R/G/B 分光)を実装。3本が別方向に出るのを確認。
5. Filter / Combiner / Goal 判定を実装。単純ステージを「解ける」状態にする。
6. ドラッグ&ドロップの配置UI + 在庫パレット + 回転操作。
7. ステージJSONローダ + クリア判定演出 + リセット/アンドゥ。
8. ステージ選択画面・チュートリアルステージ・エフェクト(発光・パーティクル)。

## 10. オープン事項(実装前に決めたい)
- グリッドサイズは固定(8×8)か、ステージ可変か。
- ビームは「セル中心を通る」前提か、任意角度を許すか(まずはセル中心・直角のみ推奨)。
- 合成器の入力タイミング(全入力待ちの実装方式)。
- ステージJSONのキー表現(辞書 vs 配列)。
- 色の丸め粒度(ループ検出の訪問済み判定に使う量子化ステップ)。

## 11. 追加実装(実装済み)
### 部品の拡張
| 部品 | 挙動 |
|---|---|
| Splitter(スプリッタ/ハーフミラー) | 鏡と同じ向き規則で **半分を反射・半分を透過**(各ビームの強度 0.5 倍)。スタンダードパック以降に登場 |

### ステージパックと内部課金
- ステージは番号でパックに属する(`LevelPack`):
  - **無料**: 1〜10
  - **スタンダードパック**(非消耗型IAP `com.aryzae.aglaia.prism.pack.standard`): 11〜50。スプリッタ登場
  - **Extraパック**(非消耗型IAP `com.aryzae.aglaia.prism.pack.extra`): 51〜100。複合ギミックで高難度化
- StoreKit 2(`PrismStore`)で購入・復元・`Transaction.currentEntitlements` による解放判定を行う。
- ステージJSONは `level_001.json` 形式の3桁連番。`Levels` フォルダに置くだけで自動的に一覧へ反映される。

### クリア判定の方針
- 解法は照合しない。**最終的に各ゴール(結晶)が受け取った色が目標色の許容誤差内かどうかだけ**で判定する
  (別解・想定外の解法もクリアとして扱う)。

### 操作
- パレットから盤面へ **ドラッグ&ドロップ** で配置(タップ選択→空セルタップでも可)。
- 配置済み部品: タップで回転、ドラッグで移動、**盤外へドラッグで在庫へ回収**。

## 12. パクリ回避の確認ポイント
- 部品名・アイコン・BGM・UIデザイン・ステージ・ゲーム名はすべて独自に用意する。
- Electric Box の画像/音/文言/ステージを一切流用しない。
- 「連鎖変換パズル」というジャンル自体の流用は問題なし(ルール・アイデアは著作権対象外)。
  ※最終的な法的判断は専門家に確認すること。
