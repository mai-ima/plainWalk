# ファイル配置と生成の流れ

## 編集する場所

```text
web/
  src/                 ブラウザ版の JavaScript・CSS の正本
  public/              HTML・PWA・アイコン・出典表示
    data/NOTICE.md     境界データのライセンス
  README.md            Web の編集・ビルド

ios/
  PlainWalk/           SwiftUI の画面・状態・端末 API・権限の正本
    NativeRootView     標準タブ、ナビゲーション、シート
    NativeMyMapView    Canvas の白地図
    NativeAnswerMapView MapKit の地図・検索・目的地
    NativeRecordsView / NativeProfileView / NativeCollectionsView
    NativeAppModel / NativeModels / NativeStore
    NativeTrackMath / NativeTrackIO / NativeDoodleProgress
    NativeSettingsView / NativeDeveloperView
  Shared/              Live Activity の共有データ型
  PlainWalkLive/       Live Activity / Dynamic Island 拡張
  PlainWalk.xcodeproj/ Xcode 用プロジェクト
  Playgrounds/         Swift Playgrounds パッケージと説明

datasets/              圧縮した地理データの原本
scripts/               ビルド・パッケージ生成・検証
tests/                 計算・ブラウザ操作・合成フィクスチャ
docs/                  要件、画像分析、調査根拠、実装と残差
```

上の Swift ファイル名は拡張子 `.swift` を省略しています。通常の iOS / Playgrounds の起動先は `NativeRootView` です。ブラウザの画面を iOS の正本としては扱いません。旧 `LocalWebApp` / `NativeBridge` は互換コードとして残します。

- `tests/unit/`: 距離・開拓・境界・バックアップ・LUT・単位・診断のテスト。
- `tests/browser/`: ブラウザ操作と保存失敗・復旧の回帰テスト。`native-bridge` と `data-integrity` のネイティブ連携はモックです。
- `tests/fixtures/`: 合成したテスト用動画。ユーザーの記録は置きません。
- Swift の DEBUG 自己テスト: ジャーナル復旧、保存形式、距離計算、GPX / TCX を隔離したデータで確認するコードです。実機試験とは別です。

## 自動生成する場所

| 出力 | 生成コマンド | 用途 |
|---|---|---|
| `dist/` | `npm run build` | Web 配信、Vercel、アプリに同梱するリソース |
| `ios/Playgrounds/PlainWalk.swiftpm/Sources/` | `npm run playgrounds` | Swift の正本とリソースから生成するコード |
| `artifacts/packages/PlainWalk.swiftpm.zip` | `npm run playgrounds` | iPad / Mac に渡す単体パッケージ |
| `artifacts/previews/` | `npm run test:browser` | 確認用スクリーンショット・動画 |
| `.build/` | GitHub / Xcode | ビルド中間物・Simulator 画像 |

生成物を正本と重複して編集・保存しません。`dist/` の `Web/data/japan-municipalities.geojson` 相当のリソースは、SwiftUI の実境界バッジでも必要です。Xcode のビルド前にも `npm run build` を実行してください。

Playgrounds の生成では HealthKit / Live Activity を利用可能に見せず、背景 GPS を無効化します。通常の Xcode 版には背景 GPS と Live Activity のコードを残します。SwiftUI 版に未実装の LUT・手動軌跡修正・軌跡の動画出力は、ブラウザ版を同梱しただけでネイティブに実装済みとはしません。ノートの配置調整・PNG 出力も Swift 側のコードで行います。

## 保存の互換性

Web は IndexedDB `plainwalk-web`、ネイティブは Application Support の `PlainWalk/web-library.json` 等を使います。保存キー、ミリ秒の時刻、位置の切断点、バックアップの version 1 を維持し、未知の追加項目も保持します。アプリとブラウザ、別端末の保存領域を共有したり自動同期したりする仕組みではありません。移動にはバックアップの明示的な入出力を使います。

APK や分析作業用のファイルはアプリのソースと混ぜません。実体は調査用領域に置き、公開するのは [ハッシュ・構造・画像の出典](apk-static-analysis.md)です。元アプリのコードや素材をビルド資源へコピーしません。

## 検証

```sh
npm ci
npm run build
npm test
npm run check
python3 ios/validate_project.py
npm start
# 別のターミナル:
npx playwright install chromium
npm run test:browser
```

`PW_ENGINE=webkit` は対応するテストで WebKit を選びます。必要に応じて `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` / `PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH` を指定できます。ブラウザテストは `dist/` を操作するので、編集後に再ビルドします。

Web の計算・構文・操作、iOS 本体と拡張のビルド・起動、Playgrounds のコンパイルを CI で分けて検証します。今回の SwiftUI 化の最新の macOS 結果は [README](../README.md)を参照してください。以前の CI 成功を現在の変更の検証結果として扱いません。Vercel は接続せず、ユーザーが GitHub から手動で Import する設定を維持します。
