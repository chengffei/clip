<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  Double-tap ⌘. Frame it. Done.<br>
  Screenshots, recording and text recognition. Nothing leaves your Mac.<br><br>
  A free, open-source screenshot, screen recording and OCR tool for Mac. An alternative to CleanShot X and Shottr.
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.5.0.dmg"><b>Download</b></a> ·
  <a href="https://chengffei.github.io/clip/">Website</a> ·
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Clip capture overlay with a selection and a single toolbar">
</p>

## Nothing leaves your Mac.

**Online only when you ask.** No upload, no account, no telemetry. Clip goes online for one thing: when you choose Check for Updates.

**Text, every time.** Apple Vision reads first. If it stalls or finds nothing, a built-in model steps in. Both run on your Mac, and the text lands on your clipboard.

**Double-tap in. Double-tap out.** Double-tap ⌘ to start, double-tap again to copy.

## Everything else, built in.

- **Mark it up:** shapes, arrows, pen, mosaic, numbers and text; every mark stays editable
- **Record the region:** the same frame, to MP4 or GIF
- **Go long:** scroll and Clip stitches as you go; fixed headers and footers appear once
- **Pin and pick:** float a capture above your windows, pick any color on screen
- **Snap to windows:** click a window to frame it, pixel-precise on every display
- **Your toolbar, your way:** any tool on the bar, in More or out of sight, with dividers anywhere
- **Made for the Mac:** native AppKit, one app for Apple silicon and Intel

## How it compares

Shottr is tiny but can't record. CleanShot X does the most and costs $35. PixPin is free and packed, but closed source and 127 MB. Clip is free, open and stays offline. See the [full table](https://chengffei.github.io/clip/#compare).

## Install

1. Download [Clip-0.5.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.5.0.dmg) and drag Clip into Applications.
2. Clip is signed but not notarized, so macOS blocks the first launch. Open it, close the warning, then click **Open Anyway** in *System Settings › Privacy & Security*. Or run this once in Terminal and open Clip as usual:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Clip.app
   ```
3. Allow two permissions when asked: **Accessibility** for the ⌘⌘ trigger and **Screen Recording** for capture.

Requires macOS 14 or later.

## Shortcuts

| Action | Default |
|---|---|
| Region screenshot | ⌘ ⌘ (double-tap) |
| Copy to clipboard while selecting | ⌘ ⌘ |
| Record, OCR, copy image text, pin, full screen, color picker | Set in Settings › Shortcuts |

Editor tools have single-key shortcuts, such as R for rectangle, A for arrow and T for text. Hover a tool to see its key.

## Build from source

Requires Xcode 26 or later. The Command Line Tools alone can't build the SwiftUI macros used by the permission panel.

```sh
bash scripts/rebuild-and-open.sh   # build, sign, install to /Applications, launch
bash scripts/make-release.sh       # universal release → dist/Clip-<version>.dmg and .zip
swift test                         # 180+ tests; CLIP_SNAPSHOT_DIR=dir also writes toolbar/selection/settings PNGs
```

Trigger diagnostics are written to `~/Library/Logs/Clip/clip.log`. `Clip --diagnose` prints the permission state (Screen Recording is only accurate when launched from Finder).

## Credits

The built-in text recognition model is PP-OCRv6 small from [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) (Apache-2.0), converted to Core ML. See `Resources/OCRModels/NOTICE`.

## License

[MIT](LICENSE)
