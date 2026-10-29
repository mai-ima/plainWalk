# Web アプリの正本

`src/` を編集し、`public/` に HTML・PWA・アイコンを置きます。`npm run build` は両方を `dist/` にコピーし、境界データを展開します。ブラウザの配信 URL は変更しません。

- `app.js`: 画面・記録・イベントを接続。
- `core.js`, `units.js`: 位置計算、インポート、バックアップ、単位。
- `native.js`: Swift とのメッセージ契約。
- `areas.js`: 自治体のポリゴン判定と表示。
- `collections.js`: ステッカー一覧、らくがき、しおり、白地図ファイル。
- `notebook.js`, `effects.js`, `media.js`: ノート、画像処理、短い動画。
- `reference-ui.js`, `companion.js`, `style.css`: 参照画像に沿った画面と相棒。

ランタイムの外部 npm ライブラリはありません。Playwright は開発時のテストにだけ使います。生成済み `dist/` を直接編集せず、正本を修正して再ビルドしてください。

## ネイティブ版との関係

通常の iOS / Playgrounds は `ios/PlainWalk/NativeRootView.swift` から SwiftUI の画面を開きます。このフォルダの Web UI はブラウザ版の正本です。旧 WebView 用の `native.js` 契約は互換コードとして残し、モックで検証します。

保存キー・ミリ秒の時刻・切断点・JSON バックアップを Swift と揃えますが、ブラウザとアプリの保存領域は自動同期されません。バックアップは既存の記録を ID で重複排除し、未知の root / ノート項目を保持します。GPX / TCX は空の座標を除外し、欠損区間を線でつなぎません。時刻のない点には補間・補完値を使います。

Web に実装した LUT、手動軌跡修正、軌跡の動画書き出しは、SwiftUI 版の実装済み機能とは区別します。ノートは双方で配置を保持・調整し PNG を出力しますが、直接ドラッグとスライダーという操作差があります。境界 GeoJSON は `dist/` 経由で同梱し、ネイティブの区域判定にも使います。

`npm run test:browser -- data-integrity` は、ブラウザの XML パーサー、保存失敗、再読み込み、取り込みの再試行を確認します。ネイティブ連携の部分はモックであり、iOS の実機動作を検証したものではありません。
