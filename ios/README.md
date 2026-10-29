# iOS プロジェクト（iOS 17 以降）

通常の起動先は `NativeRootView` です。SwiftUI のタブ・ナビゲーション・シート、Canvas の白地図、MapKit の答え合わせ地図を使います。Web ページをそのまま表示する起動構成から変更しました。PlainWalk の公開画面と機能を基にした独立実装で、元アプリのソースや署名済みアプリではありません。

**今回追加した SwiftUI 構成は macOS で検証中で、コンパイル・Simulator 試験の成功は未確認です。実機・配布署名も未検証で、署名済み IPA はありません。** [以前の CI 成功](https://github.com/mai-ima/plainWalk/actions/runs/40888890524) は旧 WebView 構成の検証履歴です。

## Mac で開く

1. リポジトリ全体を Mac に展開し、`npm ci` と `npm run build` を実行します。
2. `ios/PlainWalk.xcodeproj` を Xcode 16 以降で開き、`PlainWalk` スキームを選びます。
3. Signing & Capabilities で自分の Team と一意の Bundle Identifier を設定します。アプリと Live Activity 拡張の両方を変更してください。
4. 実機にインストールし、記録開始時に位置情報、必要な機能を使うときにモーション・カメラ・HealthKit 等を許可します。

`npm run build` は日本の境界 GeoJSON も展開します。ビルド時に `dist/` をアプリの `Web/` にコピーするため、`ios/` と `dist/` の相対位置を保ってください。SwiftUI のバッジはここから実際の境界データを読みます。ローカルの白地図・記録・保存は Web サーバーを必要とせず、MapKit の地図・場所検索には通信が必要です。

プロジェクトを再生成する場合は `python3 ios/generate_project.py` を実行します。署名情報を持たない生成スクリプトなので、手動の署名設定を残したい場合は先に退避してください。

## 画面と機能の配置

| ファイル | 担当 |
|---|---|
| `NativeRootView.swift` | 標準タブ、NavigationStack、シート、ファイル取り込み |
| `NativeMyMapView.swift` | Canvas、パン・拡大縮小、軌跡・写真ピン・現在地、記録ボタン |
| `NativeAnswerMapView.swift` | MapKit、標準・航空写真・3D、場所検索、旗・しおり |
| `NativeRecordsView.swift`, `NativeProfileView.swift` | 履歴、カレンダー、詳細、プロフィール |
| `NativeCollectionsView.swift` | 写真、Vision ステッカー、実境界バッジ、らくがき、共有、ノート |
| `NativeLayerView.swift`, `NativeSettingsView.swift` | 配色、表示、設定、OS 機能への入口 |
| `NativePhotoCaptureView.swift` | PhotosPicker、ネイティブカメラ、短い動画 |
| `NativeAppModel.swift`, `NativeModels.swift`, `NativeStore.swift` | 状態、既存 JSON との互換、検証、atomic な保存 |
| `NativeTrackMath.swift`, `NativeTrackIO.swift`, `NativeDoodleProgress.swift` | 距離・開拓、GPX / TCX、歩いたらくがきの更新 |
| `NativeUtilityViews.swift` | メニュー、統計、軌跡の再生、HealthKit の取り込み |

`PlainWalkApp.swift` 内の `LocalWebApp` と `NativeBridge.swift` は互換コードとして残ります。通常起動の白地図・記録・プロフィールを表示するためには使いません。ネイティブとブラウザは同じ保存キー・バックアップ形式を利用しますが、端末間やアプリとブラウザの保存領域は自動同期されません。

SwiftUI 版には LUT / フィルム、手動の軌跡修正、軌跡の動画書き出しがまだありません。これらは Web 版の機能です。ネイティブのノートは文章・紙・書体、スライダーでの配置調整と PNG 出力に対応し、写真・道・ステッカーの既存配置や未知の追加項目を保持します。キャンバス上の直接ドラッグ編集は Web 版との操作差です。[対応表](../docs/reproduction-audit.md)も参照してください。

## 端末 API

- `LocationRecorder.swift`: Core Location。Xcode 版は記録中に背景更新を使用し、精度・揺れ・速度・時間の欠損を判定します。位置は連番付きの追記ジャーナルへ保存します。
- `MotionService.swift`, `HealthService.swift`: モーション歩数、許可した HealthKit の歩数・ワークアウト・ルート。HealthKit は読み取りのみです。未許可とデータなしを区別できない項目があります。
- `LiveActivityService.swift`, `PlainWalkLive/`: ActivityKit / Dynamic Island。通常のホーム画面ウィジェットとは別です。
- `CutoutService.swift`: Vision による被写体の切り抜き。画像の内容によって切り抜けない場合があります。
- `NativeDeveloperView.swift`, `DiagnosticService.swift`: 権限・保存・ジャーナル復旧を確認する隔離された検証操作。自動送信はしません。

## 保存と復旧

Application Support の `PlainWalk/` に、既存と同じ `web-library.json`、`web-config.json`、`web-active.json` を保存します。IndexedDB に依存しません。ファイル保護には初回ロック解除後の背景書き込みに対応する `completeFileProtectionUntilFirstUserAuthentication` を使います。

ネイティブの位置セッションと画面用の保存は分かれています。位置ジャーナルはセッション ID と連番を持ち、不完全な行からの復旧や重複の排除を行います。記録中の全経路を位置更新ごとに書き直す方式は避けています。保存データを読み取れない場合は元のファイルを保護し、バックアップからの復元を案内します。

OS 終了・アプリ再起動後は記録を自動で再開せず、復旧した状態を確認します。強制終了・再起動・権限変更・低容量時の動作は実機での確認が必要です。

JSON バックアップと GPX は標準共有シートから Files / iCloud Drive / AirDrop 等へ渡せます。共有の白地図は選んだ線だけのファイル交換で、日時・写真・メモを除きます。招待リンク、共同編集、自動同期、独自の近接交換は未実装です。

## 実機で確認すること

[実機検証の手順](../docs/device-testing.md)に沿って、背景 GPS、一時停止・復旧、低容量、HealthKit、Live Activity、MapKit、写真・動画・ファイル、VoiceOver・文字サイズ・セーフエリアを確認してください。Playgrounds の前面記録と、Xcode 版の背景記録を分けて記録します。

Watch アプリ、通常のホーム画面ウィジェット、ジオフェンス等の自動開始、iCloud 自動同期は未実装です。公式の細かな演出や内部判定の一致も未確認です。
