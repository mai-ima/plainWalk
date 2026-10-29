# ファイル配置と生成の流れ

## 編集する場所

```text
web/
  src/                 アプリの JavaScript と CSS の正本
  public/              HTML・PWA・アイコン・出典表示
    data/NOTICE.md     境界データのライセンス
  README.md            Web の編集・ビルド

ios/
  PlainWalk/           本体の Swift・権限・リソースの正本
  Shared/              Live Activity の共有データ型
  PlainWalkLive/       Live Activity / Dynamic Island 拡張
  PlainWalk.xcodeproj/ Xcode 用プロジェクト
  Playgrounds/         Swift Playgrounds 用パッケージと説明

datasets/              圧縮した地理データの原本
scripts/               ビルド・パッケージ生成・検証
tests/                下記のテスト用フォルダ
```

- `tests/unit/`: 距離・開拓・境界・バックアップ・LUT の計算テスト。
- `tests/browser/`: 端末サイズでの操作テスト。共通パス・ブラウザ設定は `support.cjs`。
- `tests/fixtures/`: 合成したテスト用動画。ユーザーの記録は置かない。
- `docs/`: 要件、画像の分析、調査根拠、実装と未対応の範囲。

## 自動生成する場所

| 出力 | 生成コマンド | 用途 |
|---|---|---|
| `dist/` | `npm run build` | Web 配信、Vercel、Xcode に同梱する画面 |
| `ios/Playgrounds/PlainWalk.swiftpm/Sources/` | `npm run playgrounds` | 正本から用意した Playgrounds のコード・画面 |
| `artifacts/packages/PlainWalk.swiftpm.zip` | `npm run playgrounds` | iPad / Mac に渡す単体パッケージ |
| `artifacts/previews/` | `npm run test:browser` | 確認用スクリーンショット・動画 |
| `.build/` | GitHub / Xcode | ビルド中間物・Simulator 画像 |

生成物は Git に重複して保存しない。編集は必ず正本で行い、再生成する。Playgrounds では HealthKit と Live Activity を利用可能に見せず、専用の説明を返す。位置記録は前面に限定する。通常の Xcode 版は背景 GPS と Live Activity のコードを保持する。

`dist/` の URL と保存キーは整理前と同じ。IndexedDB のデータベース名、ネイティブ保存ファイル、バックアップ形式、Service Worker のスコープを変更しないため、フォルダ整理だけでユーザーの記録を移行する必要はない。

## 検証

```sh
npm ci
npm run build
npm test
npm run check
npm start
# 別のターミナル:
npx playwright install chromium
npm run test:browser
```

`PW_ENGINE=webkit` は対応するテストで WebKit を選ぶ。必要に応じて `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` / `PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH` を指定できる。ブラウザテストは配信済みの `dist/` を操作するため、編集後に再ビルドする。

CI は Web の計算・構文・操作、通常の iOS 本体と拡張のビルド・起動、Swift Playgrounds パッケージのコンパイルを分けて実行する。Vercel には接続せず、GitHub をユーザーが手動で Import する設定を維持する。
