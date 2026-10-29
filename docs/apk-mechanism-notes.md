# Android 記録機構の静的メタデータ照合

確認日: 2026-10-29。対象は Android **1.1.0 / versionCode 4**。提供された iOS 画面の版と同じ実装・機能とは扱わない。バイナリは実行していない。

## 出典と対象の同定

- 配布ページ: [APKPure / PlainWalk](https://apkpure.net/plainwalk-draw-your-own-map/com.kanta.plainwalk/download)
- 公式の比較先: [PlainWalk](https://plainwalk.app/) / [Android 案内](https://plainwalk.app/android)
- XAPK: `plainwalk-1.1.0.xapk`、16,955,113 bytes。
- XAPK SHA-256: `d312e1d16f99a6fb280b4b736803c5fe9993e5ebcfb00abbeb4f2dbe4a57ae1e`
- コンテナ内 base: `com.kanta.plainwalk.apk`、16,500,038 bytes。
- base SHA-256: `e67ff4630b07b389e544d4a8f25f162c2b05baf2bf276676026e2478394461d2`
- package: `com.kanta.plainwalk`。base の `classes.dex` と binary manifest を対象とした。全体の構成は [既存の解析](apk-static-analysis.md) / [機械可読の要約](references/android-apk.json)を参照。

Androguard でクラス、フィールドの型、メソッドの宣言、呼出先参照、シリアライザーの項目名を読んだ。今回の重点範囲は `walk` パッケージ、記録のデータ型、位置コールバックのアダプターであり、アプリ全体の制御フローを復元したものではない。逆コンパイルしたソース、命令列、秘密情報、元アプリの画像・音声・実行ファイルはこの文書や実装へ転載していない。

## 確認できた機構と、その限界

| 項目 | 静的に確認できた参照 | ここからは確定できないこと |
|---|---|---|
| 記録の開始入口 | `WalkRecorderService` は Android `Service` を継承。`onStartCommand` は `Intent.getAction` / `getStringExtra`、状態管理、通知、サービス内の開始処理を参照する。別メソッドに `startForeground` がある | すべての action の意味、ユーザー操作との完全な対応、自動再開・失敗時の全分岐 |
| 位置・センサーの開始 | Google Play services の `LocationRequest` の構築とクライアント呼出し、`SensorManager.registerListener`、`PendingIntent`、`PowerManager.WakeLock.acquire` を参照 | 実機で採用される精度・周期、OS の省電力制限下での挙動、電池消費。要求値を実測値とは扱わない |
| 停止・終了 | 停止用メソッドに location クライアント側の解除呼出し、`unregisterListener`、`Handler.removeCallbacks`、`WakeLock.isHeld/release` がある。`onDestroy` からこの停止処理を呼ぶ | 強制終了・プロセス停止でも必ず `onDestroy` が実行されるという保証、停止後の復旧の完全な条件 |
| 位置入力 | アダプターは Android `Location` の緯度・経度・時刻・精度・速度・方位と `hasAccuracy/hasSpeed/hasBearing` を参照し、型付きの値を状態管理側へ渡す | 精度・速度の棄却閾値、古い位置の採否、位置欠損の許容時間、平滑化・補間の計算式 |
| 方向・歩数等のセンサー入力 | サービスは `onSensorChanged` / `onAccuracyChanged` を持ち、センサー種別、回転ベクトルからの行列変換、時刻差、状態・セッション更新を参照する | 各センサーの必須性や最終的な歩数集計式。センサー処理の存在だけでは Health Connect 由来の歩数と同じものとは言えない |
| 動作認識 | `ActivityReceiver.onReceive` と `MovementReceiver.onReceive` は `ActivityRecognitionResult` を参照する。前者は時刻と分類を持つ `MotionMark`、後者は `AutoRecord.Transition` の生成を参照する | 歩行・走行・乗物の信頼度閾値、分類の持続時間、開始停止の条件、GPS と動作認識の優先順位 |
| 場所による入口 | `PlaceReceiver` と `TriggerPlace` があり、位置精度・座標と時刻の参照がある | すべての場所監視条件、境界付近の扱い、権限を失った際の挙動 |
| 保存 | 保存管理には `PersistedData` の Kotlin serialization、文字列のファイル読書き、ディレクトリ作成、`Files.move` がある。状態管理側には `Files.copy` と保存済みデータの読込みもある | 移動が常に原子的であること、fsync の保証、保存頻度、停電・容量不足時のデータ保証。`Files.move` の存在だけからジャーナル方式とは言えない |

難読化された名前には、本来の関数名を推測して付け直していない。上表の「開始」「停止」は関連する API の参照のまとまりを説明しており、元の関数名や全分岐を再構成したものではない。

## データ型から分かった分離

- `TrackPoint` のシリアライズ項目に座標・時刻と **`leg`（整数）・`edited`（Boolean）** がある。Boolean を「GPS 欠損」や `gap` と読み替える根拠はない。`leg` の存在から切断判定の閾値までは決められない。
- `TrackSession` は識別子、開始・終了、点列、距離・開拓距離・歩数に加え、動作履歴、分ごとの歩数、移動手段区間、分類元、鉄道関連の別項目を持つ。項目名の存在は、すべてが通常操作で有効になることを意味しない。
- `MotionMark` は時刻と分類文字列、`ModeSpan` は開始時刻・終了時刻と分類文字列の型を持つ。GPS の点と動作イベント・移動区間を分離したモデルであることは確認できる。
- 状態管理クラスには `ModeSpan` の生成とセッションの更新を参照するメソッドがある。ただし、最終分類を生成する全アルゴリズムやユーザー修正との優先関係は未確定。

この範囲では、欠損 GPS を直線で接続するか、区間を分けるか、どの時間・精度で切るかを完全には確定できなかった。Android の内部閾値を発見・移植したとはしない。

## 現在の独立実装との対応・具体的な残差

| 観点 | このリポジトリの iOS / Web | Android のメタデータとの残差 |
|---|---|---|
| 画面から独立した記録 | [LocationRecorder](../ios/PlainWalk/LocationRecorder.swift) が Core Location と保存を担当し、[NativeAppModel](../ios/PlainWalk/NativeAppModel.swift) が画面状態を管理 | OS 固有の foreground service と iOS の background location は別機構。Android の wake lock を iOS へ置き換えたものではない |
| 保存と復旧 | ネイティブは checkpoint と追記 journal、連番・時刻での重複排除、paused 復旧、保存失敗時の停止を独立実装。Web の進行中記録を native checkpoint へ移行する API もある | Android が同じジャーナル・復旧形式を使うことは未確認。元アプリの保存ファイルとの互換性を提供しない |
| 欠損・再開 | native の `gap`、共通モデルの `isBreak` で区間を分け、距離・描画・書出しで切断を維持。開始前・再開前のキャッシュ位置と不正な位置を除外する | Android の整数 `leg` と直接対応する形式ではない。現在の時間・速度・精度の条件はこの独立版の設計であり、本家の条件ではない |
| 速度・方向 | native は点間距離と時間から異常な移動を判定。方位は Core Location の heading 更新から取得する | Android の入力には `Location` 自体の速度・方位もある。入力経路・保持する生の情報は一致しない |
| 動作の分類 | [MotionService](../ios/PlainWalk/MotionService.swift) の Core Motion 結果を点の `mode` に記録。移動手段表示の設定と連動する | `MotionMark` と `ModeSpan` の別履歴、分類元、分ごとの歩数、鉄道判定・判定規則を同じ形では保持していない。これらの後処理の完全再現は未達 |
| 自動開始 | 現在は明示的な記録開始・一時停止・再開が中心 | Android の Activity / Movement / Place receiver に相当する自動開始の全経路は実装していない。設定だけで利用可能に見せない |
| 開拓距離 | [NativeTrackMath](../ios/PlainWalk/NativeTrackMath.swift) / [Web core](../web/src/core.js) は公式の公開説明を参考にした 12m グリッド近似を独立実装 | この DEX メタデータ照合では Android のグリッド計算式・補正処理との一致を検証していない |

今後、実機で「開始直後のキャッシュ位置」「権限変更」「長い位置欠損」「画面ロック後の継続」「歩行から乗物への移行」を比較すると差分を狭められる。今回の静的解析と Simulator 検証だけでは、本家との実機挙動・背景記録・分類精度の一致は証明できない。
