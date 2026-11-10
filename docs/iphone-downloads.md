# iPhone から配布ファイルを保存する

[ダウンロードページ](https://plainwalk-web-map.jinmai2000.chatgpt.site/downloads/)をSafariで開き、「iPhone用IPAを保存（未署名）」を押します。Safariのダウンロード一覧、または「ファイル」アプリから保存したファイルを確認できます。確認用サイトは本人限定です。

IPAはSwiftUIのネイティブ版を実機用にビルドしたファイルです。**未署名のため、保存しただけではインストールできません。** インストールには有効な署名・プロビジョニングなど、Appleの配布条件を満たす準備が別途必要です。署名済みIPA・TestFlight・iPhone実機での起動成功を示すものではありません。現在iPhone単体で使えるのは、同ページから開けるWeb版です。

Swift Playgrounds用ZIPはiPad / Mac向けです。iPhoneへ直接インストールするものではありません。

## 実機用IPAの検証

[Package unsigned iPhone device app 42786525618](https://github.com/mai-ima/plainWalk/actions/runs/42786525618) が成功しました。ビルド元は `446d109160ef6e1c767b80dfd1949f0fededcb02`。`Release`・`iphoneos`・`arm64`で本体とLive Activity拡張をビルドしています。Simulator用アプリをIPAという名前にしたものではありません。

本体と拡張について、処理済みInfo.plistのiPhoneOS、iPhone対応、lipoのarm64、Mach-OのLC_BUILD_VERSIONのIOSを検証し、配布証明書のAuthorityとprovisioning profileがないことを確認しました。ダウンロード後、Linux側でも実バイナリのヘッダーとロードコマンドを独立に解析し、両方のplatformが2（iOS実機）、最低OS17.0、SDK26.5であることを照合しました。ZIPのCRC・SHA-256・ファイルサイズも一致しています。[検証記録](references/iphone-device-build-2026-11-10.json)を参照してください。

`PlainWalk-iPhone-unsigned.ipa` は2,819,351バイト、SHA-256は `de1bcb9704f37fc065b32c4995ada1c328f38208a282cb42a7ab0a63a42305a1` です。インストール可否はメタデータでも `installableAsDownloaded: false` と明示します。

## ブラウザでの保存確認

ChromiumとLinux WebKitのモバイル表示で、実際のIPA・Playgrounds ZIPをHTTPからダウンロードし、保存した全バイトのサイズ・SHA-256を元ファイルと比較しました。準備中、不正なメタデータ、通信失敗、再確認、320px幅、署名状態の説明も検査しています。物理iPhoneのSafari操作そのものは未検証です。[実ファイルの検査結果](references/iphone-download-qa-2026-11-10.json)に記録しています。

Service Workerは配布ページ・メタデータ・ファイルをアプリ用キャッシュへ入れません。古いメタデータをキャッシュに置いて通信を失敗させても、保存リンクを誤って有効にしないことを確認しました。

## 配置と再ビルド

- `distribution/ios/PlainWalk-iPhone-unsigned.ipa`: 検証済みの実機用未署名ビルド。
- `distribution/playgrounds/PlainWalk.swiftpm.zip`: ソース `931f6121917c97326ce96ca4e3eeac523e9302df` でコンパイルし、生成73ファイルを照合したPlaygroundsパッケージ。
- `web/public/downloads/build.json`: 実ファイルの作成元、署名状態、サイズ、ハッシュ。
- `web/public/downloads/`: 保存用ページと表示ロジック。
- `scripts/package-ios-device.py`: 実機用バイナリの検証とIPAの作成。

通常の `npm run build` はファイルとメタデータのハッシュを照合して `dist/downloads/` へコピーします。GitHubからの通常ビルドでも保存リンクを再現できます。NativeとPlaygroundsの資源は `node scripts/build.mjs --native` で作り、配布物を含めません。次のIPAやZIPが前のIPA・ZIPを内部へ取り込み、再帰的に大きくなるのを防ぎます。Webページの新しいダウンロード案内は、過去にコンパイル済みのPlaygrounds内資源へ後付けしていません。

Vercelへの接続は行っていません。
