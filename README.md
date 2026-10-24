<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  Double-tap ⌘. Frame it. Done.<br>
  A macOS menu bar tool that only does screenshots, screen recording and OCR.
</p>

<p align="center">
  <a href="https://chengffei.github.io/clip/"><b>Website</b></a> ·
  <a href="https://github.com/chengffei/clip/releases">Releases</a> ·
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Clip capture overlay with a selection and a single toolbar">
</p>

## Why Clip

Screenshot tools keep growing: cloud sync, teams, subscriptions. Clip goes the other way. It lives in the menu bar, wakes on a double-tap of ⌘, and does three things: a region screenshot you can annotate, a region recording, and OCR that drops the text straight into your clipboard. Native light chrome, one blue accent, no telemetry, no account.

## Features

- **Double-tap ⌘** anywhere to start a capture. Window edges snap, selections are pixel-precise, the size label shows origin and dimensions, multiple displays work.
- **Annotate**: rectangle, ellipse, arrow, line, pen, highlighter, mosaic, numbered markers, text. Every mark stays editable, with undo and redo.
- **Record** the selected region to MP4 or GIF, with a small HUD for pause and stop.
- **OCR to clipboard**: on-device Apple Vision recognition. One click or one shortcut copies the text; a result panel is available in Settings.
- **Scrolling capture**, pin to screen, color picker, rotate.
- **One toolbar, three zones**: cancel on the left, drawing tools in the middle, outcomes (OCR, save, pin, confirm) on the right. Nothing is selected when the editor opens, so you see one bar, not two. Settings › Toolbar moves any tool between the bar, the “more” menu and hidden.
- **Native AppKit**, Swift Package Manager, universal binary for Apple silicon and Intel.

## Install

There is no packaged release yet. Until the first one is published, build from source (below). When releases exist:

1. Download `Clip-<version>.dmg` from [Releases](https://github.com/chengffei/clip/releases) and drag Clip into Applications.
2. **First launch**: Clip is signed but not notarized by Apple, so macOS blocks it once. Open it, dismiss the warning, then go to *System Settings › Privacy & Security* and click **Open Anyway**.
3. Grant two permissions when Clip asks: **Accessibility** (for the ⌘⌘ trigger) and **Screen Recording** (for capture). Clip requests Screen Recording through the system prompt, so it appears in the list by itself.

Requires macOS 14 or later.

## Shortcuts

| Action | Default |
|---|---|
| Region screenshot | ⌘ ⌘ (double-tap) |
| Confirm to clipboard while the overlay is up | ⌘ ⌘ |
| Record, OCR, copy image text, pin, full screen, color picker | set in Settings › Shortcuts |

Editor tool shortcuts (R for rectangle, A for arrow, T for text and so on) are listed in the tooltips and in Settings › Toolbar.

## Build from source

Requires Xcode 26 or later. The Command Line Tools alone cannot build the SwiftUI macros used by the permission panel.

```sh
bash scripts/rebuild-and-open.sh   # build, sign, install to /Applications, launch
bash scripts/make-release.sh       # universal release → dist/Clip-<version>.dmg and .zip
swift test                         # 160+ tests; CLIP_SNAPSHOT_DIR=dir also writes toolbar/selection/settings PNGs
```

Trigger diagnostics are written to `~/Library/Logs/Clip/clip.log`. `Clip --diagnose` prints the permission state (Screen Recording is only accurate when launched from Finder).

## Credits

Clip is a fork of [capcap](https://github.com/realskyrin/capcap) by realskyrin (MIT). The capture engine, editor and recording pipeline come from there. Clip changes the identity, the permission flow and the chrome, and removes what one person does not need: cloud upload, translation, image merge, the history panel, the agent CLI, auto-update, countdown, QR and beautify toolbar buttons.

## License

[MIT](LICENSE)
