<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <b>日本語</b>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  ⌘を2回。囲んで、おしまい。<br>
  スクリーンショット、画面収録、テキスト認識。何ひとつ、Macの外へ出ません。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg"><b>ダウンロード</b></a> ·
  <a href="https://chengffei.github.io/clip/">ウェブサイト</a> ·
  <a href="#ソースからビルド">ソースからビルド</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="選択範囲とツールバーを表示したClipのキャプチャ画面">
</p>

## 何ひとつ、Macの外へ出ない。

**つながるのは、頼んだときだけ。** アップロードなし、アカウントなし、データ収集なし。Clipがネットにつながるのは「Check for Updates…」を選んだときだけです。

**文字は、必ず読み取る。** まずApple Visionが読み取り、止まったり何も見つからなかったりしたら内蔵モデルが引き継ぎます。どちらもMac上で動き、テキストはそのままクリップボードへ。

**2回で始めて、2回で終わる。** ⌘を2回押して開始、もう一度2回押してコピー。

## ほかに必要なものも、すべて。

- **書き込み**：図形、矢印、ペン、モザイク、番号、テキスト。どれもあとから編集できます
- **範囲を録画**：同じ枠のまま、MP4またはGIFで
- **縦に長く**：スクロールしながらつなぎ合わせ、上下の固定バーは一度だけ
- **ピン留めと色の抽出**：キャプチャをすべてのウインドウの上に浮かべ、画面上の色を拾えます
- **ウインドウに吸着**：クリックひとつで枠に。ピクセル単位で、どのディスプレイでも
- **ツールバーは好みのままに**：どのツールもバー、More、非表示に置け、区切り線もどこにでも
- **Macのために**：ネイティブAppKit。Apple シリコンとIntelの両方に対応

## ほかのツールとの違い

Shottrは小さいけれど録画できません。CleanShot Xはいちばん多機能で35ドル。PixPinは無料で多機能ですが、ソースは非公開で127 MB。Clipは無料、オープンソースで、ふだんはオフライン。詳しい比較は[ウェブサイト](https://chengffei.github.io/clip/#compare)で。

## インストール

1. [Clip-0.4.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg)をダウンロードし、Clipを「アプリケーション」にドラッグします。
2. Clipは署名済みですがAppleの公証を受けていないため、初回起動時にmacOSにブロックされます。一度開いて警告を閉じたあと、「システム設定 › プライバシーとセキュリティ」で「このまま開く」をクリックしてください。または「ターミナル」で次のコマンドを一度実行すれば、そのまま開けます。

   ```sh
   xattr -dr com.apple.quarantine /Applications/Clip.app
   ```
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

内蔵のテキスト認識モデルは、[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)のPP-OCRv6 small（Apache-2.0）をCore MLに変換したものです。詳しくは `Resources/OCRModels/NOTICE` をご覧ください。

## ライセンス

[MIT](LICENSE)
