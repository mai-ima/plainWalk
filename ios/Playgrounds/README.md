# Swift Playgrounds 用アプリ

iPad / Mac の Swift Playgrounds で開く `.swiftpm` 形式です。iOS / iPadOS 17 以降を対象にします。通常の iPhone 実機インストールや HealthKit / Live Activities は `ios/PlainWalk.xcodeproj` を使ってください。

## 開き方

1. 配布 ZIP `PlainWalk.swiftpm.zip` を iPad の「ファイル」で展開します。
2. `PlainWalk.swiftpm` を Swift Playgrounds で開きます。
3. 実行ボタンを押し、記録開始時に位置情報・必要なときだけモーションやカメラを許可します。

iPhone には Swift Playgrounds アプリがありません。iPad / Mac で編集し、iPhone 向けの実機ビルドは Xcode 版から行ってください。

## リポジトリから生成する

```sh
npm ci
npm run playgrounds
```

`ios/Playgrounds/PlainWalk.swiftpm/Sources/` と `artifacts/packages/PlainWalk.swiftpm.zip` を生成します。Swift の正本は `ios/PlainWalk/`、画面の正本は `web/` にあります。生成物の編集は再生成で上書きされるため、正本側を変更してください。生成済みの ZIP は単独で開け、Node.js や Web サーバーを必要としません。

## 利用範囲

Web と同じ白地図・履歴・コレクション、端末内ファイル保存、前面での Core Location 記録、モーション歩数、MapKit、Vision 切り抜き、ファイルの入出力を同梱します。答え合わせ以外の保存済みデータは端末内で扱います。

Playgrounds 版は前面で記録する構成です。HealthKit、Live Activity 拡張、Apple Watch、ロック中の継続 GPS を利用できる版としては扱いません。HealthKit 操作には利用範囲の説明を返します。iPad 実機での権限・GPS 精度・カメラと Mac の Playgrounds 実行は未検証です。

権限とアプリ設定の根拠: [Apple: app playground capabilities](https://developer.apple.com/documentation/swift-playgrounds/project-capabilities)、[Apple: iPad でファイル・画像を追加](https://support.apple.com/guide/playgrounds-ipad/add-swift-files-images-and-swift-packages-itc18b7bce9d/ipados)。

## 検証

GitHub Actions 40898218214 の `playgrounds` ジョブで `.swiftpm` のアプリを iOS Simulator 向けにコンパイルしました。iPad / Mac の Swift Playgrounds 上の実行試験とは区別します。

設定と実機診断の SwiftUI 画面も、同じ正本から生成して同梱します。HealthKit の操作には Playgrounds の利用範囲を説明します。通知やメディア・モーションの権限は端末で個別に確認してください。
