// UU远程 的适配器：每拍合成一份观测：覆盖窗口（同步查）、控制端表格（后台读）、推流（日志子进程）
import AppKit
import RemoteUU
import SnugCore
import SnugSystem

@MainActor
package final class UURemoteAdapter: RemoteAdapter {
    package static let identity = UURemote.identity
    private let controllers = ControllerReader()
    private let captureLog = CaptureLogWatcher()

    package init() {}

    package func start() {
        UURemoteApp.start()
        captureLog.start()
    }
    package func stop() { captureLog.stop() }

    package func sample(wallClock: Date) -> RemoteObservation {
        let capture = captureLog.sample(at: wallClock)
        return UUSignals(overlayVisible: UURemoteApp.overlayVisible(), controllers: controllers.poll(), captureActive: capture.active)
            .observation(streamedDisplay: capture.display)
    }

    package func phoneSwitchCapture() -> (display: DisplayID, startedAt: Date)? {
        captureLog.confirmedCapture()
    }

    /// Verify the current table off the main thread. The normal connection tracker deliberately retains old names.
    package func phoneSwitchControllers() async -> [String]? {
        guard AX.isTrusted, let pid = UURemoteApp.pid() else { return nil }
        let result: [String]? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let started = ProcessInfo.processInfo.systemUptime
                let names = autoreleasepool {
                    UUAccessibility.windows(pid: pid).map(ControllerTable.init(windows:))?.names
                }
                continuation.resume(returning: ProcessInfo.processInfo.systemUptime - started <= 2 ? names : nil)
            }
        }
        guard UURemoteApp.pid() == pid else { return nil }
        return result
    }

    /// UU may only publish this table while its window exists. Reopen it without stealing focus.
    package func reopenControllerWindow() {
        guard let pid = UURemoteApp.pid(), let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
}
