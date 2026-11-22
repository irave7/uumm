# uumm

Virtual displays, touch gestures, automatic phone display switching, and vertical wheel synchronization for Macs controlled through NetEase UU Remote. An MIT-licensed fork of [Snug](https://github.com/zephyr4123/snug).

[简体中文](README.md) · [日本語](README.ja.md) · [Download the DMG](https://github.com/irave7/uumm/releases/latest)

## Install

1. Set up NetEase UU Remote on the Mac running macOS 14 or later.
2. Open the DMG from [GitHub Releases](https://github.com/irave7/uumm/releases/latest) and drag **uumm** into Applications.
3. Open uumm and grant Accessibility access. In macOS 27, the permission is under System Settings → Privacy & Security → Device Control & Data Access. Screen Recording access is needed only for uumm's optional screenshot feature.

This release is ad-hoc signed and has not been notarized by Apple. macOS may block it on first launch. After verifying the download source, see [Apple's instructions](https://support.apple.com/102445) for allowing the individual app to open.

## Use

- **Virtual displays and gestures.** Enable a virtual display in uumm and select it in UU Remote after connecting. The display includes an app library, window layout, and gestures for phones and tablets. The Mac's original display is the default main display.
- **Automatic phone display switching.** In Settings → UU 优化 (UU enhancements), turn on 自动切屏 (Automatic switching). Enter the phone name exactly as it appears on UU Remote's local incoming-control page and save it. In Displays, enable a single portrait virtual phone display and retain the existing main display. When the specified phone is the only controller, UU Remote is streaming the original display, and the target display is online, uumm briefly disables the built-in screen so UU Remote switches to the virtual display, then restores the built-in main display. Other devices and unidentified controllers do not initiate a switch.
- **Vertical wheel synchronization.** In Settings → UU 优化, turn on 同步纵向滚轮 (Sync vertical wheel). uumm combines macOS Natural Scrolling with the applicable LinearMouse vertical reversal, and uses lines per notch where the configuration can be matched. The local mouse and trackpad use their own settings. [LinearMouse](https://linearmouse.app/)

Both automatic phone switching and wheel synchronization start off. Automatic switching supports a built-in main display with only the built-in and target virtual displays online. The built-in panel goes dark briefly and windows may temporarily move. A different controller taking over during that interval might land on the virtual display. Use a unique phone name. When UU Remote cannot identify the controller, select the virtual display manually in UU Remote.

## Migrate from Snug

Before using uumm, quit Snug, UUyc-companion and any separate UU wheel or display-switching helpers. Keep the old apps and settings while you configure the desired display in uumm. Once it works, remove the old helpers from Login Items if you no longer use them.

## Source and license

On a Mac with Xcode, Swift 6, and the macOS SDK, run `scripts/uumm check` to build and test. Run `scripts/uumm dmg` to build the app and disk image. Outputs are written to `build/` and `dist/`.

The project preserves Snug's history and [MIT license](LICENSE). Thanks to zephyr4123 for [Snug](https://github.com/zephyr4123/snug), AoyamaShou for [UUyc-companion](https://github.com/aoyamashou/UUyc-companion), and the contributors to [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow), [Better Remote](https://github.com/pincc-debug/better-remote), and [FreeDisplay](https://github.com/huberdf/FreeDisplay).

uumm is a community project independent of NetEase. Virtual displays and automatic switching depend on private macOS display interfaces and on the behavior of the installed UU Remote client. Platform updates may affect compatibility.
