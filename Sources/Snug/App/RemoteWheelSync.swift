import AppKit
import CoreGraphics
import Darwin
import SnugCore

/// 只同步 UU 注入的纵向滚轮。手势生成的滚动事件、实体设备和横向滚轮照常通过。
@MainActor
final class RemoteWheelSync {
    private var session: WheelSyncSession?

    func update(enabled: Bool) {
        if enabled, session == nil {
            let next = WheelSyncSession()
            next.start()
            session = next
        } else if !enabled, let session {
            session.stop()
            self.session = nil
        }
    }
}

/// 和 TouchTap 一样在自己的线程处理事件，避免建屏和恢复窗口拖慢系统输入。
private final class WheelSyncSession: @unchecked Sendable {
    private let config = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/linearmouse/linearmouse.json")
    private let permittedPaths: Set<String> = {
        let applications = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return Set(applications.map {
            $0.appendingPathComponent("UURemote.app/Contents/Helpers/UURemoteServer").resolvingSymlinksInPath().path
        })
    }()
    /// start() 同步等线程就绪；之后仅由主线程读取。
    private var runLoop: CFRunLoop?

    // 这些状态只在监听线程读写。
    private var inputTap: CFMachPort?
    private var outputTap: CFMachPort?
    private var timer: CFRunLoopTimer?
    private var linearMouseTaps = Set<UInt32>()
    private var pending: [WheelEventID: WheelInput] = [:]
    private var profile: LinearMouseWheelProfile?
    private var lastConfigData: Data?
    private var macUsesNaturalScrolling = true
    private var reportedTapFailure = false

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()
            runLoop = loop
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 1, 0, 0) { [self] _ in
                refresh()
            }
            self.timer = timer
            CFRunLoopAddTimer(loop, timer, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "uumm.uu-wheel-sync"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            if let timer { CFRunLoopTimerInvalidate(timer) }
            timer = nil
            removeTaps()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func refresh() {
        readProfile()
        guard profile != nil else {
            removeTaps()
            return
        }
        macUsesNaturalScrolling = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let currentTaps = getLinearMouseTaps()
        if let inputTap, currentTaps != linearMouseTaps {
            // LinearMouse 的监听重开后可能跑到最前面；移回它前面，才能记下 UU 传来的方向。
            CFMachPortInvalidate(inputTap)
            self.inputTap = nil
            pending.removeAll(keepingCapacity: true)
        }
        linearMouseTaps = currentTaps
        if outputTap == nil { outputTap = makeTap(.cgSessionEventTap, callback: Self.apply) }
        if inputTap == nil, outputTap != nil {
            inputTap = makeTap(.cghidEventTap, callback: Self.capture)
        }
        let installed = outputTap != nil && inputTap != nil
        if !installed, !reportedTapFailure {
            Log.warn("UU 滚轮同步的事件监听未能开启，将重试")
        }
        reportedTapFailure = !installed
    }

    private func readProfile() {
        let data = try? Data(contentsOf: config)
        guard data != lastConfigData else { return }
        lastConfigData = data
        profile = nil
        guard let data else { return }
        do { profile = try LinearMouseWheelProfile(contents: data) }
        catch { Log.warn("读取 LinearMouse 滚轮设置失败，暂时停用 UU 滚轮同步") }
    }

    private func removeTaps() {
        if let inputTap { CFMachPortInvalidate(inputTap) }
        if let outputTap { CFMachPortInvalidate(outputTap) }
        inputTap = nil
        outputTap = nil
        pending.removeAll(keepingCapacity: true)
    }

    private func getLinearMouseTaps() -> Set<UInt32> {
        let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.lujjjh.LinearMouse")
        guard !processes.isEmpty else { return [] }
        let pids = Set(processes.map(\.processIdentifier))
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return linearMouseTaps }
        var taps = Array(repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(UInt32(taps.count), &taps, &count) == .success else { return linearMouseTaps }
        return Set(taps.prefix(Int(count)).compactMap {
            $0.tapPoint == .cghidEventTap && pids.contains($0.tappingProcess) ? $0.eventTapID : nil
        })
    }

    private func makeTap(_ location: CGEventTapLocation, callback: CGEventTapCallBack) -> CFMachPort? {
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        return port
    }

    private static let capture: CGEventTapCallBack = { _, type, event, context in
        if let context {
            let sync = Unmanaged<WheelSyncSession>.fromOpaque(context).takeUnretainedValue()
            if type == .scrollWheel { sync.remember(event) }
            else { sync.reenable(sync.inputTap, after: type) }
        }
        return Unmanaged.passUnretained(event)
    }

    private static let apply: CGEventTapCallBack = { _, type, event, context in
        if let context {
            let sync = Unmanaged<WheelSyncSession>.fromOpaque(context).takeUnretainedValue()
            if type == .scrollWheel { sync.normalize(event) }
            else { sync.reenable(sync.outputTap, after: type) }
        }
        return Unmanaged.passUnretained(event)
    }

    private func reenable(_ tap: CFMachPort?, after type: CGEventType) {
        if let tap, type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func remember(_ event: CGEvent) {
        let id = WheelEventID(event)
        guard let profile, isUURemoteServer(id.pid),
              let input = WheelInput(event: event, profile: profile, macUsesNaturalScrolling: macUsesNaturalScrolling) else { return }
        if pending.count >= 256 { pending.removeAll(keepingCapacity: true) }
        pending[id] = input
    }

    private func normalize(_ event: CGEvent) {
        pending.removeValue(forKey: WheelEventID(event))?.apply(to: event)
    }

    private func isUURemoteServer(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        var buffer = [CChar](repeating: 0, count: 4096)
        let size = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard size > 0 else { return false }
        return permittedPaths.contains(String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self))
    }
}

private struct WheelEventID: Hashable {
    let pid: pid_t
    let time: CGEventTimestamp

    init(_ event: CGEvent) {
        pid = pid_t(clamping: event.getIntegerValueField(.eventSourceUnixProcessID))
        time = event.timestamp
    }
}

private struct WheelInput {
    let sign: Double
    let lines: Int64?

    init?(event: CGEvent, profile: LinearMouseWheelProfile, macUsesNaturalScrolling: Bool) {
        let delta = event.verticalDelta
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0, delta.isFinite, delta != 0 else {
            return nil
        }
        let hasHorizontal = [CGEventField.scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2,
                             .scrollWheelEventDeltaAxis2].contains { event.getDoubleValueField($0) != 0 }
        sign = profile.direction(for: delta, macUsesNaturalScrolling: macUsesNaturalScrolling)
        lines = hasHorizontal ? nil : profile.verticalLines
    }

    func apply(to event: CGEvent) {
        if let lines {
            // 写入行数时 Quartz 会同步更新连续滚动字段。斜向事件不改成按行滚动。
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(sign) * lines)
        } else if event.verticalDelta * sign < 0 {
            let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line == .min ? .max : -line)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -point)
        }
    }
}

private extension CGEvent {
    var verticalDelta: Double {
        for field in [CGEventField.scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1,
                      .scrollWheelEventDeltaAxis1] {
            let delta = getDoubleValueField(field)
            if delta != 0 { return delta }
        }
        return 0
    }
}
