import CoreGraphics
import Darwin
import Foundation
import SnugCore
import SnugSystem

struct PhoneDisplayState: Codable, Sendable {
    let original: CGDirectDisplayID
    let target: CGDirectDisplayID
    private let targetX: Int32
    private let targetY: Int32
    private let bootSession: String
    private let capturedAtUptime: TimeInterval

    var isFromCurrentBoot: Bool {
        Self.currentBootSession() == bootSession
    }

    var originalIsActive: Bool {
        (Screens.online() ?? []).contains(original)
            && CGDisplayIsBuiltin(original) != 0
            && CGDisplayIsActive(original) != 0
    }

    static func matches(source: CGDirectDisplayID, target: CGDirectDisplayID) -> Bool {
        guard source != target, CGMainDisplayID() == source,
              Set(Screens.online() ?? []) == [source, target],
              CGDisplayIsBuiltin(source) != 0,
              CGDisplayVendorNumber(target) == ScreenSpec.vendorID else { return false }
        return [source, target].allSatisfy { CGDisplayIsActive($0) != 0 && CGDisplayIsInMirrorSet($0) == 0 }
    }

    static func capture(source: CGDirectDisplayID, target: CGDirectDisplayID) throws -> PhoneDisplayState {
        guard matches(source: source, target: target) else { throw PhoneDisplayError.unexpectedDisplays }
        let bounds = CGDisplayBounds(target)
        guard bounds.height > bounds.width, let x = Int32(exactly: bounds.origin.x),
              let y = Int32(exactly: bounds.origin.y), let boot = currentBootSession() else {
            throw PhoneDisplayError.unexpectedDisplays
        }
        guard setEnabled != nil else { throw PhoneDisplayError.unavailable }
        return PhoneDisplayState(original: source, target: target, targetX: x, targetY: y, bootSession: boot,
                                 capturedAtUptime: ProcessInfo.processInfo.systemUptime)
    }

    func disable(files: PhoneDisplayFiles) throws {
        try Self.withDisplayLock {
            guard isFromCurrentBoot else { throw PhoneDisplayError.staleSnapshot }
            let age = ProcessInfo.processInfo.systemUptime - capturedAtUptime
            // A delayed switch must expire before the recovery process wakes.
            guard (0..<6).contains(age) else { throw PhoneDisplayError.staleSnapshot }
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: files.ready.path),
                  fileManager.fileExists(atPath: files.record.path),
                  !fileManager.fileExists(atPath: files.restore.path) else { throw PhoneDisplayError.notArmed }
            let current = try Self.capture(source: original, target: target)
            guard current.targetX == targetX, current.targetY == targetY else {
                throw PhoneDisplayError.unexpectedDisplays
            }
            guard let setEnabled = Self.setEnabled else { throw PhoneDisplayError.unavailable }
            try Self.transaction { setEnabled($0, original, false) }
        }
    }

    func restore() throws {
        try Self.withDisplayLock {
            guard isFromCurrentBoot else { throw PhoneDisplayError.staleSnapshot }
            var lastError: Error = PhoneDisplayError.unexpectedDisplays
            for attempt in 0..<12 {
                do {
                    try restoreOnce()
                    return
                } catch {
                    lastError = error
                    if attempt < 11 { Thread.sleep(forTimeInterval: 0.5) }
                }
            }
            throw lastError
        }
    }

    private func restoreOnce() throws {
        guard let setEnabled = Self.setEnabled else { throw PhoneDisplayError.unavailable }
        if !originalIsActive {
            try Self.transaction { setEnabled($0, original, true) }
        }
        guard originalIsActive else { throw PhoneDisplayError.unexpectedDisplays }
        let displays = Screens.online() ?? []
        let targetOnline = displays.contains(target) && CGDisplayVendorNumber(target) == ScreenSpec.vendorID
        let savedOrigin = CGPoint(x: Int(targetX), y: Int(targetY))
        if CGMainDisplayID() != original || (targetOnline && CGDisplayBounds(target).origin != savedOrigin) {
            try Self.transaction { config in
                let primary = CGConfigureDisplayOrigin(config, original, 0, 0)
                guard primary == .success, targetOnline else { return primary }
                return CGConfigureDisplayOrigin(config, target, targetX, targetY)
            }
        }
        guard originalIsActive, CGMainDisplayID() == original else {
            throw PhoneDisplayError.unexpectedDisplays
        }
    }

    private typealias DisplayEnable = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private static let setEnabled: DisplayEnable? = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                          "CGSConfigureDisplayEnabled")
        .map { unsafeBitCast($0, to: DisplayEnable.self) }

    private static func transaction(_ stage: (CGDisplayConfigRef?) -> CGError) throws {
        var configuration: CGDisplayConfigRef?
        let started = CGBeginDisplayConfiguration(&configuration)
        guard started == .success else { throw PhoneDisplayError.transaction(started) }
        let staged = stage(configuration)
        guard staged == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw PhoneDisplayError.transaction(staged)
        }
        let committed = CGCompleteDisplayConfiguration(configuration, .forSession)
        guard committed == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw PhoneDisplayError.transaction(committed)
        }
    }

    private static func currentBootSession() -> String? {
        var length = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0, (2...128).contains(length) else { return nil }
        var bytes = [CChar](repeating: 0, count: length)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func withDisplayLock(_ operation: () throws -> Void) throws {
        let lock = FileManager.default.temporaryDirectory.appendingPathComponent("uumm-display-control.lock")
        let fd = open(lock.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw PhoneDisplayError.lock(errno) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw PhoneDisplayError.lock(errno) }
        }
        defer { flock(fd, LOCK_UN) }
        try operation()
    }
}

struct PhoneDisplayFiles {
    let directory: URL
    init(_ directory: URL) { self.directory = directory }

    static func recoveryRoot(paths: SnugPaths) -> URL {
        paths.dataDirectory.appendingPathComponent("phone-display-recovery", isDirectory: true)
    }

    var record: URL { directory.appendingPathComponent("display.json") }
    var ready: URL { directory.appendingPathComponent("ready") }
    var restore: URL { directory.appendingPathComponent("restore") }

    func load() throws -> PhoneDisplayState {
        try JSONDecoder().decode(PhoneDisplayState.self, from: Data(contentsOf: record))
    }
}

private enum PhoneDisplayError: Error {
    case unexpectedDisplays
    case unavailable
    case staleSnapshot
    case notArmed
    case transaction(CGError)
    case lock(Int32)
}

/// App-private, short-lived commands. The watchdog is established before any transaction disables an output.
enum PhoneAutoSwitchWorker: String {
    case apply = "--uumm-apply-phone-display"
    case watch = "--uumm-watch-phone-display"
    case recoverAbandoned = "--uumm-recover-phone-display"

    static func run(arguments: [String]) -> Int32? {
        guard let name = arguments.first, let mode = Self(rawValue: name) else { return nil }
        guard arguments.count == 2, arguments[1].hasPrefix("/") else { return 2 }
        let root = PhoneDisplayFiles.recoveryRoot(paths: .standard).resolvingSymlinksInPath()
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).resolvingSymlinksInPath()
        if mode == .recoverAbandoned {
            guard directory.path == root.path else { return 2 }
        } else {
            guard isAttempt(directory, in: root) else { return 2 }
        }
        do {
            switch mode {
            case .apply:
                try apply(PhoneDisplayFiles(directory))
            case .watch:
                _ = setsid()
                try watch(PhoneDisplayFiles(directory))
            case .recoverAbandoned:
                try recoverAbandoned(in: directory)
            }
            return 0
        } catch {
            Log.error("手机切屏：执行 \(mode.rawValue) 失败：\(error)")
            return 1
        }
    }

    private static func isAttempt(_ directory: URL, in root: URL) -> Bool {
        UUID(uuidString: directory.lastPathComponent) != nil
            && directory.deletingLastPathComponent().path == root.path
    }

    private static func apply(_ files: PhoneDisplayFiles) throws {
        // Release the transaction lock even if the desktop app exited and the display API stalls.
        let timeout = DispatchWorkItem { _exit(EXIT_FAILURE) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.5, execute: timeout)
        defer { timeout.cancel() }
        try files.load().disable(files: files)
    }

    private static func watch(_ files: PhoneDisplayFiles) throws {
        let saved = try files.load()
        guard saved.isFromCurrentBoot else { throw PhoneDisplayError.staleSnapshot }
        let deadline = ContinuousClock.now + .seconds(8)
        try Data().write(to: files.ready, options: .withoutOverwriting)
        while ContinuousClock.now < deadline && !FileManager.default.fileExists(atPath: files.restore.path) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try saved.restore()
        try FileManager.default.removeItem(at: files.directory)
    }

    private static func recoverAbandoned(in directory: URL) throws {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
        for entry in entries where isAttempt(entry.resolvingSymlinksInPath(), in: directory) {
            let files = PhoneDisplayFiles(entry)
            if let created = try entry.resourceValues(forKeys: [.creationDateKey]).creationDate {
                let untilWatchdog = 14 - Date().timeIntervalSince(created)
                if (0...14).contains(untilWatchdog) { Thread.sleep(forTimeInterval: untilWatchdog) }
            }
            guard fileManager.fileExists(atPath: entry.path) else { continue }
            if fileManager.fileExists(atPath: files.record.path) {
                let saved = try files.load()
                if saved.isFromCurrentBoot { try saved.restore() }
            }
            try fileManager.removeItem(at: entry)
        }
    }
}
