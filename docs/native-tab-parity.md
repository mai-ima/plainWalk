# iPhone の固定タブバー

更新日: 2026-11-01。

提供された iPhone 画像では、下部タブが画面の幅いっぱいの白い領域に並びます。iOS 26 の標準 TabView の浮いた外観とは異なるため、iPhone では SwiftUI の Button・SF Symbols と VStack を使い、既存の TabView と NavigationStack の選択・履歴を維持したまま固定フッターを表示します。iPad / Mac の標準タブ表示は維持します。

タップ領域は最低 49 pt、ラベルは Dynamic Type の caption2、選択中の項目には accessibility の selected trait を付けます。埋め込みの設定には追加バーを付けず、独立して提示する設定だけ共通部品を利用します。システム背景色に追従します。これらは実装上の選択で、元画像から全寸法を確定したものではありません。

[Apple の toolbar 資料](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:))に基づき、各 NavigationStack でシステムの tabBar を非表示にします。[UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility) は一時的な互換指定で、iOS 27 以降を対象にビルドすると無視されるため使用しません。

初回の撮影で、TabView の外に safeAreaInset を付けるだけでは地図の下部操作がフッターの下に隠れることを確認しました。VStack で TabView とフッターに別々の高さを割り当てるよう修正しています。また、「ここいいな」の一覧で、写真の aspect-fill が列幅の計算に流入し、写真と説明が左端に切れていました。旧画像でも同じ症状を確認し、列幅を受け取る固定高の領域に写真を重ね、描画をクリップする構造へ修正しました。

固定バーと写真一覧の修正は [CI 41307487157](https://github.com/mai-ima/plainWalk/actions/runs/41307487157) の全11ジョブと86枚の撮影で確認しました。その後の地図計算・カメラ等の追加差分は39 Swiftファイルの構文・参照整合性まで確認し、別CIのApple SDK実行待ちです。実機の VoiceOver、最大文字サイズ、キーボード表示時の配置は未確認です。標準のタブ専用アクセシビリティ要素と同一とはしていません。

公式サイトと公式 note の基本・旅行・開拓の説明を再確認しました。全画面・全状態を確認できる操作動画は見つかっていません。公開情報や APK の構造だけで本家の全内部仕様が確定したとはしません。未対応部分は [再現対応表](reproduction-audit.md) に残します。
