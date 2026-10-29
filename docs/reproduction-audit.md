# PlainWalk 再現調査・対応表

調査日: 2026-10-29。完全一致の認定ではなく、実装の根拠と残差を記録する。

## 一次資料

1. https://plainwalk.app/ — 白地図、12 m グリッド、写真・動画、エリア、Plus、1.17 の機能一覧。
2. https://apps.apple.com/jp/app/id6800746478 — iPhone のスクリーンショット、アプリ説明、バージョン履歴。iTunes Lookup API の日本ストア結果も確認。10 枚のスクリーンショットのうち白地図、答え合わせ、旗、配色、記録画面を目視で照合。
3. https://note.com/plainwalk/n/nab36140b7cf1 — 公式の基本機能の説明。
4. https://note.com/plainwalk/n/nf160cabe8248 — 写真とつぶやき、旅行での利用。
5. Web・画像・動画検索も実施。「PlainWalk app youtube 動画 操作」等では全画面と全操作を網羅した動画は見つからず。動画内容を視聴済みとする記録はない。

## Apple の実装資料

- https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- https://developer.apple.com/documentation/healthkit/reading-route-data
- https://developer.apple.com/documentation/widgetkit/activityconfiguration
- https://developer.apple.com/documentation/webkit/wkwebviewconfiguration

## 対応表

| 対象 | Web | iOS プロジェクト | 完全一致との残差 |
|---|---|---|---|
| 白地図・現在地・線 | 実装・ブラウザ検証 | 同じ UI を同梱 | 正確な内部描画仕様は不明。線の頻度・投影は独立実装 |
| 記録・一時停止・長押し終了 | 実装 | native 位置記録に接続 | アニメーション・振動のタイミングは完全照合していない |
| 背景 GPS | ブラウザ制限あり | Core Location コード追加 | Xcode CI ビルド通過、ロック状態の実機検証が必要 |
| 記録の永続化・復旧 | IndexedDB、検証済み | protected file と native session | iOS の OS 終了・低容量は未検証 |
| 歩数 | 手動 | HealthKit 取得コード | 実機権限・Apple Watch データとの比較が必要 |
| Health ワークアウト | 対応不可 | ルート選択・読み込みコード | 実機 Health データが必要 |
| 答え合わせ | OSM タイル | MapKit の標準・航空写真・3D | 地図プロバイダと見た目は元アプリと一致保証なし |
| 配色・線・ピン・相棒 | 標準＋14 配色、3 線種、2 ピン種 | 同じ UI | 配色は公式サイト公開値に一致。iOS アプリ内の全配色との対照試験は未完了。相棒の公式アニメーションは不明。相棒はプロフィール表示 |
| 写真ピン・フィルム・LUT | 実装、写真の保存検証 | 同じ UI | フィルムは独立実装。公式 LUT の値は不明 |
| 1〜2 秒動画 | ファイル入力・対応環境のカメラ | 同じ UI | 動画自体へのフィルム加工とルート再生への差し込みは未対応 |
| ノート・画像書き出し | 紙・書体・写真と道のドラッグ配置・回転・PNG・手動切り抜き・箔/ホログラム | Vision 自動切り抜きコードも追加 | 公式の演出・交換は未対応、Vision は実機未検証 |
| 再生・動画出力 | 実装、6 秒出力検証 | 同じ UI、実機未検証 | 公式の演出・動画ピン再生・映像合成は未再現 |
| 軌跡の手動修正 | ドラッグ・削除・分割・Undo、検証 | 同じ UI | 道路への自動スナップは未対応 |
| 旗 | 複数・順序・座標共有 | 同じ UI | 住所検索・公式の共有導線は未再現 |
| エリアバッジ | 日本 1,905 区域のポリゴン判定・輪郭・訪問距離、WebKit 検証 | 同じ UI | 日本以外のデータ、公式の結晶造形との一致は未対応 |
| Live Activities | 対応不可 | ActivityKit と拡張コード | ビルド・実機未検証。通常のウィジェットではない |
| Watch・自動開始・共有白地図 | 未対応 | 未実装 | 追加ターゲット、権限、同期プロトコルが必要 |
| iCloud | ファイルの手動保存 | Files で選べる共有・復元 | 直接の自動同期ではない |

## 完全再現を断定できない理由

公開の宣伝用画面だけでは、全設定、全モーダル、初期状態、エラー状態、各 OS バージョン、アニメーションや触覚の仕様は確定できない。実機の公式アプリと同じデータを用いた画面・操作の対照試験が必要。現在は元アプリの全状態の記録がなく、作業機は Linux で、GitHub macOS CI による Xcode ビルドは通過。Apple の実機署名環境はない。

独自実装や模擬検証を公式との完全一致として扱わない。未実装のボタンに偽の成功結果や架空の健康・境界データを出すことはしない。

前回の指定を引き継ぎ、購入・課金・広告を設けず、実装済みのカスタマイズは無料。beta 機能は設定から切替可能。

## 配色データの照合

https://plainwalk.app/assets/lang-menu-Bx17NVHy.js の公開配色定義を確認。標準＋14 色の名称、paper と ink の値を反映。これは公式 Web サイトの値であり、iOS の全状態の色が同じだとは断定しない。

検証した配色アセットの SHA-256: `07983f270bb828d46747f64b7a39baeab3075ed710e17ae322ecb22b5067b34a`

## 継続改善

日本の市区町村 1,905 区域の境界を端末内で判定するエリアバッジを実装。出典は dist/data/NOTICE.md。ノートに写真・道・切り抜き画像を配置し、サイズ・回転・紙・書体・仕上げを変更できる。WebKit の不足ライブラリを作業領域内に準備し、Linux WebKit でモバイルの GPX・エリアバッジ・ノート・保存復旧の実操作が通過。iPhone の実機試験とは区別する。
