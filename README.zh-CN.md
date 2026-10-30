<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  连按两下 ⌘，框一下，就好。<br>
  截图、录屏、识别文字。什么都不离开你的 Mac。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.5.0.dmg"><b>下载</b></a> ·
  <a href="https://chengffei.github.io/clip/">官网</a> ·
  <a href="#从源码构建">从源码构建</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Clip 截图界面：一个选区和一条工具栏">
</p>

## 什么都不离开你的 Mac。

**只在你要时联网。** 不上传，不要账号，不收集数据。Clip 只在你点「检查更新」时联网，别的时候一概不联网。

**文字，总能认出来。** 先由 Apple Vision 识别；它卡住或没认出来，内置模型接着上。两者都在本机运行，文字直接进剪贴板。

**连按开始，连按完成。** 连按两下 ⌘ 开始，再连按两下复制。

## 其他的，都有。

- **随手标注**：形状、箭头、画笔、马赛克、序号和文字，每个标注都能再改
- **录下选区**：同一个框，录成 MP4 或 GIF
- **长截图**：边滚边拼，顶部和底部的固定栏只出现一次
- **贴图与取色**：让截图浮在所有窗口上方，吸取屏幕上任意颜色
- **吸附窗口**：点一下窗口就框住，精确到像素，多显示器都行
- **工具栏随你摆**：每个工具都能放在栏上、「更多」里或隐藏，分隔线随处加
- **为 Mac 而做**：原生 AppKit，一个应用同时支持 Apple 芯片和 Intel

## 对比

Shottr 很小，但不能录屏。CleanShot X 功能最全，售价 35 美元。PixPin 免费且功能多，但闭源，安装包 127 MB。Clip 免费、开源，平时不联网。完整对比见[官网](https://chengffei.github.io/clip/#compare)。

## 安装

1. 下载 [Clip-0.5.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.5.0.dmg)，把 Clip 拖进「应用程序」。
2. Clip 已签名但未经 Apple 公证，首次打开会被 macOS 拦下。先打开一次并关掉提示，再到「系统设置 › 隐私与安全性」点「仍要打开」。也可以在「终端」里运行一次下面的命令，之后正常打开即可：

   ```sh
   xattr -dr com.apple.quarantine /Applications/Clip.app
   ```
3. Clip 会申请两项权限，都要允许：「辅助功能」用于连按 ⌘ 触发，「屏幕录制」用于截图和录屏。

需要 macOS 14 或更高版本。界面支持简体中文和英文。

## 快捷键

| 操作 | 默认 |
|---|---|
| 区域截图 | 连按两下 ⌘ |
| 选区时复制到剪贴板 | 连按两下 ⌘ |
| 录屏、OCR、复制图中文字、贴图、全屏、取色 | 在「设置 › 快捷键」中设置 |

编辑器里的工具都有单键快捷键，比如 R 是矩形，A 是箭头，T 是文字。鼠标停在工具上就能看到。

## 从源码构建

需要 Xcode 26 或更高版本。只装 Command Line Tools 无法编译权限面板用到的 SwiftUI 宏。

```sh
bash scripts/rebuild-and-open.sh   # 编译、签名、装到 /Applications 并启动
bash scripts/make-release.sh       # 通用发行包 → dist/Clip-<版本>.dmg 和 .zip
swift test                         # 180 多个测试；设置 CLIP_SNAPSHOT_DIR=目录 还会输出工具栏、选区、设置页截图
```

触发诊断日志写在 `~/Library/Logs/Clip/clip.log`。`Clip --diagnose` 会打印权限状态（从 Finder 启动时，屏幕录制的状态才准确）。

## 致谢

内置的文字识别模型是 [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) 的 PP-OCRv6 small（Apache-2.0），已转换为 Core ML，详见 `Resources/OCRModels/NOTICE`。

## 许可

[MIT](LICENSE)
