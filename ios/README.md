# iOS プロジェクト（iOS 17 以降）

Web と同じ画面を WKWebView で表示し、端末 API を Swift から接続する構成です。元の PlainWalk のソースや署名済みアプリではありません。公開されている機能・画面を基にした独立実装です。

**この Linux 環境には Xcode と Apple SDK がありません。プロジェクトは生成済みですが、Swift のコンパイル・シミュレーター・実機・署名は未検証です。IPA は作成していません。**

## Mac で開く

1. リポジトリ全体を Mac に展開します。`ios/` と `dist/` の相対位置を保ってください。
2. `ios/PlainWalk.xcodeproj` を Xcode 16 以降で開き、`PlainWalk` スキームを選びます。
3. Signing & Capabilities で自分の Team と一意の Bundle Identifier を設定します。アプリと Live Activity 拡張の両方を変更してください。
4. 実機で位置情報を許可し、必要な場合だけヘルスケアの読み取りを許可します。

プロジェクトを再生成するときは `python3 ios/generate_project.py` を実行します。生成スクリプトは署名情報を持ちません。手動で編集した署名設定を保存したい場合は再生成前に退避してください。

ビルド時、`dist/` をアプリの `Web/` にコピーします。リモートサイトを読み込むラッパーではなく、画面とロジックをアプリ内に同梱します。答え合わせ以外は通信を必要としません。

## 接続したコード

- `LocationRecorder.swift`: 記録中だけ Core Location の background updates を有効化。3 m フィルタ、GPS 精度・速度チェック。位置更新ごとに atomic なファイル書き込み。画面側が止まっていても保持し、復帰時に seq で重複を避けて同期。
- `NativeBridge.swift`: 自分のローカルメインフレームだけからのメッセージを受付。Web の状態を protected Application Support ファイルへ保存。共有シート、ファイル選択、ネイティブ地図へ接続。
- `HealthService.swift`: 明示操作で歩数・最近 200 件までの歩行／ラン／ハイク／自転車ワークアウトと許可されたルートを読む。書き込みはしない。未許可とデータなしを区別できない点を UI に表示。
- `LiveActivityService.swift` と `PlainWalkLive`: 距離と記録状態の ActivityKit / Dynamic Island 表示。通知サーバーは使わない。
- `NativeMapController.swift`: MapKit の建物、立体表示、航空写真と分割した軌跡。

## 保存と復旧

iOS 側は IndexedDB に依存せず、Web 状態も Application Support に保存します。ファイル保護は初回ロック解除後の background 書き込みに対応する `completeFileProtectionUntilFirstUserAuthentication` です。ネイティブの位置セッションと Web 状態は別々に保持し、終了前に同期します。

OS にプロセスを終了された後は自動的に記録を再開せず、復旧確認を出します。強制終了後の継続記録、端末再起動後、位置情報の権限変更時の動作を実機で検証する必要があります。

「バックアップを書き出す」で共有シートを開き、「ファイルに保存」から iCloud Drive をユーザーが選べます。直接の iCloud 自動同期ではありません。

## 実機で必要な検証

- カスタム URL scheme で ES modules と画像／動画の再生が動くこと
- 位置情報の拒否・許可・概算位置・権限取消時の表示
- ロック状態で 15 分以上歩き、native の記録点と復帰後の白地図が一致すること
- 一時停止／再開／終了、OS によるプロセス終了、空き容量不足
- HealthKit の許可／拒否、Apple Watch 起源の歩数、位置のないワークアウト
- Live Activity の作成・更新・停止、Dynamic Island、古い Activity の復旧
- MapKit の軌跡・分割点・建物・航空写真、ネットワーク切断
- 写真／動画の権限、共有シート、ファイルの取り込みと iCloud Drive への保存
- VoiceOver、文字サイズ、ダークモード、縦横画面、セーフエリア

Apple Watch アプリ、通常のホーム画面ウィジェット、ジオフェンスによる自動開始、共有白地図、写真切り抜きステッカー、自治体の境界データは未実装です。
