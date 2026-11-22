// 旧版「UU远程伴侣」（com.corndog.uudisplay）会在远程时建虚拟屏、关物理屏，和 Snug 同时运行会互相干扰
import AppKit
import SnugCore

@MainActor
enum LegacyApp {
    nonisolated private static let conflictingIDs = [
        "com.corndog.uudisplay", "com.zephyr4123.snug",
        "local.uuremote.scrollsync", "local.uuremote.phonescreenswitch",
    ]

    private static var running: [NSRunningApplication] {
        conflictingIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    static var isRunning: Bool { !running.isEmpty }

    /// 请旧版正常退出（它会先把自己改过的屏幕还原）
    static func quit() {
        let apps = running
        for app in apps where !app.terminate() {
            Log.warn("请旧版 UU远程伴侣（pid \(app.processIdentifier)）退出没有成功")
        }
        if !apps.isEmpty { Log.info("已请求旧版辅助工具退出") }
    }

    /// 旧版启动、退出时回调，参数是此刻它是否在运行
    static func observe(_ onChange: @escaping @MainActor (Bool) -> Void) -> [any NSObjectProtocol] {
        let center = NSWorkspace.shared.notificationCenter
        return [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, conflictingIDs.contains(id) else { return }
                MainActor.assumeIsolated { onChange(isRunning) }
            }
        }
    }
}
