# Clip

Felix 自用的 macOS 菜单栏截图工具。三件事：区域截图加标注、区域录屏（mp4 与 gif）、截图 OCR 直接进剪贴板。

基于 [realskyrin/capcap](https://github.com/realskyrin/capcap) 1.7.22（MIT）分叉，原作者版权声明见 `LICENSE`。相对上游的改动：

- 应用名、包名改为 Clip 与 `com.chengffei.clip`，用个人开发者证书签名，权限授予后不随重编译丢失。
- 去掉分享扩展、自动更新、多余语言包，只留简体中文与英文。
- 双击 ⌘ 检测按权限状态选路径并写日志，排查「没反应」。
- 视觉按 Apple 风重做（进行中）。

## 构建

需要 Xcode（Command Line Tools 的 SwiftPM 缺 SwiftUI 宏插件）。

```bash
bash scripts/rebuild-and-open.sh   # 编译、签名、装到 /Applications/Clip.app 并启动
bash scripts/bundle.sh --release   # 只打包到 build/Clip.app
```

## 权限

首次启动在设置窗口授予两项：辅助功能（双击 ⌘）、屏幕录制（截图与录屏）。

排查触发器：

```bash
log stream --predicate 'subsystem == "com.chengffei.clip"' --style compact
```
