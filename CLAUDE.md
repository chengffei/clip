# Clip

Felix's personal macOS menu bar tool: region screenshot with annotations, region recording (mp4 / gif), screenshot OCR to clipboard. Pure AppKit, SwiftPM, forked from capcap (MIT).

## Build & run

```bash
bash scripts/rebuild-and-open.sh   # build, sign, install to /Applications/Clip.app, launch
bash scripts/make-release.sh       # universal release → dist/Clip-<version>.dmg + .zip
```

SwiftPM must use Xcode's toolchain (`DEVELOPER_DIR` is exported in the scripts). The Command Line Tools build fails on SwiftUI macros inside PermissionFlow.

## Rules

- Visual identity lives in `Clip/UI/Brand.swift` and `Clip/UI/AdaptiveChrome.swift`. Change colors, radii and fonts there, not inline.
- Trigger diagnostics go to `~/Library/Logs/Clip/clip.log` via `FileLog`. `Clip --diagnose` prints the TCC view (Screen Recording is only accurate when launched from Finder).
- Quit the running Clip by its own PID; never `pkill` by name or drive other apps' windows.
- Commit messages in English. `NOTES.md` is local working notes and is not tracked.

## Layout

- `Clip/App/` entry point and `Info.plist`
- `Clip/Capture/` ScreenCaptureKit capture, selection overlay, recording engine, history
- `Clip/Editor/` annotation editor
- `Clip/Trigger/` double-tap ⌘ detection and global hotkeys
- `Clip/UI/` status bar, brand, toasts, HUDs
- `Clip/Settings/` settings window
- `design/` SVG sources for the app and menu bar icons; `scripts/generate-icon.sh` renders them
