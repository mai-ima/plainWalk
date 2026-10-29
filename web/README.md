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
