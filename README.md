# PlainWalk Web / iOS / Swift Playgrounds

PlainWalk の公開情報・提供された画面・APK の静的な構造を参考にした、非公式の独立実装です。**本家との完全一致は未達です。** 元アプリのコードや素材の一括コピーはしていません。課金・広告は設けず、実装済みのカスタマイズを無料で使えます。

| 対象 | 開く場所 | 画面と記録 |
|---|---|---|
| Web / PWA | `npm run build` → `dist/` | JavaScript / SVG、前面 GPS、IndexedDB |
| iOS / Xcode | `ios/PlainWalk.xcodeproj` | SwiftUI / Canvas / MapKit、Core Location、端末内ファイル |
| Swift Playgrounds | `ios/Playgrounds/PlainWalk.swiftpm` | 同じ SwiftUI の正本から生成、前面 GPS |

## iOS はネイティブ画面で起動します

起動先は `NativeRootView` です。マイマップは Canvas、記録・プロフィール・設定・コレクションは SwiftUI、答え合わせは MapKit を使います。標準タブ、ナビゲーション、シート、SF Symbols、触覚、PhotosPicker、カメラ、ファイル選択、共有シートを接続しています。

以前の `LocalWebApp` / `NativeBridge` は互換用のコードとして残しています。通常起動の画面には使いません。同梱 `Web/` にはブラウザ版の資源と、日本の境界 GeoJSON が入ります。Native のエリアバッジもこの実データを読みます。

- [ファイル配置と生成物](docs/project-structure.md)
- [確定したユーザー要件](docs/requirements.md)
- [提供画像 16 枚の分析](docs/app-analysis.md)
- [追加の画像・一次資料の分析](docs/research-deep-dive.md)
- [追加画像の目視・実装との比較](docs/research-parity-followup.md)
- [APK の静的解析と Android 画像](docs/apk-static-analysis.md)
- [APK の記録・保存・動作分類の仕組みと差分](docs/apk-mechanism-notes.md)
- [実装範囲と残差](docs/reproduction-audit.md)
- [実機検証と開発者機能](docs/device-testing.md)
- [Xcode の起動・署名](ios/README.md)
- [Swift Playgrounds の開き方](ios/Playgrounds/README.md)

## Web の起動

Node.js 22 以降と Python 3 を使います。

```sh
npm ci
npm run build
npm start
```

`http://localhost:4173` を開きます。実端末の位置情報・カメラ・PWA は HTTPS が必要です。編集する正本は `web/`、配信用 `dist/` は自動生成です。

Vercel は GitHub リポジトリのルートをユーザーが手動で Import してください。`vercel.json` がビルドと `dist/` 出力を指定します。Vercel の接続・デプロイは行っていません。

## Swift Playgrounds 用 ZIP

```sh
npm run playgrounds
```

`artifacts/packages/PlainWalk.swiftpm.zip` を生成します。展開した `.swiftpm` を iPad / Mac の Swift Playgrounds で開きます。生成済み ZIP に Node.js や Web サーバーは不要です。iPhone の署名・インストールは通常の Xcode 版を使います。

Playgrounds 版も SwiftUI / Canvas / MapKit を使います。HealthKit、Live Activity 拡張、ロック中の継続 GPS は利用範囲に含めません。

## 機能の範囲

| 機能 | Web | SwiftUI 版 |
|---|---|---|
| 白地図・記録・一時停止・終了・復旧 | 前面 GPS | Core Location、Xcode 版に背景記録コード |
| 配色・線・写真ピン・現在地・表示レイヤー | 実装 | ネイティブの選択画面と描画 |
| 履歴・カレンダー・統計・軌跡再生 | 実装 | SwiftUI で実装 |
| GPX / TCX 取り込み、GPX 出力、JSON バックアップ | 実装 | Files / 共有シート |
| 写真・短い動画・ひとこと | 実装 | PhotosPicker・カメラ・動画再生 |
| 旗・しおり・らくがき・ステッカー | 実装 | SwiftUI / MapKit / Vision |
| 日本 1,905 区域のバッジ | 実 GeoJSON の判定 | 同じ実 GeoJSON を Swift で判定 |
| 共有の白地図 | 選んだ線のファイル交換 | 同じ形式のファイル交換 |
| 写真フィルム・3D LUT | 実装 | CoreImage、.cube 取り込み・比較プレビュー |
| 手動軌跡修正 | 実装 | MapKit の点移動・削除・区切り・Undo |
| 動画書き出し | 実装 | 未実装 |
| ノート | 写真・道の自由配置、切り抜き、PNG 出力 | 文章・紙・書体、スライダーでの配置調整、PNG 出力 |

共有白地図には選んだ線だけを入れ、日時・写真・メモを除きます。招待リンクによる共同編集・自動同期はありません。立体バッジや猫の見た目・演出は独自実装です。Watch、通常のウィジェット、自動開始、iCloud 自動同期、日本以外の境界、道路へのスナップ、公式と同じ近接交換は未実装です。

## 検証と限界

```sh
npm test
npm run check
python3 ios/validate_project.py
# npm run build と npm start の後、別ターミナルで:
npx playwright install chromium
npm run test:browser
```

2026-10-29 のローカル検証では、単体テスト 25 件、Chromium の 7 スイート、構文チェック、Web ビルドが通過しました。新しい保存整合性テストは、GPX / TCX、保存失敗、再読み込み、取り込みの再試行、ネイティブ拡張データの保持を確認します。ネイティブ接続のブラウザ試験はモックです。Linux WebKit の以前の操作試験も、iPhone 実機検証とは区別します。

[GitHub Actions 40922182440](https://github.com/mai-ima/plainWalk/actions/runs/40922182440) で、Xcode 本体・Live Activity 拡張・Swift Playgrounds パッケージのコンパイルが通過しました。Xcode 版は iPhone Simulator で起動し、記録復旧・保存失敗と再試行・GPX / TCX・共有ファイル・地図カメラの自己テスト、主要画面の表示完了待ち、診断画像のタイトル検出も通過しています。画像を見比べ、初期地図のカメラと設定ラベルを修正しました。実機の背景 GPS・HealthKit・電池消費・配布署名は未検証で、署名済み IPA はありません。

公式サイトは 2026-10-29 に再確認しました。12 m グリッド、手動記録、GPX / TCX、選んだ線だけの共有という公開仕様を参照しています。内部の判定閾値や全画面の完全一致を確定したものではありません。

端末やブラウザのデータ消去に備え、バックアップを保存してください。Web の取り込みは 45 MB、SwiftUI 版は 30 MB までです。短い動画の時間・容量を制限し、写真は保存前に圧縮します。設定・外観は記録のバックアップとは別に保存します。

Linux での Swift 構文検査は `pip install -r scripts/requirements-swift.txt` と `python3 scripts/check-swift-syntax.py` を使います。Apple API の型・実行検証は macOS CI と区別します。
