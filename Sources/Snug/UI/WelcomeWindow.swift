// 欢迎页说明 uumm 的主要功能和授权入口。
// 授权状态读 AppState（AppController 每拍刷新），这里不自己轮询
import AppKit
import SwiftUI
import SnugCore

struct WelcomeView: View {
    let state: AppState
    let onDone: () -> Void

    var body: some View {
        let granted = state.accessibilityTrusted
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                Text("欢迎使用 uumm").font(.largeTitle.bold())
                Text("为 UU 远程连接设置屏幕、触控和滚轮").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                Feature(symbol: "rectangle.on.rectangle", title: "使用远程虚拟屏", detail: "在 UU 的屏幕列表选屏，手机和平板可铺满窗口")
                Feature(symbol: "iphone.radiowaves.left.and.right", title: "指定手机自动切屏", detail: "填写手机名称，并启用一块手机竖屏")
                Feature(symbol: "computermouse", title: "同步远程滚轮", detail: "让 UU 的纵向滚轮沿用 Mac 的 LinearMouse 设置")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                SettingLabel.accessibility
                Spacer(minLength: 12)
                PermissionStatus(granted: granted)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 12) {
                Spacer()
                if granted {
                    Button("完成", action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button("稍后", action: onDone)
                    AuthorizeButton(pane: .accessibility)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 520)
    }
}

/// 一项功能：图标统一大小，标题 + 一行说明
private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
final class WelcomeWindowController {
    private let state: AppState
    private var window: NSWindow?
    private var onDone: (() -> Void)?
    private var closeObserver: (any NSObjectProtocol)?

    init(state: AppState) { self.state = state }

    func show(onDone: (() -> Void)? = nil) {
        if let onDone { self.onDone = onDone }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(state: state) { [weak self] in
                self?.window?.close()
            }))
            w.styleMask = [.titled, .closable]
            w.title = "uumm"
            w.isReleasedWhenClosed = false
            w.center()
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
