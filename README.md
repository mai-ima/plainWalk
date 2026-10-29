# PlainWalk Web / iOS / Swift Playgrounds

PlainWalk の公開情報と提供された画面を参考にした非公式の独立実装です。**完全再現は未達です。** 課金・広告なし。追加の beta 機能は設定から切り替えます。

| 対象 | 開く場所 | 主な動作 |
|---|---|---|
| Web / PWA | `npm run build` → `dist/` | Safari・ホーム画面、前面 GPS、端末内保存 |
| iOS / Xcode | `ios/PlainWalk.xcodeproj` | 同梱 Web UI＋Core Location・HealthKit・Live Activity・MapKit |
| Swift Playgrounds | `ios/Playgrounds/PlainWalk.swiftpm` | iPad / Mac で編集・実行する前面記録版 |

- [構成・生成物の配置](docs/project-structure.md)
- [確定したユーザー要件](docs/requirements.md)
- [提供画像 16 枚の分析](docs/app-analysis.md)
- [追加の画像・一次資料の分析](docs/research-deep-dive.md)
- [実装範囲と残差](docs/reproduction-audit.md)
- [Xcode 版の起動・署名](ios/README.md)
- [Swift Playgrounds 版の開き方](ios/Playgrounds/README.md)

## Web の起動

Node.js 22 以降と Python 3 を使います。

```sh
npm ci
npm run build
npm start
```

`http://localhost:4173` を開きます。実端末の位置情報・カメラ・PWA は HTTPS が必要です。編集する正本は `web/`、配信用 `dist/` は自動生成します。

Vercel は GitHub リポジトリのルートを手動で Import してください。`vercel.json` がビルドと `dist/` 出力を指定します。こちらから Vercel の接続・デプロイは行いません。

## Swift Playgrounds 用 ZIP

```sh
npm run playgrounds
```

`artifacts/packages/PlainWalk.swiftpm.zip` を生成します。展開後の `.swiftpm` を iPad / Mac の Swift Playgrounds で開けます。生成済み ZIP は単独で動く構成で、Web サーバーや Node.js は不要です。iPhone 向けの署名・インストールは通常の Xcode 版を使います。

Playgrounds 版は前面 GPS、ファイル保存、MapKit、Vision、モーション歩数、同じ Web UI を同梱します。HealthKit・Live Activity 拡張・ロック中の継続記録を使える版としては扱いません。iPad 実機での動作は未検証です。

## 実装した機能

白地図、GPS 記録、一時停止と長押し終了、中断復旧、12 m セルによる開拓距離の近似、通った回数による線の変化、履歴・カレンダー・統計、GPX / TCX 入出力、JSON バックアップ、写真・短い動画、フィルム・3D LUT、旗と方角、しおり、地図上のらくがき、ノートの自由配置・切り抜き・画像出力、軌跡の修正・再生・動画出力、日本 1,905 区域のエリアバッジ。

標準＋14 配色と実装済みカスタマイズは無料。共有の白地図は、選んだ線だけの JSON ファイルを交換する方式です。日時・写真・メモを除外し、共同編集や自動同期は行いません。猫は独自 SVG で、公式の立体モデルとは異なります。

## 検証と限界

```sh
npm test
npm run check
python3 ios/validate_project.py
# npm start を起動した別ターミナルで:
npx playwright install chromium
npm run test:browser
```

15 件の単体テストと、Chromium / Linux WebKit の主要画面・保存復旧・操作が通過。テストは `tests/unit/` と `tests/browser/`、画像や動画は `artifacts/previews/` に分離しました。

通常の iOS 版は [GitHub Actions 40888890524](https://github.com/mai-ima/plainWalk/actions/runs/40888890524) で本体・拡張のコンパイル、iPhone Simulator 起動、Web/native 接続、位置ジャーナル復旧が通過。実機の背景 GPS・HealthKit・電池消費・配布署名は未検証で、署名済み IPA はありません。Playgrounds 版の検証は通常版と区別します。

Watch アプリ、通常のウィジェット、自動開始、共有の自動同期、日本以外の区域、公式と同じ立体バッジ、道路へのスナップ、写真の深度ぼかし、動画ピンへのフィルム、公式と同じ近接交換は未実装です。Web の傾斜表示は建物の 3D 表示ではありません。

端末やブラウザのデータ消去に備え、バックアップを保存してください。インポートは 45 MB、動画は 15 MB / 2.6 秒以内。写真は読み込み後に圧縮します。外観設定はバックアップに含みません。
