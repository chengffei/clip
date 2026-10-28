<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <b>繁體中文</b> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  連按兩下 ⌘，框一下，就好。<br>
  截圖、螢幕錄影、文字辨識，都在選單列裡。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg"><b>下載</b></a> ·
  <a href="https://chengffei.github.io/clip/">網站</a> ·
  <a href="#從原始碼建置">從原始碼建置</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Clip 截圖畫面：一個選取範圍和一條工具列">
</p>

## 少，是刻意的。

截圖工具越做越大，雲端同步、團隊協作、訂閱一樣不少。Clip 只做三件事：截圖、錄影、辨識文字，做完就退到一旁。不用註冊帳號，不收集資料，所有內容都留在你的 Mac 上。

## 功能

**一按即截。** 在任何地方連按兩下 ⌘。視窗邊緣自動貼齊，選取範圍精確到像素，多部顯示器都能用。

**隨手標註。** 矩形、橢圓、箭頭、直線、畫筆、螢光筆、馬賽克、編號和文字。每個標註都能再修改，支援還原和重做。

**只錄你要的那塊。** 把選取的範圍錄成 MP4 或 GIF，小巧的控制列可隨時暫停和停止。

**什麼文字都能拿下來。** 文字辨識完全在本機完成。先由 Apple Vision 辨識，沒辨識出來時，內建模型接手。按一下，文字就進了剪貼簿。

**長圖也能截。** 開始捲動截圖，然後捲動頁面。Clip 邊捲邊拼接，頂部和底部的固定列只出現一次。

**釘選、取色、旋轉。** 讓截圖浮在所有視窗上方，吸取螢幕上任何顏色，或一鍵旋轉圖片。

**工具列，照你的習慣擺。** 左邊取消，中間工具，右邊輸出結果。每個工具都能放在工具列、「更多」選單或隱藏，分隔線想加在哪裡就加在哪裡。

**為 Mac 而生。** 原生 AppKit 開發，一個安裝檔同時支援 Apple 晶片和 Intel。

## 安裝

1. 下載 [Clip-0.4.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg)，把 Clip 拖進「應用程式」。
2. Clip 已簽署但未經 Apple 公證，首次開啟會被 macOS 擋下。先開啟一次並關閉提示，再到「系統設定 › 隱私權與安全性」按「強制打開」。也可以在「終端機」裡執行一次下面的指令，之後正常開啟即可：

   ```sh
   xattr -dr com.apple.quarantine /Applications/Clip.app
   ```
3. Clip 會要求兩項權限，都要允許：「輔助使用」用於連按 ⌘ 觸發，「螢幕錄製」用於截圖和錄影。

需要 macOS 14 或以上版本。介面目前只有簡體中文和英文，繁體中文系統會顯示簡體中文。

## 快速鍵

| 動作 | 預設 |
|---|---|
| 範圍截圖 | 連按兩下 ⌘ |
| 選取時拷貝到剪貼簿 | 連按兩下 ⌘ |
| 錄影、OCR、拷貝圖中文字、釘選、全螢幕、取色 | 在「設定 › 快捷鍵」中設定 |

編輯器裡的工具都有單鍵快速鍵，例如 R 是矩形，A 是箭頭，T 是文字。滑鼠停在工具上就能看到。

## 從原始碼建置

需要 Xcode 26 或以上版本。只裝 Command Line Tools 無法編譯權限面板用到的 SwiftUI 巨集。

```sh
bash scripts/rebuild-and-open.sh   # 編譯、簽署、安裝到 /Applications 並啟動
bash scripts/make-release.sh       # 通用發行包 → dist/Clip-<版本>.dmg 和 .zip
swift test                         # 180 多個測試；設定 CLIP_SNAPSHOT_DIR=目錄 還會輸出工具列、選取範圍、設定頁截圖
```

觸發診斷記錄寫在 `~/Library/Logs/Clip/clip.log`。`Clip --diagnose` 會印出權限狀態（從 Finder 啟動時，螢幕錄製的狀態才準確）。

## 致謝

Clip 分支自 realskyrin 的 [capcap](https://github.com/realskyrin/capcap)（MIT）。截圖引擎、編輯器和錄影流程都來自它。Clip 換了身分、權限流程和外觀，並拿掉一個人用不到的部分：雲端上傳、翻譯、拼圖、歷史紀錄、Agent 命令列、自動更新、倒數計時、QR 碼和美化。

內建的文字辨識模型是 [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) 的 PP-OCRv6 small（Apache-2.0），已轉換為 Core ML，詳見 `Resources/OCRModels/NOTICE`。

## 授權

[MIT](LICENSE)
