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
- [写真の撮影日時・場所と取り込み](docs/photo-import-parity.md)
- [iOS のノート操作と軌跡動画](docs/native-creation.md)
- [APK の静的解析と Android 画像](docs/apk-static-analysis.md)
- [APK の記録・保存・動作分類の仕組みと差分](docs/apk-mechanism-notes.md)
- [公式 Web コード・APK と実装の対応](docs/reference-mechanisms.md)
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
| 写真・短い動画・ひとこと | JPEG 撮影日時・場所を使う取り込み | ImageIO・PhotosPicker・カメラ・動画再生 |
| 旗・しおり・らくがき・ステッカー | 実装 | SwiftUI / MapKit / Vision |
| 日本 1,905 区域のバッジ | 実 GeoJSON の判定 | 同じ実 GeoJSON を Swift で判定 |
| 共有の白地図 | 選んだ線のファイル交換 | 同じ形式のファイル交換 |
| 写真フィルム・3D LUT | 実装 | CoreImage、.cube 取り込み・比較プレビュー |
| 手動軌跡修正 | 実装 | MapKit の点移動・削除・区切り・Undo |
| 動画書き出し | 実装 | AVFoundation の MP4 / 標準共有 |
| ノート | 写真・道の自由配置、切り抜き、PNG 出力 | 直接の移動・拡縮・回転、透明度・Undo、PNG 出力 |

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

2026-11-01 のローカル検証では、単体テスト 34 件、Chromium の 8 スイート、構文チェック、Web ビルドが通過しました。新しい保存整合性テストは、GPX / TCX、保存失敗、再読み込み、取り込みの再試行、ネイティブ拡張データの保持を確認します。ネイティブ接続のブラウザ試験はモックです。Linux WebKit の以前の操作試験も、iPhone 実機検証とは区別します。

[GitHub Actions 41297028999](https://github.com/mai-ima/plainWalk/actions/runs/41297028999) で Web、Xcode 本体・Live Activity 拡張、Simulator、Swift Playgrounds の全 4 ジョブが成功しました。Web は単体 34 件と Chromium 8 スイートが通過。Simulator では保存・復旧・軌跡・写真の従来テストに加え、ノートの配置計算とジェスチャー再開時の基準更新、実 MP4 の生成・復号・キャンセルが通過しました。ノート編集を含む 14 画面を撮影し、診断画像のタイトル検出も通過しています。MP4 の試験出力は合成データの 360 × 640、8 fps、1 秒で、実際の複数指操作や既定の長時間出力の実機検証とは区別します。

前段の CI 41293979673 は写真追加画面の完了待ちで初回失敗し、同じバイナリの再試行で成功しました。期限後の画像では画面が表示されていましたが、期限内の描画までは確定できません。中間の CI 41295495000 では記録、41296423376 では設定の完了待ちが失敗しました。後者のログは、追加した UIKit の移動フラグの条件で停止したことを示しました。その条件を取り除きました。SwiftUI の表示構造と UIKit の管理上の親子関係が一致すると仮定する条件を改め、選択中の画面・実描画・配置・遷移の照合と待機理由の記録、各起動前の古い完了ファイルの削除を含めて検証しています。

実機の起動・カメラ・背景 GPS・HealthKit・電池消費・配布署名は未検証で、署名済み IPA はありません。Web は JPEG の撮影情報を対象とし、取得できない情報を推測して配置しません。OS の標準タブ・細かな寸法、未実装機能を含め、本家の完全一致ではありません。

公式サイトと写真の公式説明は 2026-11-01 に再確認しました。12 m グリッド、手動記録、GPX / TCX、選んだ線だけの共有という公開仕様を参照しています。内部の判定閾値や全画面の完全一致を確定したものではありません。

端末やブラウザのデータ消去に備え、バックアップを保存してください。Web の取り込みは 45 MB、SwiftUI 版は 30 MB までです。短い動画の時間・容量を制限し、写真は保存前に圧縮します。設定・外観は記録のバックアップとは別に保存します。

Linux での Swift 構文検査は `pip install -r scripts/requirements-swift.txt` と `python3 scripts/check-swift-syntax.py` を使います。Apple API の型・実行検証は macOS CI と区別します。
