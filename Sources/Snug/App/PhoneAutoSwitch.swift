import AppKit
import Darwin
import RemoteUUSystem
import SnugCore

/// Switches the viewed display only for the configured UU phone. The display worker and recovery worker
/// run outside the app so a stalled UI or an app crash cannot keep the physical display suspended.
@MainActor
final class PhoneAutoSwitch {
    private struct Candidate: Equatable {
        let generation: Int
        let phone: String
        let target: DisplayID
        let source: DisplayID
        let captureStarted: Date
    }

    private struct Attempt {
        let directory: URL
        let target: DisplayID
        var requestedAt: Date
        var restoreRequested = false
        var applyWorker: Process?
    }

    private let helper: URL
    private let recoveryDirectory: URL
    private var recoveryWorker: Process?
    private var attempt: Attempt?
    private var verification: Task<Void, Never>?
    private var generation = 0
    private var openedAt: Date?
    private var nextVerification = Date.distantPast
    private var attempted = false
    private var reopened = false
    private var running = false
    private var configuredPhone: String?
    private var configuredTarget: DisplayID?

    init(paths: SnugPaths, helper: URL) {
        self.helper = helper
        recoveryDirectory = PhoneDisplayFiles.recoveryRoot(paths: paths)
    }

    func start() {
        running = true
        recoverIfNeeded()
    }

    private func recoverIfNeeded() {
        guard hasRecoveryRecord else { return }
        do { recoveryWorker = try launch(.recoverAbandoned, directory: recoveryDirectory) }
        catch { Log.error("手机切屏：无法启动原屏恢复：\(error.localizedDescription)") }
    }

    func stop() {
        running = false
        verification?.cancel()
        if let worker = attempt?.applyWorker, worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
        requestRestore()
    }

    func observe(adapter: UURemoteAdapter?, registeredPhone: String?, target: DisplayID?, transitions: [SessionTransition]) {
        guard running else { return }
        configuredPhone = registeredPhone
        configuredTarget = target
        if let pending = attempt {
            if registeredPhone == nil || target.map({ $0 != pending.target }) == true {
                requestRestore()
            } else if let capture = adapter?.phoneSwitchCapture(), capture.display == pending.target,
                      capture.startedAt >= pending.requestedAt, Date().timeIntervalSince(capture.startedAt) >= 0.25 {
                requestRestore()
            }
            return
        }

        for transition in transitions {
            switch transition {
            case .began, .resumed: newConnection(at: Date())
            case .interrupted, .ended: newConnection(at: nil)
            case .controllersChanged: break
            }
        }
        guard let adapter, let phone = registeredPhone, !phone.isEmpty, let target else { return }
        guard verification == nil, !attempted, recoveryWorker?.isRunning != true, !hasRecoveryRecord,
              let openedAt, let stream = adapter.phoneSwitchCapture() else { return }
        let now = Date()
        guard (0...12).contains(now.timeIntervalSince(openedAt)), now >= nextVerification,
              stream.startedAt >= openedAt.addingTimeInterval(-2) else { return }
        if stream.display == target {
            // The viewer already selected the phone display; don't interrupt this connection.
            attempted = true
            return
        }
        guard PhoneDisplayState.matches(source: stream.display, target: target) else { return }
        nextVerification = now.addingTimeInterval(0.6)
        let candidate = Candidate(generation: generation, phone: phone, target: target,
                                  source: stream.display, captureStarted: stream.startedAt)
        verification = Task { [weak self] in
            await self?.verifyAndSwitch(candidate, using: adapter)
        }
    }

    private func newConnection(at date: Date?) {
        generation += 1
        openedAt = date
        nextVerification = .distantPast
        attempted = false
        reopened = false
        verification?.cancel()
    }

    private var hasRecoveryRecord: Bool {
        let pending = (try? FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)) ?? []
        return pending.contains { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    private func verifyAndSwitch(_ candidate: Candidate, using adapter: UURemoteAdapter) async {
        defer { verification = nil }
        let names = await adapter.phoneSwitchControllers()
        guard running, !Task.isCancelled, candidate.generation == generation, let openedAt,
              configuredPhone == candidate.phone, configuredTarget == candidate.target,
              (0...12).contains(Date().timeIntervalSince(openedAt)),
              let capture = adapter.phoneSwitchCapture(), capture.display == candidate.source,
              capture.startedAt == candidate.captureStarted else { return }
        guard let names, !names.isEmpty else {
            if !reopened {
                reopened = true
                adapter.reopenControllerWindow()
            }
            return
        }
        guard names == [candidate.phone] else { return }

        let directory = recoveryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            let state = try PhoneDisplayState.capture(source: candidate.source, target: candidate.target)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(state).write(to: PhoneDisplayFiles(directory).record, options: .atomic)
            let watchdog = try launch(.watch, directory: directory) { [weak self] status in
                self?.watchdogExited(at: directory, status: status)
            }
            attempt = Attempt(directory: directory, target: candidate.target, requestedAt: Date())
            let deadline = ContinuousClock.now + .milliseconds(750)
            while watchdog.isRunning, ContinuousClock.now < deadline,
                  !FileManager.default.fileExists(atPath: PhoneDisplayFiles(directory).ready.path) {
                try await Task.sleep(for: .milliseconds(25))
            }
            guard running, !Task.isCancelled, candidate.generation == generation, attempt?.directory == directory,
                  configuredPhone == candidate.phone, configuredTarget == candidate.target,
                  attempt?.restoreRequested == false, watchdog.isRunning,
                  FileManager.default.fileExists(atPath: PhoneDisplayFiles(directory).ready.path),
                  let current = adapter.phoneSwitchCapture(), current.display == candidate.source,
                  current.startedAt == candidate.captureStarted else {
                requestRestore()
                return
            }
            attempted = true
            attempt?.requestedAt = Date()
            Log.info("手机切屏：已核对控制端和当前推流，切到屏 #\(candidate.target)")
            let worker = try launch(.apply, directory: directory) { [weak self] status in
                guard let self, attempt?.directory == directory else { return }
                if status != 0 {
                    Log.warn("手机切屏：屏幕切换未完成（状态 \(status)）")
                    requestRestore()
                }
            }
            attempt?.applyWorker = worker
        } catch {
            if attempt?.directory == directory { requestRestore() }
            else { try? FileManager.default.removeItem(at: directory) }
            if !(error is CancellationError) {
                Log.warn("手机切屏：无法执行自动切换：\(error.localizedDescription)")
            }
        }
    }

    private func requestRestore() {
        guard let pending = attempt, !pending.restoreRequested else { return }
        do {
            try Data().write(to: PhoneDisplayFiles(pending.directory).restore, options: .atomic)
            attempt?.restoreRequested = true
        } catch {
            Log.warn("手机切屏：无法请求提前恢复原屏，等待独立恢复进程")
        }
    }

    private func watchdogExited(at directory: URL, status: Int32) {
        guard attempt?.directory == directory else { return }
        attempt = nil
        if status == 0 {
            Log.info("手机切屏：Mac 原屏已恢复")
        } else {
            Log.error("手机切屏：原屏恢复未完成，保留恢复记录（状态 \(status)）")
            recoverIfNeeded()
        }
    }

    private func launch(_ mode: PhoneAutoSwitchWorker, directory: URL,
                        onExit: (@MainActor @Sendable (Int32) -> Void)? = nil) throws -> Process {
        let worker = Process()
        worker.executableURL = helper
        worker.arguments = [mode.rawValue, directory.path]
        worker.standardInput = FileHandle.nullDevice
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        if let onExit {
            worker.terminationHandler = { process in
                let status = process.terminationStatus
                Task { @MainActor in onExit(status) }
            }
        }
        try worker.run()
        return worker
    }
}
