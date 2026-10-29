# Swift Playgrounds 用アプリ

iPad / Mac の Swift Playgrounds で開く `.swiftpm` 形式です。iOS / iPadOS 17 以降を対象にし、通常の iOS 版と同じ SwiftUI / Canvas / MapKit の正本から生成します。iPhone への署名・インストール、HealthKit、Live Activity は `ios/PlainWalk.xcodeproj` を使ってください。

## 開き方

1. `PlainWalk.swiftpm.zip` を iPad / Mac の「ファイル」等で展開します。
2. `PlainWalk.swiftpm` を Swift Playgrounds で開きます。
3. 実行し、記録開始時に位置情報、必要な機能を使うときにモーションやカメラを許可します。

iPhone 用の Swift Playgrounds アプリはありません。iPad / Mac で編集し、iPhone 向けの実機ビルドは Xcode 版で行ってください。

## リポジトリから生成する

```sh
npm ci
npm run playgrounds
```

`ios/Playgrounds/PlainWalk.swiftpm/Sources/` と `artifacts/packages/PlainWalk.swiftpm.zip` を生成します。ネイティブ画面と端末処理の正本は `ios/PlainWalk/`、ブラウザ版の正本は `web/`、境界データは `datasets/` です。生成済み Sources を編集しても再生成で上書きされます。

ZIP はコードとリソースを同梱するので、生成後に Node.js や Web サーバーは不要です。白地図の Canvas や SwiftUI の履歴・コレクションが通常の起動先です。同梱 `Web/` の境界 GeoJSON を Swift 側も読みます。MapKit の地図・検索は通信を使います。

## 利用範囲

前面の Core Location 記録、端末内ファイル、モーション歩数、MapKit、PhotosPicker・カメラ、Vision 切り抜き、GPX / TCX・バックアップの入出力を含みます。SwiftUI の機能差分は [iOS README](../README.md) と [対応表](../../docs/reproduction-audit.md)を参照してください。

Playgrounds 版は前面記録用です。生成時に背景位置更新を無効化し、HealthKit と Live Activity のサービスを利用範囲の説明に置き換えます。Apple Watch、ロック中の継続 GPS、HealthKit や Live Activity 拡張を使える版としては扱いません。

権限の根拠: [Apple: app playground capabilities](https://developer.apple.com/documentation/swift-playgrounds/project-capabilities)、[Apple: ファイル・画像を追加](https://support.apple.com/guide/playgrounds-ipad/add-swift-files-images-and-swift-packages-itc18b7bce9d/ipados)。

## 検証

今回の SwiftUI 起動構成を含むパッケージは [GitHub Actions 40922182440](https://github.com/mai-ima/plainWalk/actions/runs/40922182440) の macOS ジョブでコンパイルを通過しました。Simulator の起動・自己テスト・画面確認は同じ正本からビルドした Xcode 版で実施しており、Playgrounds アプリ内での実行試験とは区別します。iPad / Mac の Swift Playgrounds 上での実行、権限、GPS 精度、カメラは未検証です。

実機検証の画面は同じ正本から生成されます。検証結果は [手順](../../docs/device-testing.md)に従って記録し、Xcode / Simulator の結果と区別してください。
