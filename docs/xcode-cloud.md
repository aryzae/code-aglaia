# Xcode Cloud / TestFlight セットアップ手順

Prism(Aglaia)を Xcode Cloud でビルド・テストし、TestFlight へ配信するための手順。
**リポジトリ側の準備は完了済み**なので、以下は Xcode / App Store Connect の画面で行う操作。

## 1. リポジトリ側で用意済みのもの

| ファイル | 役割 |
|---|---|
| `Aglaia/Aglaia.xcodeproj/xcshareddata/xcschemes/Aglaia.xcscheme` | **共有スキーム**。Xcode Cloud はこれが無いとワークフローを作れない。Build/Test(AglaiaTests + AglaiaUITests)/Archive(Release)を定義 |
| `Aglaia/ci_scripts/ci_post_clone.sh` | clone 直後に実行。全ステージの解けることを機械検証し、壊れたステージがビルドに乗るのを防ぐ。TestFlight のテスト対象テキストにビルド情報を追記 |
| `Aglaia/ci_scripts/ci_pre_xcodebuild.sh` | archive 前に実行。`CI_BUILD_NUMBER` をアプリのビルド番号に反映(**TestFlight の「ビルド番号が既に使われています」エラーを防ぐ**) |
| `Aglaia/TestFlight/WhatToTest.ja.txt` / `WhatToTest.en-US.txt` | TestFlight の「テスト対象」。Xcode Cloud が自動で読み込む。**配信内容が変わったら手で更新すること** |
| `Aglaia/Aglaia/Prism/Store/Prism.storekit` | ローカルでの課金テスト用 StoreKit 構成ファイル(後述) |

> `ci_scripts` と `TestFlight` は `.xcodeproj` と同じ階層(`Aglaia/`)に置いてある。
> 万一 Xcode Cloud が認識しない場合はリポジトリルートへ移動する。

## 2. App Store Connect でのアプリ登録

Xcode Cloud のワークフローを作る前に、アプリのレコードが必要。

1. [App Store Connect](https://appstoreconnect.apple.com) → 「マイ App」→ 「+」→ 新規 App
2. 入力値:
   - プラットフォーム: iOS
   - **バンドルID: `jp.aryzae.Aglaia`**(プロジェクトの `PRODUCT_BUNDLE_IDENTIFIER` と一致必須)
   - SKU: 任意(例 `prism-001`)
   - 主要言語: 日本語

バンドルIDが一覧に出ない場合は、先に
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) で
`jp.aryzae.Aglaia` を Identifier として登録し、**In-App Purchase** のケーパビリティを有効にする。

## 3. App内課金(IAP)の商品登録

App Store Connect → 対象App → 「App内課金」→ 「+」で **非消耗型** を2つ作成する。

| 参照名 | プロダクトID | 内容 |
|---|---|---|
| Prism Standard Pack | `jp.aryzae.Aglaia.prism.pack.standard` | ステージ11〜50を解放 |
| Prism Extra Pack | `jp.aryzae.Aglaia.prism.pack.extra` | ステージ51〜100を解放 |

> **重要**: App Store Connect で一度作成したプロダクトIDは変更も再利用もできない。
> 上記IDはコード側(`LevelPack.productID`)と完全に一致している必要があるので、
> 作成前に必ず綴りを確認すること。

各商品には表示名・説明・価格・審査用スクリーンショットが必要。
審査用スクリーンショットはステージ選択画面の購入セクションを撮れば足りる。

## 4. Xcode Cloud ワークフローの作成

Xcode で `Aglaia.xcodeproj` を開き、**Product → Xcode Cloud → Create Workflow**。

1. **アプリの選択**: `Aglaia` を選ぶ(共有スキームがあるので候補に出る)
2. **ソースコードの許可**: GitHub の `aryzae/code-aglaia` へのアクセスを許可する
   (GitHub 側で Xcode Cloud の App をインストールする画面が出る)
3. ワークフローを次のように構成する:

| 項目 | 推奨設定 |
|---|---|
| **Start Conditions** | Branch Changes → `master`(および必要なら `claude/*`) |
| **Environment** | Xcode は手元と同じバージョンを固定。`Clean` はオフでよい |
| **Actions: Build** | スキーム `Aglaia` / Platform: iOS |
| **Actions: Test** | スキーム `Aglaia` / Destination: iPhone(最新)シミュレータ |
| **Actions: Archive** | スキーム `Aglaia` / **Deployment Preparation: TestFlight (Internal Testing Only)** |
| **Post-Actions** | TestFlight Internal Testing → 配信したいテスターグループを指定 |

> テストとアーカイブを1つのワークフローに入れておくと、
> **テストが落ちたら TestFlight に配信されない**ので安全。

## 5. TestFlight 配信

1. 上記ワークフローが `master` への push で自動的に走る
2. Archive が成功すると TestFlight に自動アップロード
3. 内部テスターは追加のレビュー無しですぐ利用可能
   (外部テスターに配る場合は初回のみ Beta App Review が必要)

配信のたびに `Aglaia/TestFlight/WhatToTest.ja.txt` を更新しておくと、
テスターに「今回何を見てほしいか」が届く。

## 6. 課金のテスト

### ローカル(シミュレータ・実機デバッグ)
StoreKit 構成ファイルを使えば App Store Connect 無しで購入フローを試せる。

1. Xcode で **Product → Scheme → Edit Scheme… → Run → Options**
2. **StoreKit Configuration** に `Prism.storekit` を選ぶ
3. 実行すると、実際の課金なしで購入・復元が動作する
   (購入状態のリセットは Xcode の Debug → StoreKit → Manage Transactions)

### TestFlight
TestFlight のビルドは**サンドボックス課金**になる。実際の請求は発生しない。
App Store Connect で作った商品が「送信準備完了」以上のステータスである必要がある。

## 7. 既知の注意点

- **SwiftFormat のビルドフェーズは CI ではスキップされる**。
  `$CI == TRUE` を見て早期 exit するようにしてある(CI でソースを書き換えるのは不適切で、
  SwiftFormat のソースビルドに数分かかるため)。ローカルでは従来どおり動作する。
- **`Aglaia.entitlements` は削除済み**。中身が macOS 用のサンドボックス設定で、
  iOS アプリには不要かつ配信時のノイズになるため。今後 Push 通知や iCloud を
  使う場合は Xcode の Signing & Capabilities から追加すると再生成される。
- **対応プラットフォームを iOS のみに変更済み**(以前は macOS も含まれていた)。
- 画面の向きは現状 iPhone でも横向きを許可している。縦持ち専用にするなら
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` を
  `UIInterfaceOrientationPortrait` のみに絞る。
