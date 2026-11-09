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

Nativeアプリのコンパイル・Simulator実行と、Playgroundsコンパイルの基準ソース `e9f77e354bc528488ec318b8b32f115c0c391893` の [CI 42598341045](https://github.com/mai-ima/plainWalk/actions/runs/42598341045) は全11ジョブ成功です。Web単体49件、Chromium9スイート（地図描画12シナリオ）、39 Swiftファイルの構造・構文検査、本体・Live Activity拡張・Playgroundsのコンパイル、Playgrounds生成71ファイルと正本のバイト照合、Simulatorの自己テスト・実表示・文字確認を含みます。後続の画面一覧専用JavaScript修正は、このCI後に配信用資源の実操作を対象とした別のブラウザ検証で確認しました。Native/Playgroundsの同梱互換Web資源はCI時点のまま維持し、検証済み71ファイルは再生成していません。 ネイティブ接続のブラウザ試験はモックで、iOSの実行試験とは区別します。

MapKitは高度により傾斜を制限します（[Appleのpitch資料](https://developer.apple.com/documentation/mapkit/mkmapcamera/pitch)）。今回の条件では要求55°に対する実値は約35°で、独立したMapKit対照と完了後に安定した実カメラを比較し、中心・距離と拡大縮小時の角度保持を確認しました。写真の配置欄は0.137ptの測定端数を表示画素へ整列して判定し、全配置欄と「現在地に置く」のOCR確認を維持しています。日付変更線を跨ぐ短い軌跡は、連続した線とローカルな初期表示範囲を確認しました。DEBUGの対照地図を安定して保持する検証ハーネスと、通常起動のカメラ実装は区別しています。

Webは86状態・113枚、追加スクロール27区間です。旧114枚から1枚減ったのは、動画モードで写真専用フィルム・LUTを隠し、第2区間が不要になったためです。実MP4の復号と再生時間の進行後に停止して撮影しました。合成データのChromiumモバイル模擬で、iPhone実機の結果とは区別します。

**Native86枚＋Web113枚の全199枚を個別に開いて確認し、SHA-256と実際の撮影元を[更新後の画像監査](docs/references/image-audit-2026-11-09.json)に記録しました。配信用一覧を199枚で生成し、Linux WebKitの393×852・タッチ設定で全画像の読み込み、検索・分類・拡大・戻る、iPhone案内との導線を確認しました。これは配信用生成物の検証で、確認用サイトへの公開更新完了を意味しません。**

Native画像は単一コミットの一括撮影ではありません。collections12枚・layers-developer13枚・settings-a8枚・settings-b8枚の計41枚は `b29eddf2d39fe2bb4693704f5f3624a02328f269`、creation10枚の計10枚は `b6ab64dfecba44bc9b0d9534cd6d19c08519739f`、records13枚の計13枚は `9f9a05ea0052e943c3368f7baf1f8490491e619a`、baseline14枚の計14枚は `e9f77e354bc528488ec318b8b32f115c0c391893`、maps8枚の計8枚は `63b4d832d656cdaa8ca8166cd1c28f8091a58ef9` が実際の撮影元です。recordsを含め、監査のグループ別出典と実画像のSHA-256をそのまま保存しました。Web113枚は `722e90a798ec9c4b9ced14195e62bccb37e23c92` で撮影し、Web正本27ファイルが最終アプリソース `e9f77e354bc528488ec318b8b32f115c0c391893` まで不変であることを照合しました。その後の変更は配信用一覧のviewer専用で、113枚の撮影対象であるWebアプリ本体やNative画像の変更ではありません。 maps8枚は `63b4d832d656cdaa8ca8166cd1c28f8091a58ef9` の実画像を保持しました。最終実行検証 `e9f77e354bc528488ec318b8b32f115c0c391893` との差分はDEBUGの数値判定で、DEBUGを除くMapKitカメラ実装のSHA-256 `4e234fdb756efa433af98f89e260b1838f71f315a2ee98910ed16f494c525494` と、他の正本アプリSwift全ファイルの不変を照合しています。撮影元を実行検証版へ書き換えてはいません。 NativeのstepGoal1枚はOSのApple Intelligence通知がヘッダーへ重なる撮影状態で、タイトルと閉じる操作の外観はそのPNGから確認できません。アプリの欠けとは判定せず、通知を画像編集で除去していません。 [撮影範囲と出典](docs/screen-coverage.md)も参照してください。

実機の起動・カメラ・背景 GPS・HealthKit・電池消費・配布署名は未検証で、署名済み IPA はありません。Web は JPEG の撮影情報を対象とし、取得できない情報を推測して配置しません。細かな寸法や未実装機能を含め、本家の完全一致ではありません。

2026-11-01 の [CI 41302732947](https://github.com/mai-ima/plainWalk/actions/runs/41302732947) の全 11 ジョブ成功、当時の Swift 86 枚・Web 114 枚の一覧、[画像200枚と地図の精度の監査](docs/image-map-audit.md)は旧版の履歴です。固定バー・写真一覧の修正を確認した [CI 41307487157](https://github.com/mai-ima/plainWalk/actions/runs/41307487157) も、後続差分の検証成功とは扱いません。[再開後の確認事項](docs/work-checkpoint.md)を参照してください。

公式サイトと写真の公式説明は 2026-11-01 に再確認しました。12 m グリッド、手動記録、GPX / TCX、選んだ線だけの共有という公開仕様を参照しています。内部の判定閾値や全画面の完全一致を確定したものではありません。

端末やブラウザのデータ消去に備え、バックアップを保存してください。Web の取り込みは 45 MB、SwiftUI 版は 30 MB までです。短い動画の時間・容量を制限し、写真は保存前に圧縮します。設定・外観は記録のバックアップとは別に保存します。

Linux での Swift 構文検査は `pip install -r scripts/requirements-swift.txt` と `python3 scripts/check-swift-syntax.py` を使います。Apple API の型・実行検証は macOS CI と区別します。
