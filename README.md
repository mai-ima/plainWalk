# PlainWalk Web / iOS / Swift Playgrounds

PlainWalk の公開情報・提供された画面・APK の静的な構造を参考にした、非公式の独立実装です。**本家との完全一致は未達です。** 元アプリのコードや素材の一括コピーはしていません。課金・広告は設けず、実装済みのカスタマイズを無料で使えます。

| 対象 | 開く場所 | 画面と記録 |
|---|---|---|
| Web / PWA | `npm run build` → `dist/` | JavaScript / SVG、前面 GPS、IndexedDB |
| iOS / Xcode | `ios/PlainWalk.xcodeproj` | SwiftUI / Canvas / MapKit、Core Location、端末内ファイル |
| Swift Playgrounds | `ios/Playgrounds/PlainWalk.swiftpm` | 同じ SwiftUI の正本から生成、前面 GPS |

## iPhone だけで使う

PC や有料開発者登録を持たない現在の利用経路は、[確認用 Web](https://plainwalk-web-map.jinmai2000.chatgpt.site/)です。Safari で開き、共有メニューからホーム画面へ追加できます。[iPhone での使い方](https://plainwalk-web-map.jinmai2000.chatgpt.site/iphone/)と[画面一覧](https://plainwalk-web-map.jinmai2000.chatgpt.site/screens/)も、ブラウザで見られます。確認用サイトは本人限定です。

Web の GPS は画面ロックやアプリ切り替えで更新が止まる場合があります。SwiftUI 版は継続開発していますが、署名済み IPA と TestFlight 配布はまだありません。Swift Playgrounds 用 ZIP は iPad / Mac 向けで、iPhone に直接インストールするものではありません。

## iOS はネイティブ画面で起動します

起動先は `NativeRootView` です。マイマップは Canvas、記録・プロフィール・設定・コレクションは SwiftUI、答え合わせは MapKit を使います。iPhoneの固定タブ、標準のナビゲーション・シート、SF Symbols、触覚、PhotosPicker、カメラ、ファイル選択、共有シートを接続しています。

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
- [全画面確認の範囲と撮影方法](docs/screen-coverage.md)
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

Vercel への接続・デプロイは行いません。現在の確認用サイトは本人限定の公開範囲を維持します。

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

2026-11-09 の再開後、Web の単体テスト 49 件、Chromium の 9 スイート、構文チェック、Web ビルドが通過しました。地図描画の回帰は 12 シナリオで、実動画の復号・再生・保存・再表示も確認しています。保存整合性テストは GPX / TCX、保存失敗、再読み込み、取り込みの再試行、ネイティブ拡張データの保持を確認します。ネイティブ接続のブラウザ試験はモックで、iOS の実行試験とは区別します。

Native は再開後の CI で本体・Playgrounds のビルドが通過しましたが、Simulator の MapKit 3D pitch 検証が未通過です。地図の表示範囲と写真一覧の撮影に関する追加修正も、最新 CI での実行確認を待っています。ビルド成功だけで Native の動作確認完了とは扱いません。

Web は 86 の画面・状態を **113 枚**に再撮影しました。長い画面の追加スクロール 27 区間を含みます。合成データ・393 × 852 の Chromium モバイル模擬で、撮影失敗・JavaScript エラーはありません。全画像を個別に開き、ファイル名・SHA-256・可視状態を記録し、新しい重大な欠け・未描画・残った読み込み表示がないことを確認しました。動画は実際の復号と再生時間の進行を確認してから停止して撮影しています。

Native 86 枚の最新差分の再撮影・文字確認・目視を完了した後、Web と合わせた **199 枚**の一覧へ更新する予定です。現在の確認用サイトと配布 ZIP は以前の検証済み版のままです。[画面確認の範囲](docs/screen-coverage.md)に、撮影方法と OS・実機限定の残差を記録しています。

実機の起動・カメラ・背景 GPS・HealthKit・電池消費・配布署名は未検証で、署名済み IPA はありません。Web は JPEG の撮影情報を対象とし、取得できない情報を推測して配置しません。細かな寸法や未実装機能を含め、本家の完全一致ではありません。

2026-11-01 の [CI 41302732947](https://github.com/mai-ima/plainWalk/actions/runs/41302732947) の全 11 ジョブ成功、当時の Swift 86 枚・Web 114 枚の一覧、[画像200枚と地図の精度の監査](docs/image-map-audit.md)は旧版の履歴です。固定バー・写真一覧の修正を確認した [CI 41307487157](https://github.com/mai-ima/plainWalk/actions/runs/41307487157) も、後続差分の検証成功とは扱いません。[再開後の確認事項](docs/work-checkpoint.md)を参照してください。

公式サイトと写真の公式説明は 2026-11-01 に再確認しました。12 m グリッド、手動記録、GPX / TCX、選んだ線だけの共有という公開仕様を参照しています。内部の判定閾値や全画面の完全一致を確定したものではありません。

端末やブラウザのデータ消去に備え、バックアップを保存してください。Web の取り込みは 45 MB、SwiftUI 版は 30 MB までです。短い動画の時間・容量を制限し、写真は保存前に圧縮します。設定・外観は記録のバックアップとは別に保存します。

Linux での Swift 構文検査は `pip install -r scripts/requirements-swift.txt` と `python3 scripts/check-swift-syntax.py` を使います。Apple API の型・実行検証は macOS CI と区別します。
