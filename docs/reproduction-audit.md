# PlainWalk 再現調査・対応表

更新日: 2026-10-29。公開資料と実装を対照した記録です。完全一致の認定ではありません。

## 調査の根拠

- [公式サイト](https://plainwalk.app/)を 2026-10-29 に再確認しました。12 m グリッド、手動 GPS 記録、GPX / TCX の取り込み、選んだ線だけの共有を確認しています。公式の Apple Watch・共有白地図は iPhone 向けとして扱います。
- [App Store](https://apps.apple.com/jp/app/id6800746478)、提供画像 16 枚、iTunes Lookup の画像、[公式の基本説明](https://note.com/plainwalk/n/nab36140b7cf1)、[写真とつぶやきの説明](https://note.com/plainwalk/n/nf160cabe8248)を調査済みです。画像ごとの記録は [画像分析](app-analysis.md) と [追加調査](research-deep-dive.md)にあります。
- 実際に取得した Android 1.1.0 XAPK の binary manifest、DEX の型構成、署名証明書の指紋を静的に確認しています。[APK の解析記録](apk-static-analysis.md)と [機械可読の要約](references/android-apk.json)を参照してください。
- App Store 以外では AppBrain の公開画像 8 枚を取得・個別に確認しました。出典とハッシュは [画像一覧](references/android-images.json)にあります。Android の画面を iOS の正解として扱いません。
- 動画の検索は行っていますが、全画面・全操作を網羅した操作動画の視聴記録はありません。未確認の動画を視聴済みとはしません。

APK から確認した TrackSession / TrackPoint / ModeSpan、位置サービスと receiver の分離は設計の参考です。難読化された名前や権限の存在だけで、元の閾値・UI・実装済み機能を確定しません。コードや素材の一括抽出・流用、ライセンス制御の回避はしていません。以下の画面とアルゴリズムは独立実装です。

Apple の実装資料: [SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas)、[MapKit](https://developer.apple.com/documentation/mapkit)、[Core Location 背景更新](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)、[HealthKit ルート](https://developer.apple.com/documentation/healthkit/reading-route-data)、[ActivityKit](https://developer.apple.com/documentation/activitykit)。

## 対応表

SwiftUI 版の通常起動は `NativeRootView` です。画面の実装があることと、コンパイル・実機試験が通過したことを区別します。

| 対象 | Web | SwiftUI / iOS | 残差・確認事項 |
|---|---|---|---|
| 白地図・現在地・線 | SVG、ブラウザ検証 | Canvas、パン・拡大縮小、現在地とピン | 内部描画仕様・公式との細かな一致は不明 |
| 記録・一時停止・長押し終了 | 前面 GPS、保存失敗・復旧の回帰試験 | Core Location と標準 UI・触覚 | 実歩行、権限変更、演出の照合が必要 |
| 背景 GPS | ブラウザ制限あり | Xcode 版に背景更新・ジャーナル | Playgrounds は前面のみ。実機未検証 |
| 保存・復旧 | IndexedDB | 保護付きファイル、ID・連番、互換 JSON | OS 終了・低容量時の実機試験が必要 |
| 歩数・Health ワークアウト | 歩数の手動入力 | モーション、Xcode 版の HealthKit 読み取り | 実機権限と実データの照合が必要 |
| 答え合わせ | OSM タイル | MapKit の標準・航空写真・3D・検索 | プロバイダと描画の一致保証なし |
| 地図の輪郭 | 日本の実 GeoJSON | 同じ 1,905 区域を倍率別にキャッシュ描画 | 世界境界・低倍率の都道府県境への切替は未対応 |
| 配色・線・ピン・相棒 | 標準＋14 配色、実線・点線・5 ピン種 | SwiftUI の選択と Canvas の描画 | 猫・動きは独自実装、全状態の対照未完了 |
| 写真・短い動画・ひとこと | 保存・再生 | PhotosPicker、カメラ、動画再生 | 実機の権限、位置・時刻の保持を確認する |
| フィルム・3D LUT | 実装 | CoreImage、.cube 取り込み、強さ・比較プレビュー | 公式 LUT の値や動画加工は未再現。独自プリセット |
| ノート | 自由配置、回転、切り抜き、PNG、仕上げ | 文章・紙・書体、スライダーの配置調整、PNG | ネイティブは直接ドラッグ編集なし。実機の描画・出力は未検証 |
| 軌跡の再生 | 再生・動画出力 | ネイティブの再生 | SwiftUI の動画書き出しは未実装 |
| 軌跡の手動修正 | 移動・削除・分割・Undo | MapKit の点移動・削除・区切り・Undo、明示保存 | 道路への自動スナップは未対応 |
| 旗・しおり | 方角・座標共有、しおりから旗 | MapKit の検索・選択、旗・しおり | 公式との導線・表示の完全対照は未完了 |
| エリアバッジ | 実 GeoJSON、ブラウザ検証 | 日本 1,905 区域の実境界を Swift で判定 | 日本以外、公式と同じ結晶・立体造形は未対応 |
| らくがき | 地図への描画・歩行時の更新 | MapKit 描画、保存・歩行での更新 | 消去判定・演出は独立実装 |
| ステッカー | 手動切り抜き、一覧・PNG | Vision、一覧、共有シート | 公式の近接交換は未実装 |
| 共有白地図 | 選んだ線の JSON ファイル | 同じ形式のファイル作成・交換 | 招待リンク・共同編集・自動同期は未対応 |
| GPX / TCX、バックアップ | 取り込み、GPX / JSON 出力 | Files、XML 解析、標準共有 | 双方で形式検証。未知の追加データを保持する |
| Live Activities | 対応不可 | ActivityKit / Dynamic Island 拡張 | Xcode のコンパイルは通過。実機表示は未検証 |
| Watch・通常ウィジェット・自動開始 | 未対応 | 未実装 | 別ターゲットや権限・同期実装が必要 |
| iCloud | ファイルの手動保存 | Files / 共有シートから選択 | 直接の自動同期ではない |

## 配色と計算の参照範囲

公式の公開配色アセット `https://plainwalk.app/assets/lang-menu-Bx17NVHy.js` の名称・paper・ink を照合した記録があります。標準＋14 色に反映していますが、iOS の全画面・明暗・状態の色が同一だとは断定しません。確認済みアセットの SHA-256 は `07983f270bb828d46747f64b7a39baeab3075ed710e17ae322ecb22b5067b34a` です。

開拓距離は 12 m セルと区間のサンプリングによる近似です。GPS の精度・揺れ・速度・時間欠損の処理、らくがきの消去、エリア内の距離も独自実装です。公開仕様や APK の型の存在から元の数値を復元できたとはしません。境界の出典とライセンスは [NOTICE](../web/public/data/NOTICE.md)にあります。

## 検証の状況

2026-10-29 のローカルで、単体テスト 25 件、Chromium 7 スイート、構文チェック、Web ビルドが通過しました。追加したデータ整合性テストは、空の GPX / TCX 座標、区間の切断、時刻 0、保存失敗、保存直後の再読み込み、重複排除、再取り込みを検証します。Web/native の連携はモックであり、iOS の動作試験ではありません。時刻のないファイルの時刻は補間・補完値です。

以前の [Xcode CI 40888890524](https://github.com/mai-ima/plainWalk/actions/runs/40888890524) と [Playgrounds CI 40898218214](https://github.com/mai-ima/plainWalk/actions/runs/40898218214)、Linux WebKit の操作試験は旧構成の履歴です。今回の SwiftUI 通常起動、Canvas、MapKit、コレクションを含む最新の macOS コンパイル・Simulator 結果は [README](../README.md)で確認してください。旧構成の成功を今回の成功として扱いません。

公開画像では全設定・初期状態・エラー・アニメーション・触覚を確定できません。公式アプリと同じデータを使う実機の対照試験が必要です。背景 GPS、HealthKit、カメラ、電池消費、配布署名は未検証で、署名済み IPA はありません。独自実装・モック・Simulator を本家の完全再現として扱いません。

実装済みのカスタマイズは無料で、課金・広告は追加しません。使えない自動開始・同期等は説明を表示し、架空の健康データや成功結果は出しません。

## 追加の再現作業

[追加比較](research-parity-followup.md)で確認した差分から、プロフィール内のコレクションと設定を、下部タブを保つ全面のネイティブナビゲーションに変更しました。答え合わせは MapKit の全面表示・浮いた見出しと閉じるボタン・下の目的地／らくがきボタン・右のレイヤー／現在地へ変更しました。OS の標準タブの形は iOS バージョンによって異なります。

設定のリセットは確認ダイアログを伴い、記録中・復旧中は拒否します。保存に失敗すれば表示中のライブラリを残し、成功後にさんぽ・写真・ノート・旗・共有地図などを消去します。外観などの設定は残ります。Live Activity は起動時にも復元済みの状態を照合します。

追加機能のコードには、軌跡編集のメタデータ・区切り・Undo・拒否時の不変性、実 CoreImage の LUT チャンネル順・JPEG 変換、境界ポリゴンの穴・島・簡略化の自己検証を含めています。最新 CI の成否は README の検証欄で区別します。


最新の [CI 40972605104](https://github.com/mai-ima/plainWalk/actions/runs/40972605104) は Web / iOS / Playgrounds の全ジョブ成功です。最初の起動で全自己テストを行い、その後は同じバイナリの画面撮影用起動で 12 画面を確認します。設定の初回遷移を修正した後の結果で、前の失敗した CI を成功扱いにしていません。iOS の新しい標準タブや、未実装の自動開始・同期・Watch などは原画像との残差です。
