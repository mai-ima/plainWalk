# PlainWalk Web + iOS project

公式の画面・機能説明を調査した非公式の独立実装です。**完全再現は未達です。** 課金・広告なし、beta の設定を引き継いでいます。

- Web: `dist/` を HTTPS 配信する静的 PWA。iPhone の Safari / ホーム画面を想定。
- iOS: `ios/PlainWalk.xcodeproj`。同じ UI を同梱し、Swift から端末 API を接続。
- 調査結果と残差: [docs/reproduction-audit.md](docs/reproduction-audit.md)
- iOS 起動・署名・未検証事項: [ios/README.md](ios/README.md)

## Web の起動

Node 24 / Python 3。ランタイムの npm 依存ライブラリはありません。

```
npm start
```

http://localhost:4173 を開きます。実端末の位置情報・カメラ・PWA は HTTPS が必要です。

## Web で実装した機能

白地図、GPS 記録、一時停止と長押し終了、中断復旧、12 m セルの開拓距離の近似計算、頻度による線の変化、履歴とカレンダー、統計、手動歩数、写真ピン、1〜2 秒の動画ピンと対応環境での撮影、複数の旗・順序・方角、テキストノートと絵文字ステッカー、PNG カード、GPX / TCX の入出力、JSON バックアップ、軌跡と全記録の再生、対応環境での再生動画出力、軌跡のドラッグ修正・削除・分割・Undo、カスタム 3D .cube LUT の読み込み。

配色は公式 Web サイトの標準＋14 色の paper / ink 公開値に更新しました。線・ピン・相棒のカスタマイズは無料です。相棒はプロフィールの絵文字表示で、公式の猫のアニメーションを再現していません。

beta 設定: GPS 精度円、画面スリープ防止、全 GPX の書き出し、診断、実データと分離した体験モード。

## iOS 側に追加したコード

Core Location の背景記録、位置更新ごとの atomic ファイル保存、復帰時の重複を避けた同期、HealthKit の歩数・ワークアウトとルート、ActivityKit と Dynamic Island の拡張ターゲット、MapKit の建物・立体・航空写真、Files と共有シート。Web 状態も保護された端末内ファイルに保存し、独自 URL scheme の IndexedDB には依存しません。

**GitHub の macOS / Xcode CI で iOS 本体と Live Activity 拡張のビルドが通過しました。実機の権限・背景 GPS と配布署名は未検証です。署名済み IPA はありません。**

## 検証

```
npm test
npm run check
python3 ios/validate_project.py
```

9 件の計算・バックアップ・LUT テストと JS 構文検査が通過。モバイルサイズの Chromium で以下を検証しました。

- `tests/browser.cjs`: GPS 記録、履歴の保存、再読み込み後の永続化、beta
- `tests/features.cjs`: GPX、旗、写真、ノート、バックアップ、地図切替、オフライン復元
- `tests/advanced.cjs`: 軌跡のドラッグ修正、2 秒の動画ピン、再生動画の実ファイル出力。ffprobe でも約 6 秒の MP4 を確認
- `tests/native-bridge.cjs`: 模擬ネイティブアダプターとの通信・記録・一時停止・保存・歩数応答。Swift や iOS の実行試験ではありません

ブラウザ試験スクリプトの Playwright モジュールと出力パスはこの実行環境を前提にしています。ほかの環境ではパスを変更してください。Linux WebKit でも GPX 取り込み、実境界のエリアバッジ、ノートへの道の配置、保存と再読み込みが通過。iPhone 実機の Safari 試験は未完了です。

## 制約と未対応

Web の画面ロック中の GPS や HealthKit はネイティブと同じにはできません。同梱の iOS ソースをビルド・インストールしない限り、ネイティブ機能は利用できません。

自治体の輪郭・立体バッジ、道路への自動スナップ、共有の白地図、切り抜きステッカーと交換、公式の猫のアニメーション、通常のウィジェット、Apple Watch アプリ、自宅からの自動開始、動画へのフィルムと再生中の動画ピン合成は未実装。ノートも公式の自由レイアウトを完全には再現していません。開拓レベル名・計算・描画の内部仕様は公式と一致する保証がありません。

端末のデータ消去・アプリ削除・容量不足に備えてバックアップが必要です。JSON の取り込みは 45 MB、動画ピンは 15 MB / 2.6 秒以内、写真は読み込み後に圧縮します。大きくなったメディアは個別にも書き出してください。バックアップには外観設定は含みません。

## 継続版の追加

日本全国 1,905 区域のエリアバッジ、写真・道・切り抜きステッカーの自由配置ノート、紙・書体・箔・ホログラム、Vision 自動切り抜きの iOS コードを追加。前の未対応一覧のうち、国内のエリア判定とノート配置は実装済みです。

Vercel ではリポジトリ全体を Import し、Root Directory はルートのままにしてください。vercel.json が npm run build と dist 出力を指定します。圧縮した境界データをビルド時に展開するため、先に npm run build を実行してから Xcode で開いてください。

確定した要件は [docs/requirements.md](docs/requirements.md) を参照。

## ビルド検証の記録

iOS コンパイル通過: https://github.com/mai-ima/plainWalk/actions/runs/40884105110 。次の CI では iPhone Simulator 起動と、Web 画面の読み込み・ネイティブストレージ接続・位置ジャーナルの復旧を検証します。Vercel への接続はユーザー指示により行わず、GitHub からの手動 Import に対応します。
