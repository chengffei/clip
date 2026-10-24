<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  Double-tap ⌘. Frame it. Done.<br>
  双击 ⌘，框住，完事。一个只做截图、录屏、OCR 的 macOS 菜单栏工具。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest"><b>Download</b></a> ·
  <a href="#中文">中文</a>
</p>

## Why Clip

Screenshot tools keep growing: cloud sync, teams, subscriptions. Clip goes the other way. It lives in the menu bar, wakes on a double-tap of ⌘, and does three things: a region screenshot you can annotate, a region recording, and OCR that drops the text straight into your clipboard. Light, native-looking chrome, one blue accent, no telemetry, no account.

## Features

- **Double-tap ⌘** anywhere to start a capture; window edges snap, selections are pixel-precise, multi-display aware
- **Annotate**: rectangle, ellipse, arrow, pen, highlighter, mosaic, numbered markers, text; every mark stays editable with undo / redo
- **Record** the selected region to mp4 or gif, with a small HUD for pause and stop
- **OCR to clipboard**: Apple Vision on-device recognition, copied as text with one shortcut
- **Scrolling capture**, pin to screen, color picker
- **One toolbar, three zones**: close on the left, drawing tools in the middle, outcomes (OCR, save, pin, copy) on the right; shapes collapse into one button, the rest hides behind “more”. Settings › Toolbar lets you move anything between the bar, the menu and hidden
- **Native AppKit**, Swift Package Manager, about 45k lines after cutting cloud upload, translation, image merge, history panel and the rest; Apple Silicon and Intel

## Install

1. Download `Clip-<version>.dmg` from the [latest release](https://github.com/chengffei/clip/releases/latest) and drag Clip into Applications.
2. **First launch**: Clip is signed but not notarized by Apple, so macOS blocks it once. Open it, dismiss the warning, then go to *System Settings › Privacy & Security* and click **Open Anyway**.
3. Grant two permissions when Clip asks: **Accessibility** (for the ⌘⌘ trigger) and **Screen Recording** (for capture). Clip requests Screen Recording through the system prompt, so it appears in the list by itself.

Requires macOS 14 or later.

## Shortcuts

| Action | Default |
|---|---|
| Region screenshot | ⌘ ⌘ (double-tap) |
| Countdown screenshot | ⌥⌘ ⌥⌘ |
| Confirm to clipboard while the overlay is up | ⌘ ⌘ |
| Record, OCR, pin, full screen | set in Settings › Shortcuts |

## Build from source

Requires Xcode 26 or later. The Command Line Tools alone cannot build the SwiftUI macros used by the permission panel.

```sh
bash scripts/rebuild-and-open.sh   # build, sign, install to /Applications, launch
bash scripts/make-release.sh       # universal release → dist/Clip-<version>.dmg and .zip
```

Trigger diagnostics are written to `~/Library/Logs/Clip/clip.log`.

## Credits

Clip is a fork of [capcap](https://github.com/realskyrin/capcap) by realskyrin (MIT). The capture engine, editor and recording pipeline come from there; Clip changes the identity, the permission flow and the chrome, and removes what one person does not need: cloud upload, translation, image merge, the history panel, the agent CLI, auto-update, countdown, QR and beautify toolbar buttons.

## License

[MIT](LICENSE)

---

## 中文

### 为什么做 Clip

截图工具越做越大：云同步、团队版、订阅。Clip 反过来。它住在菜单栏里，双击 ⌘ 唤起，只做三件事：可标注的区域截图、区域录屏、把图上文字直接 OCR 进剪贴板。墨黑底、一个酸性强调色，不联网、不要账号。

### 功能

- **双击 ⌘** 随时截图，窗口边缘自动吸附，选区像素级精准，多显示器可用
- **标注**：矩形、椭圆、箭头、画笔、高亮、马赛克、序号、文字，放下后还能改，支持撤销重做
- **录屏**：选区录成 mp4 或 gif，小 HUD 负责暂停与停止
- **OCR 进剪贴板**：Apple Vision 本机识别，一个快捷键把文字复制走
- **长截图**、钉图、取色
- **一条工具栏，三段**：左边关闭，中间画图工具，右边结果（OCR、保存、钉图、复制）；四种形状合成一个按钮，其余收进「更多」。设置里的「工具栏」页可以把任何工具在栏、菜单、隐藏之间拖动
- **原生 AppKit**，Swift Package Manager，砍掉图床、翻译、拼图、历史面板等后约 4.5 万行；Apple Silicon 与 Intel 通用

### 安装

1. 到 [最新 Release](https://github.com/chengffei/clip/releases/latest) 下载 `Clip-<版本>.dmg`，把 Clip 拖进「应用程序」。
2. **首次打开**：Clip 有签名但没过 Apple 公证，macOS 会拦一次。打开后关掉提示，到「系统设置 › 隐私与安全性」点 **仍要打开**。
3. 按提示授予两项权限：**辅助功能**（双击 ⌘）与 **屏幕录制**（截图与录屏）。屏幕录制由 Clip 向系统申请，列表里会自动出现，不用手动拖。

需要 macOS 14 或更高。

### 快捷键

| 动作 | 默认 |
|---|---|
| 区域截图 | 双击 ⌘ |
| 倒计时截图 | 双击 ⌥⌘ |
| 选区打开时直接复制 | 双击 ⌘ |
| 录屏、OCR、钉图、全屏 | 在「设置 › 快捷键」里定 |

### 从源码构建

需要 Xcode 26 或更高。只装 Command Line Tools 编不过权限面板用到的 SwiftUI 宏。

```sh
bash scripts/rebuild-and-open.sh   # 编译、签名、装到 /Applications 并启动
bash scripts/make-release.sh       # 通用二进制发布包 → dist/
```

触发器日志在 `~/Library/Logs/Clip/clip.log`。

### 致谢

Clip 分叉自 realskyrin 的 [capcap](https://github.com/realskyrin/capcap)（MIT）。截图引擎、编辑器、录屏管线都来自那里；Clip 改了身份、权限流程和外观，删掉一个人用不到的部分：图床、翻译、拼图、历史面板、Agent 命令行、自动更新、倒计时、二维码与美化按钮。

### 许可

[MIT](LICENSE)
