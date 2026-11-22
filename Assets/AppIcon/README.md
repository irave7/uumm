# uumm 图标资源

| 文件 | 用途 |
|---|---|
| `DrawIcon.swift` | 使用 Core Graphics 绘制 1024×1024 的 PNG |
| `AppIcon-1024.png` | App 图标母版，纯白圆角底板，底板外透明 |
| `AppIcon.icns` | macOS 应用图标，放进 `.app/Contents/Resources/`，并在 Info.plist 设 `CFBundleIconFile = AppIcon` |

界面里的其它图标（菜单栏、设置页、屏上面板）一律用 SF Symbols，不另外绘制。

## 设计说明

一块青色折面进入钴蓝手机屏，表示远程画面切换到手机竖屏。

在本目录执行以下命令可重新生成母版与 icns。构建应用时，`scripts/uumm app` 直接使用 icns。

```bash
(
  set -e
  swift DrawIcon.swift AppIcon-1024.png
  icon_work=$(mktemp -d)
  trap 'rm -rf -- "$icon_work"' EXIT
  mkdir "$icon_work/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" AppIcon-1024.png --out "$icon_work/AppIcon.iconset/icon_${s}x${s}.png"
    sips -z "$((s * 2))" "$((s * 2))" AppIcon-1024.png --out "$icon_work/AppIcon.iconset/icon_${s}x${s}@2x.png"
  done
  iconutil -c icns "$icon_work/AppIcon.iconset" -o AppIcon.icns
)
```
