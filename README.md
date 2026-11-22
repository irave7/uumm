# uumm

为网易 UU 远程控制的 Mac 提供虚拟屏、触控手势、手机自动切屏和纵向滚轮同步。基于 [Snug](https://github.com/zephyr4123/snug) 的 MIT 开源分支。

[English](README.en.md) · [日本語](README.ja.md) · [下载 DMG](https://github.com/irave7/uumm/releases/latest)

## 安装

1. 确认被控 Mac 使用 macOS 14 或更新版本，并已安装、设置好网易 UU 远程。
2. 下载并打开 [GitHub Releases](https://github.com/irave7/uumm/releases/latest) 的 DMG，把 **uumm** 拖到「应用程序」。
3. 打开 uumm，按提示授予「辅助功能」权限。macOS 27 在「系统设置 → 隐私与安全 → 设备控制和数据访问」中管理此权限。仅在使用 uumm 的截图功能时额外需要「屏幕录制」权限。

当前发行包采用 ad-hoc 签名，未经 Apple 公证。macOS 可能拦截首次打开。如需使用，可在确认下载来源后，按 [Apple 支持说明](https://support.apple.com/zh-cn/102445) 在「隐私与安全」中单独允许打开 uumm。

## 使用

- **菜单栏图标。** 在「设置 → 通用」关闭「在菜单栏显示」即可隐藏图标，后台功能照常运行。可从「应用程序」或聚焦搜索重新打开 uumm 设置。
- **虚拟屏与触控。** 在 uumm 的「屏幕」页启用合适的虚拟屏，连接后从 UU 的屏幕列表选中它。虚拟屏支持应用资源库、窗口布局，以及手机和平板触控手势。默认使用 Mac 原屏作为主屏。
- **手机自动切屏。** 在「设置 → UU 优化」打开「自动切屏」，按 UU「本机被控中」页面显示的名称填写「手机在 UU 中的设备名称」，点「保存」。在「屏幕」页只启用一块竖屏手机虚拟屏，并将「设为主屏」留为「不改」。确认指定手机是唯一控制端、UU 正在推送原屏且目标屏已上线后，uumm 会暂时停用 Mac 内建屏，让 UU 切到虚拟屏，然后恢复内建主屏。其他设备和无法确认身份的连接不会触发切屏。
- **纵向滚轮同步。** 在「设置 → UU 优化」打开「同步纵向滚轮」。uumm 将 macOS 的自然滚动偏好与本机 LinearMouse 的纵向反向设置一起应用到 UU 滚轮。可识别的配置也会应用每格行数。Mac 本地鼠标和触控板继续按各自的设置工作。[LinearMouse](https://linearmouse.app/)

手机自动切屏和滚轮同步默认关闭。自动切屏目前适用于内建屏为主屏、仅有内建屏和目标虚拟屏在线的配置。切换时内建屏会短暂熄灭，窗口可能重新排列。极短时间内换用另一台控制设备可能撞上原屏正在恢复的时段。设备名称必须唯一，UU 无法提供控制端名称时可从屏幕列表手动选屏。

## 从 Snug 迁移

首次使用 uumm 前先退出 Snug、UU 远程伴侣，以及单独运行的 UU 滚轮或切屏工具，避免它们同时处理同一会话。原应用和设置可以保留；在 uumm 中选好虚拟屏并确认可用后，再按需要将旧工具从登录项移除。

## 源码与许可

在 macOS 上安装包含 Swift 6 和 macOS SDK 的 Xcode 后，运行 `scripts/uumm check` 构建并测试，运行 `scripts/uumm dmg` 构建 App 和 DMG。产物在 `build/` 和 `dist/`。

本项目保留 Snug 的开发历史与 [MIT 许可证](LICENSE)。感谢 [Snug](https://github.com/zephyr4123/snug) 的 zephyr4123、[UUyc-companion](https://github.com/aoyamashou/UUyc-companion) 的 AoyamaShou，以及 [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)、[Better Remote](https://github.com/pincc-debug/better-remote) 和 [FreeDisplay](https://github.com/huberdf/FreeDisplay) 的贡献者。

uumm 是独立社区项目，与网易 UU 远程及其开发商无隶属关系。虚拟屏和自动切屏依赖部分未公开的 macOS 显示接口，以及 UU 当前的会话和推流行为。系统或 UU 更新后可能需要重新验证。
