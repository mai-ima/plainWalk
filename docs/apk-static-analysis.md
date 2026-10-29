# Android APK の静的解析と iOS への適用

確認日: 2026-10-29。実際に取得した XAPK と、その中の base / split APK を読み取った。インストール・実行、ライセンス制御の回避、バイナリや逆コンパイルしたコードの転載は行っていない。内部構成の分析と、Swift による独立実装を区別する。

## 取得物

- 配布ページ: [APKPure の PlainWalk 1.1.0](https://apkpure.net/plainwalk-draw-your-own-map/com.kanta.plainwalk/download)
- パッケージ: `com.kanta.plainwalk`、versionName `1.1.0`、versionCode `4`。
- XAPK は 16,955,113 bytes。SHA-256 は `d312e1d16f99a6fb280b4b736803c5fe9993e5ebcfb00abbeb4f2dbe4a57ae1e`。配布ページの掲載値と一致。
- base APK と arm64 / 英語 / mdpi の split APK、コンテナの manifest とアイコンが入っている。
- base APK の binary AndroidManifest.xml でも min SDK 29、target SDK 36、版とパッケージ名を確認。
- APK v2 / v3 の署名ブロックを確認。base と split から読み取った証明書の SHA-1 は `1363454100089df700824ff9c117ce9bd46d8506` で掲載値と一致。Google Play から直接取得した正本との比較や、Android 上での署名検証はしていない。

機械で確認した要約: [references/android-apk.json](references/android-apk.json)。APK 自体や署名付きダウンロード URL は公開リポジトリへ入れない。

## バイナリから確認できた構造

base の DEX は 1 個、定義クラスは 9,692。アプリのパッケージに属するクラスは 80。ライブラリを含む数なので、画面数や機能数として数えない。

| 確認した構造 | 読み取れること | iOS 側での扱い |
|---|---|---|
| `WalkRecorderService` と foreground location 権限 | Android の位置記録サービスがある | Core Location の記録・中断・復旧で独立実装 |
| Activity / Movement / Place の receiver | 移動・場所の検知に関係する入口がある | 自動開始の判定条件が分かったとはしない。未接続の操作を有効に見せない |
| Boot / Reminder の receiver | 起動後や予定通知に関する入口がある | iOS の権限と実行条件に合わせて通知を構成する |
| Health Connect のクラスと読取権限 | 歩数・運動・ルートの読み取りに関係する | Xcode 版の HealthKit と分ける。Playgrounds 版では利用可能としない |
| Glance の widget と start / stats receiver | Android のウィジェットがある | iOS の通常ウィジェットは別ターゲットが必要。Live Activity と混同しない |
| Compose / Maps / Camera / ML Kit に関する構成 | Android の UI・地図・撮影・画像処理に使うライブラリを含む | SwiftUI / MapKit / Vision の実装と対照する |
| TrackSession / TrackPoint / ModeSpan 等の型 | 記録点・セッション・移動区間などのモデルを分けている | 独自の保存形式・連番・切断点を維持する |

メンバー名には難読化があり、クラスや権限の存在だけでは、内部の判定閾値、完全な画面構成、使える機能、元のソースを復元できない。例えば旗・しおりに関係する型はあるが、[公式 Android 案内](https://plainwalk.app/android)では、これらは現在 iPhone 専用として案内されている。型名から実装済みの画面を想像しない。

## 権限のまとまり

実体の manifest には、正確・概算・背景位置、位置 foreground service、モーション、カメラ・マイク、通知・再起動、wake lock、Health Connect の読み取り、通信、課金・ライセンスの権限がある。実装に取り込むのは、ユーザーが求めた機能に必要な権限だけ。課金・広告はこの独立版には追加しない。

## App Store 以外の画像

[AppBrain の公開掲載](https://www.appbrain.com/app/plainwalk-draw-your-own-map/com.kanta.plainwalk)から、Google Play 由来の紹介画像 1 枚と Android の画面を含む画像 7 枚を取得して目視確認した。出典・ハッシュ・サイズは [references/android-images.json](references/android-images.json)。重複した iOS の転載を追加画面に数えていない。

Android は、歩行アイコン、閉じるボタン、単位・時刻、通知、共有カードの選択肢が iOS と異なる。これらをそのまま iOS の正解にはしない。iOS の余白・下部タブ・設定のグループ・SF Symbols は提供された iOS 実画面を優先する。

## 今回の iOS 実装

設定と実機検証は SwiftUI の画面として追加した。設定の外観・単位・beta・開発者モードは既存の保存と画面に接続し、ファイル選択・通知・HealthKit の入口を接続する。未実装の自動開始等は理由を表示する。

マイマップや多くのコレクションは引き続き同梱 Web UI。全画面の SwiftUI 化、元アプリとのピクセル一致、背景 GPS の実機比較、元アプリの内部アルゴリズムとの一致は未達。APK を調べたことを、iOS 版の完全再現が完了した根拠にはしない。
