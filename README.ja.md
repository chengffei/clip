<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <b>日本語</b>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  ⌘を2回。囲んで、おしまい。<br>
  スクリーンショット、画面収録、テキスト認識を、メニューバーから。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.3.0.dmg"><b>ダウンロード</b></a> ·
  <a href="https://chengffei.github.io/clip/">ウェブサイト</a> ·
  <a href="#ソースからビルド">ソースからビルド</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="選択範囲とツールバーを表示したClipのキャプチャ画面">
</p>

## あえて、少なく。

スクリーンショットツールには、クラウド同期やチーム機能、サブスクリプションが次々と加わっています。Clipがするのは、撮る、録る、文字を読み取るの3つだけ。アカウントは不要。データの収集もしません。すべてがあなたのMacの中で完結します。

## 機能

**ワンタップでキャプチャ。** どこからでも⌘を2回押すだけ。ウインドウの端にぴたりと吸着し、選択はピクセル単位で正確。複数のディスプレイでも使えます。

**すぐに書き込める。** 四角形、楕円、矢印、直線、ペン、蛍光ペン、モザイク、番号、テキスト。どの注釈もあとから編集でき、取り消しとやり直しにも対応しています。

**必要な部分だけを録画。** 選択した範囲をMP4またはGIFで収録。小さなコントロールで、一時停止も停止もすぐにできます。

**どんな文字も、コピーできる。** テキスト認識はすべてMac上で行われます。まずApple Visionが読み取り、見つからなかったときは内蔵モデルが引き継ぎます。クリックひとつで、テキストがクリップボードに。

**縦に長いページも。** スクロールキャプチャを始めて、ページをスクロールするだけ。Clipがその場でつなぎ合わせ、上下の固定バーは一度だけ表示されます。

**ピン留め、色の抽出、回転。** キャプチャをすべてのウインドウの上に浮かべたり、画面上の色を拾ったり、ワンクリックで画像を回転したり。

**ツールバーは、あなた好みに。** 左にキャンセル、中央にツール、右に出力。どのツールもツールバー、「More」メニュー、非表示のどこにでも置けて、区切り線も好きな場所に追加できます。

**Macのために。** ネイティブのAppKitで開発。ひとつのアプリでAppleシリコンとIntelの両方に対応します。

## インストール

1. [Clip-0.3.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.3.0.dmg)をダウンロードし、Clipを「アプリケーション」にドラッグします。
2. Clipは署名済みですがAppleの公証を受けていないため、初回起動時にmacOSにブロックされます。一度開いて警告を閉じたあと、「システム設定 › プライバシーとセキュリティ」で「このまま開く」をクリックしてください。
3. 求められる2つのアクセス権を許可します。⌘の2回押しには「アクセシビリティ」、キャプチャには「画面収録」が必要です。

macOS 14以降が必要です。インターフェイスは現在、英語と簡体字中国語のみです。日本語環境では英語で表示されます。

## ショートカット

| 操作 | デフォルト |
|---|---|
| 範囲のスクリーンショット | ⌘を2回 |
| 選択中にクリップボードへコピー | ⌘を2回 |
| 収録、OCR、画像内テキストのコピー、ピン、全画面、カラーピッカー | Settings › Shortcuts で設定 |

エディタの各ツールには1キーのショートカットがあります。たとえばRは四角形、Aは矢印、Tはテキスト。ツールにポインタを合わせると確認できます。

## ソースからビルド

Xcode 26以降が必要です。Command Line Toolsだけでは、アクセス権パネルで使っているSwiftUIマクロをビルドできません。

```sh
bash scripts/rebuild-and-open.sh   # ビルド、署名、/Applicationsにインストールして起動
bash scripts/make-release.sh       # ユニバーサル版 → dist/Clip-<バージョン>.dmg と .zip
swift test                         # 180以上のテスト。CLIP_SNAPSHOT_DIR=ディレクトリ でツールバー、選択範囲、設定画面のPNGも出力
```

トリガーの診断ログは `~/Library/Logs/Clip/clip.log` に書き出されます。`Clip --diagnose` でアクセス権の状態を表示できます（画面収録の状態はFinderから起動したときのみ正確です）。

## クレジット

Clipは、realskyrinによる[capcap](https://github.com/realskyrin/capcap)（MIT）のフォークです。キャプチャエンジン、エディタ、収録パイプラインはcapcapから受け継いでいます。Clipでは名前、アクセス権の流れ、見た目を変え、ひとりでは使わない機能を外しました。クラウドアップロード、翻訳、画像結合、履歴、エージェントCLI、自動アップデート、カウントダウン、QRコード、美化です。

内蔵のテキスト認識モデルは、[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)のPP-OCRv6 small（Apache-2.0）をCore MLに変換したものです。詳しくは `Resources/OCRModels/NOTICE` をご覧ください。

## ライセンス

[MIT](LICENSE)
