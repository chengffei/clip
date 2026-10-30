<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Clip">
</p>

<h1 align="center">Clip</h1>

<p align="center">
  连按两下 ⌘，框一下，就好。<br>
  截图、录屏、识别文字，都在菜单栏里。
</p>

<p align="center">
  <a href="https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg"><b>下载</b></a> ·
  <a href="https://chengffei.github.io/clip/">官网</a> ·
  <a href="#从源码构建">从源码构建</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Clip 截图界面：一个选区和一条工具栏">
</p>

## 少，是刻意的。

截图工具越做越大，云同步、团队协作、订阅一样不少。Clip 只做三件事：截图、录屏、识别文字，做完就退到一边。不用注册账号，不收集数据，所有内容都留在你的 Mac 上。

## 功能

**一按即截。** 在任何地方连按两下 ⌘。窗口边缘自动吸附，选区精确到像素，多台显示器都能用。

**随手标注。** 矩形、椭圆、箭头、直线、画笔、荧光笔、马赛克、序号和文字。每个标注都能再改，支持撤销和重做。

**只录你要的那块。** 把选中的区域录成 MP4 或 GIF，小巧的控制条可以随时暂停和停止。

**什么文字都能拿下来。** 文字识别完全在本机完成。先由 Apple Vision 识别，没识别出来时，内置模型接着上。点一下，文字就进了剪贴板。

**长图也能截。** 开始长截图，然后滚动页面。Clip 边滚边拼，顶部和底部的固定栏只出现一次。

**贴图、取色、旋转。** 让截图浮在所有窗口上方，吸取屏幕上任意颜色，或一键旋转图片。

**工具栏，按你的习惯摆。** 左边取消，中间工具，右边出结果。每个工具都能放在工具栏、「更多」菜单或隐藏，分隔线想加在哪就加在哪。

**为 Mac 而生。** 原生 AppKit 开发，一个安装包同时支持 Apple 芯片和 Intel。

## 安装

1. 下载 [Clip-0.4.0.dmg](https://github.com/chengffei/clip/releases/latest/download/Clip-0.4.0.dmg)，把 Clip 拖进「应用程序」。
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
