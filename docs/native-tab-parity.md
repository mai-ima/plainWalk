# iPhone の固定タブバー

更新日: 2026-11-01。

提供された iPhone 画像では、下部タブが画面の幅いっぱいの白い領域に並びます。iOS 26 の標準 TabView の浮いた外観とは異なるため、iPhone では SwiftUI の Button・SF Symbols と safeAreaInset を使い、既存の TabView と NavigationStack の選択・履歴を維持したまま固定フッターを表示します。iPad / Mac の標準タブ表示は維持します。

タップ領域は最低 49 pt、ラベルは Dynamic Type の caption2、選択中の項目には accessibility の selected trait を付けます。埋め込みの設定には追加バーを付けず、独立して提示する設定だけ共通部品を利用します。システム背景色に追従します。これらは実装上の選択で、元画像から全寸法を確定したものではありません。

[Apple の toolbar 資料](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:))に基づき、各 NavigationStack でシステムの tabBar を非表示にします。[UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility) は一時的な互換指定で、iOS 27 以降を対象にビルドすると無視されるため使用しません。

この変更のローカル確認は 38 Swift ファイルの構文解析と Xcode プロジェクトの参照整合性です。Apple SDK ビルド、実際の撮影画像、プロフィールからの遷移後の重複は別途 CI で確認します。実機の VoiceOver、最大文字サイズ、キーボード表示時の配置は未確認です。標準のタブ専用アクセシビリティ要素と同一とはしていません。

公式サイトと公式 note の基本・旅行・開拓の説明を再確認しました。全画面・全状態を確認できる操作動画は見つかっていません。公開情報や APK の構造だけで本家の全内部仕様が確定したとはしません。未対応部分は [再現対応表](reproduction-audit.md) に残します。
