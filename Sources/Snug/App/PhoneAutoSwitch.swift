import AppKit
import Darwin
import RemoteUUSystem
import SnugCore

/// Switches the viewed display only for the configured UU phone. The display worker and recovery worker
/// run outside the app so a stalled UI or an app crash cannot keep the physical display suspended.
@MainActor
final class PhoneAutoSwitch {
    private struct Capture: Equatable {
        let display: DisplayID
        let startedAt: Date
    }

    private struct Candidate: Equatable {
        let generation: Int
        let phone: String
        let target: DisplayID?
        let capture: Capture
        let maySwitch: Bool
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
    private var admittedPhone: String?
    private var verifiedCapture: Capture?
    private var changedCaptureAt: Date?
    private var controllers: [String] = []
    private var isHandoff = false

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

    func mayShowPhoneDisplay(named phone: String?) -> Bool {
        // 切屏期间，先恢复原屏再允许撤掉虚拟屏。
        attempt != nil || (phone != nil && admittedPhone == phone)
    }

    func observe(adapter: UURemoteAdapter?, registeredPhone: String?, target: DisplayID?, transitions: [SessionTransition]) {
        guard running else { return }
        configuredPhone = registeredPhone
        configuredTarget = target

        for transition in transitions {
            switch transition {
            case .began(let names), .resumed(let names):
                newConnection(at: Date())
                controllers = names
            case .interrupted, .ended:
                newConnection(at: nil)
                controllers = []
            case .controllersChanged(let names):
                if let registeredPhone, names != [registeredPhone] || (!controllers.isEmpty && controllers != names) {
                    newConnection(at: Date(), isHandoff: names == [registeredPhone])
                }
                controllers = names
            }
        }
        if adapter == nil || admittedPhone != registeredPhone { admittedPhone = nil }
        if let pending = attempt {
            if admittedPhone == nil || target != pending.target {
                requestRestore()
            } else if let capture = adapter?.phoneSwitchCapture(), capture.display == pending.target,
                      capture.startedAt >= pending.requestedAt, Date().timeIntervalSince(capture.startedAt) >= 0.25 {
                requestRestore()
            }
            return
        }

        guard let adapter, let phone = registeredPhone, !phone.isEmpty else { return }
        guard let openedAt, let stream = adapter.phoneSwitchCapture() else { return }
        let now = Date()
        let capture = Capture(display: stream.display, startedAt: stream.startedAt)
        let mayIdentifyNewPhone = (0...12).contains(now.timeIntervalSince(openedAt)) &&
            (isHandoff || stream.startedAt >= openedAt.addingTimeInterval(-2))
        let maySwitch = mayIdentifyNewPhone && !attempted && target.map {
            PhoneDisplayState.matches(source: stream.display, target: $0)
        } == true
        // 自己切屏也会重启推流。给控制端表格几秒恢复，超时则停止提供旧手机屏。
        let captureChanged = admittedPhone == phone && verifiedCapture != capture
        if captureChanged {
            let changedAt = changedCaptureAt ?? now
            changedCaptureAt = changedAt
            if now.timeIntervalSince(changedAt) > 4 {
                admittedPhone = nil
            }
        } else {
            changedCaptureAt = nil
        }
        if admittedPhone == phone && stream.display == target { attempted = true }
        let needIdentity = captureChanged || (admittedPhone == nil && mayIdentifyNewPhone)
        guard needIdentity || maySwitch, now >= nextVerification, verification == nil,
              recoveryWorker?.isRunning != true, !hasRecoveryRecord else { return }
        nextVerification = now.addingTimeInterval(0.6)
        let candidate = Candidate(generation: generation, phone: phone, target: target, capture: capture, maySwitch: maySwitch)
        verification = Task { [weak self] in
            await self?.verifyAndSwitch(candidate, using: adapter)
        }
    }

    private func newConnection(at date: Date?, isHandoff: Bool = false) {
        generation += 1
        openedAt = date
        nextVerification = .distantPast
        admittedPhone = nil
        verifiedCapture = nil
        changedCaptureAt = nil
        self.isHandoff = isHandoff
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
        guard running, !Task.isCancelled, candidate.generation == generation,
              configuredPhone == candidate.phone, configuredTarget == candidate.target,
              let stream = adapter.phoneSwitchCapture(),
              Capture(display: stream.display, startedAt: stream.startedAt) == candidate.capture else { return }
        guard let names, !names.isEmpty else {
            if !reopened {
                reopened = true
                adapter.reopenControllerWindow()
            }
            return
        }
        guard names == [candidate.phone] else {
            admittedPhone = nil
            return
        }
        if admittedPhone != candidate.phone {
            admittedPhone = candidate.phone
            Log.info("手机切屏：已确认指定手机，允许创建手机屏")
        }
        verifiedCapture = candidate.capture
        changedCaptureAt = nil
        guard candidate.maySwitch, let openedAt, (0...12).contains(Date().timeIntervalSince(openedAt)),
              let target = candidate.target, !attempted,
              PhoneDisplayState.matches(source: candidate.capture.display, target: target) else { return }

        let directory = recoveryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            let state = try PhoneDisplayState.capture(source: candidate.capture.display, target: target)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(state).write(to: PhoneDisplayFiles(directory).record, options: .atomic)
            let watchdog = try launch(.watch, directory: directory) { [weak self] status in
                self?.watchdogExited(at: directory, status: status)
            }
            attempt = Attempt(directory: directory, target: target, requestedAt: Date())
            let deadline = ContinuousClock.now + .milliseconds(750)
            while watchdog.isRunning, ContinuousClock.now < deadline,
                  !FileManager.default.fileExists(atPath: PhoneDisplayFiles(directory).ready.path) {
                try await Task.sleep(for: .milliseconds(25))
            }
            guard running, !Task.isCancelled, candidate.generation == generation, attempt?.directory == directory,
                  configuredPhone == candidate.phone, configuredTarget == candidate.target,
                  attempt?.restoreRequested == false, watchdog.isRunning,
                  FileManager.default.fileExists(atPath: PhoneDisplayFiles(directory).ready.path),
                  let current = adapter.phoneSwitchCapture(),
                  Capture(display: current.display, startedAt: current.startedAt) == candidate.capture else {
                requestRestore()
                return
            }
            attempted = true
            attempt?.requestedAt = Date()
            Log.info("手机切屏：已核对控制端和当前推流，切到屏 #\(target)")
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
