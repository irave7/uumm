// 设置窗口：左侧切换屏幕、触控、UU 优化和通用设置，各页读取 AppState，通过 AppIntents 修改设置。
import AppKit
import Observation
import PermissionFlow
import SwiftUI
import SnugCore

// MARK: 屏幕

struct ScreensPage: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation
    /// 打开着的表单：添加屏幕、某块屏的详情（渲染样例用初值）
    @State var sheet: ScreenSheet?
    @State private var explaining = false
    /// 选了要设为主屏、等确认的那块（渲染样例用初值）
    @State var confirmingMain: ScreenID?

    var body: some View {
        Form {
            Section {
                StatusHeader(state: state, navigation: navigation)
                if state.connection == .reconnecting {
                    Button("立即结束本次远程") { intents.endSessionNow() }
                }
                if !state.libraryScreens.isEmpty {
                    Button("App 资源库") { navigation.openLibrary(on: nil) }
                }
            }
            let issues = Issue.all(state, intents)
            if !issues.isEmpty {
                Section { ForEach(issues) { IssueRow(issue: $0) } }
            }
            Section {
                ForEach(state.config.screens) { screen in
                    ScreenRow(screen: screen, watching: state.watchedScreen == screen.id,
                              enabled: Binding(get: { screen.enabled }, set: { intents.setScreenEnabled(screen.id, $0) }),
                              details: { sheet = .detail(screen.id) })
                }
                if state.config.screens.isEmpty {
                    Text("还没有屏幕").foregroundStyle(.secondary)
                }
            } header: {
                Text("虚拟屏幕")
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
                    HStack(spacing: MacTokens.Space.xs) {
                        Text("同一时间只用到一块屏，用不到的可以关掉。").foregroundStyle(.secondary)
                        Button("为什么？") { explaining = true }
                            .buttonStyle(.link)
                            .popover(isPresented: $explaining, arrowEdge: .bottom) { WhyManyScreens() }
                    }
                    .font(.callout)
                    Spacer(minLength: MacTokens.Space.m)
                    Button { sheet = .add } label: { Label("添加屏幕…", systemImage: "plus") }
                        .disabled(state.config.screens.count >= ScreenConfig.limit)
                        .help(state.config.screens.count >= ScreenConfig.limit ? "最多 \(ScreenConfig.limit) 块" : "")
                }
                .padding(.top, MacTokens.Space.xs)
            }
            Section {
                LabeledContent {
                    // 设主屏立即生效、影响本机，先讲清代价再设；改回「不改」不用问
                    Picker("设为主屏", selection: Binding(get: { state.config.mainScreen }, set: { id in
                        if let id, id != state.config.mainScreen { confirmingMain = id } else { intents.setMainScreen(id) }
                    })) {
                        Text("不改").tag(ScreenID?.none)
                        Divider()
                        ForEach(state.config.screens) { Text($0.name).tag(ScreenID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingLabel("设为主屏", detail: "常驻并作为主屏，每次连接直接进入", tile: MacTokens.IconTile.mainScreen)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add: AddScreenSheet(state: state, intents: intents) { self.sheet = nil }
            case .detail(let id): ScreenDetailSheet(id: id, state: state, intents: intents) { self.sheet = nil }
            }
        }
        .confirmationDialog(confirmingMain.flatMap { state.screen($0) }.map { "将「\($0.name)」设为主屏？" } ?? "",
                            isPresented: Binding(get: { confirmingMain != nil }, set: { if !$0 { confirmingMain = nil } })) {
            Button("设为主屏") {
                if let id = confirmingMain { intents.setMainScreen(id) }
                confirmingMain = nil
            }
        } message: {
            Text(MainScreenNotice.detail)
        }
    }
}

/// 设为主屏的代价：设置里确认时讲清楚（README「设为主屏」同一套说法）
enum MainScreenNotice {
    static let detail = """
        此屏将常驻并作为 Mac 的主屏，立即生效；UU远程 每次连接即进入此屏。

        影响：当前主屏上的窗口随即移至此屏；此后程序坞、新窗口、系统提示与锁屏登录框均显示于此屏，本机不可见。适用于未接显示器或仅远程使用的 Mac。

        UU远程 在连接时选定主屏。可随时在 App 资源库、菜单栏或 uumm 的设置中取消。
        """
}

/// 设置窗口上弹出的表单
enum ScreenSheet: Identifiable, Equatable {
    case add
    case detail(ScreenID)

    var id: String {
        switch self {
        case .add: "add"
        case .detail(let id): "detail/\(id.rawValue)"
        }
    }
}

/// 屏幕列表的一行：类别图标、名字、横竖·型号、「在看」、开关、ⓘ
private struct ScreenRow: View {
    let screen: ScreenConfig
    let watching: Bool
    @Binding var enabled: Bool
    let details: () -> Void

    var body: some View {
        HStack(spacing: MacTokens.Space.m) {
            SettingLabel(screen.name, detail: screen.summary, tile: MacTokens.IconTile.screen(symbol: screen.symbol))
            Spacer(minLength: MacTokens.Space.s)
            if watching {
                Label("在看", systemImage: "circle.fill")
                    .labelStyle(WatchingBadge())
            }
            Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
            Button(action: details) { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("详情")
                .accessibilityLabel("\(screen.name) 详情")
        }
    }
}

/// 「在看」：绿点 + 字
private struct WatchingBadge: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: MacTokens.Space.xs) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(MacTokens.Color.positive)
            configuration.title.font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 「为什么？」的气泡：多开的屏留给什么
private struct WhyManyScreens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.m) {
            Text("可以开几块屏").font(.headline)
            Text("UU远程 一次只让一台设备控制。多开的屏留给：").foregroundStyle(.secondary)
            reason("rectangle.portrait.rotate", "横竖切换", "同一台设备横竖各一块，转过来在 UU 里切")
            reason("arrow.left.arrow.right", "换设备", "另一台接管后直接选它的屏，不用改设置")
            Text("关着的屏远程时不建，UU 的屏幕列表也更短。").font(.callout).foregroundStyle(.secondary)
        }
        .padding(MacTokens.Space.l)
        .frame(width: MacTokens.Size.helpPopoverWidth, alignment: .leading)
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
            Image(systemName: symbol).foregroundStyle(MacTokens.Color.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// 顶部：此刻的状态；缺权限时主按钮「授权…」就在这里
private struct StatusHeader: View {
    let state: AppState
    let navigation: any Navigation

    var body: some View {
        let text = StatusText(state)
        HStack(spacing: MacTokens.Space.m) {
            StatusTile(state.accessibilityTrusted ? state.status.tile : MacTokens.IconTile.accessibility)
            VStack(alignment: .leading, spacing: MacTokens.Space.xs) {
                Text(text.headline).font(.headline)
                if let detail = text.detail { Text(detail).foregroundStyle(.secondary) }
            }
            Spacer(minLength: MacTokens.Space.m)
            if !state.accessibilityTrusted {
                Button("授权…") { navigation.openWelcome() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, MacTokens.Space.xs)
    }
}

private struct Issue: Identifiable {
    enum Action {
        case run(String, @MainActor () -> Void)
        /// 缺权限：「授权…」打开系统设置对应的隐私页（见 AuthorizeButton）
        case authorize(PermissionFlowPane)
    }

    let id: String
    let text: StatusText
    let action: Action?

    /// 需要用户处理的问题，和解决它的按钮（有的话）
    @MainActor
    static func all(_ state: AppState, _ intents: any AppIntents) -> [Issue] {
        var list: [Issue] = []
        if state.legacyAppRunning {
            list.append(Issue(id: "legacy", text: StatusText(headline: "旧版远控辅助工具正在运行", detail: "退出旧工具后可使用 uumm"),
                              action: .run("退出旧版", intents.quitLegacyApp)))
        }
        if let issue = state.loginItemIssue {
            list.append(Issue(id: "login", text: issue.text,
                              action: issue == .needsApproval ? .run("前往允许", intents.openLoginItemsSettings) : nil))
        }
        if state.config.screenshot, !state.screenRecordingTrusted {
            list.append(Issue(id: "screen-recording",
                              text: StatusText(headline: "截图需要\(PermissionName.screenRecording)权限", detail: "系统设置 › 隐私与安全性"),
                              action: .authorize(.screenRecording)))
        }
        if state.configSaveFailed {
            list.append(Issue(id: "config", text: StatusText(headline: "设置未保存", detail: "修改未生效，请重试"), action: nil))
        }
        return list
    }
}

/// 一个问题一行：警示图标、出了什么事、去哪里处理，右边是解决它的按钮
private struct IssueRow: View {
    let issue: Issue

    var body: some View {
        LabeledContent {
            switch issue.action {
            case .run(let title, let run): Button(title, action: run)
            case .authorize(let pane): AuthorizeButton(pane: pane)
            case nil: EmptyView()
            }
        } label: {
            HStack(spacing: MacTokens.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MacTokens.Color.warning)
                    .frame(width: MacTokens.Size.iconTile)
                VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                    Text(issue.text.headline)
                    if let detail = issue.text.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

// MARK: 触控

struct TouchPage: View {
    let state: AppState
    let intents: any AppIntents

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { state.config.gestures }, set: { intents.setGestures($0) })) {
                    SettingLabel("触控手势", detail: "单指滚动 · 长按选择 · 长按松开右键", tile: MacTokens.IconTile.gestures)
                }
                LabeledContent {
                    ZoomSlider(steps: Binding(get: { state.config.zoomSteps }, set: { intents.setZoomSteps($0) }))
                } label: {
                    SettingLabel("字号放大", detail: "窗口放上来时默认放大的级数", tile: MacTokens.IconTile.zoom)
                }
                Toggle(isOn: Binding(get: { state.config.screenshot }, set: { intents.setScreenshot($0) })) {
                    SettingLabel("截图", detail: "小横条左侧的相机键 · 截当前窗口到剪贴板", tile: MacTokens.IconTile.screenshot)
                }
            } footer: {
                Text("只作用于手机和平板屏。电脑屏不翻译手势、不放大字号。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// 字号放大：系统「文字大小」那样的带刻度滑块，两端小 A、大 A，每档一格
private struct ZoomSlider: View {
    @Binding var steps: Int

    var body: some View {
        let range = AppConfig.zoomStepsRange
        Slider(value: Binding(get: { Double(steps) }, set: { steps = Int($0.rounded()) }),
               in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
            Text("字号放大")
        } minimumValueLabel: {
            Image(systemName: "textformat.size.smaller")
        } maximumValueLabel: {
            Image(systemName: "textformat.size.larger")
        }
        .labelsHidden()
        .frame(width: MacTokens.Size.zoomSliderWidth)
        .accessibilityValue(steps == 0 ? "不放大" : "+\(steps) 级")
    }
}

// MARK: UU 优化

struct RemoteOptimizationPage: View {
    let state: AppState
    let intents: any AppIntents
    @Binding var phoneName: String

    var body: some View {
        Form {
            Section {
                Toggle("自动切屏", isOn: Binding(get: { state.config.autoSwitchPhone }, set: { intents.setAutoSwitchPhone($0) }))
                LabeledContent("手机在 UU 中的设备名称") {
                    HStack {
                        TextField("设备名称", text: $phoneName)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 174)
                            .onSubmit(savePhoneName)
                        Button("保存", action: savePhoneName)
                            .disabled(phoneName == (state.config.autoSwitchPhoneName ?? "") || phoneName.count > 128)
                    }
                }
                if state.controllers.count == 1, let connected = state.controllers.first, !connected.isEmpty {
                    Button("填入当前控制端名称") { phoneName = connected }
                }
            } header: {
                Text("手机远控")
            } footer: {
                Text("填入 UU「本机被控中」显示的手机全名，启用一块手机竖屏，并将「设为主屏」选为「不改」。确认这台手机后才会创建竖屏。切换时 Mac 原屏可能短暂熄灭。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("同步纵向滚轮", isOn: Binding(get: { state.config.remoteWheelSync }, set: { intents.setRemoteWheelSync($0) }))
            } header: {
                Text("Windows 远控 Mac")
            } footer: {
                Text("读取 Mac 的 LinearMouse 设置，校正 UU 发来的纵向滚轮。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func savePhoneName() {
        intents.setAutoSwitchPhoneName(phoneName)
        phoneName = state.config.autoSwitchPhoneName ?? ""
    }
}

// MARK: 通用

struct GeneralPage: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation

    var body: some View {
        Form {
            Section("启动与显示") {
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { intents.setLaunchAtLogin($0) })) {
                    SettingLabel("开机启动", tile: MacTokens.IconTile.launchAtLogin)
                }
                Toggle(isOn: Binding(get: { state.config.showInMenuBar }, set: { intents.setShowInMenuBar($0) })) {
                    SettingLabel("在菜单栏显示", detail: "隐藏后，从「应用程序」打开 uumm 可重新进入设置。",
                                 symbol: "menubar.rectangle", tint: SettingsWorkspace.accent)
                }
            }
            Section("权限") {
                LabeledContent {
                    if state.accessibilityTrusted { PermissionStatus(granted: true) } else { AuthorizeButton(pane: .accessibility) }
                } label: {
                    SettingLabel.accessibility
                }
                LabeledContent {
                    if state.screenRecordingTrusted { PermissionStatus(granted: true) } else { AuthorizeButton(pane: .screenRecording) }
                } label: {
                    SettingLabel.screenRecording
                }
            }
            Section {
                HStack {
                    Button("关于 uumm") { navigation.openAbout(on: nil) }
                    Link("查看 GitHub 发布版本", destination: URL(string: "https://github.com/irave7/uumm/releases")!)
                    Spacer()
                    Button("退出 uumm") { intents.quit() }
                        .help("还原窗口后退出")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: 窗口

@MainActor @Observable
final class SettingsSelection {
    var tab: SettingsWindowController.Tab

    init(_ tab: SettingsWindowController.Tab = .screens) { self.tab = tab }
}

struct SettingsWorkspace: View {
    private static let sidebarWidth: CGFloat = 154
    static let accent = Color(nsColor: .dynamic(
        light: NSColor(srgbRed: 0.12, green: 0.35, blue: 0.81, alpha: 1),
        dark: NSColor(srgbRed: 0.42, green: 0.65, blue: 1, alpha: 1)
    ))
    private static let sidebarBackground = Color(nsColor: .dynamic(
        light: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.11, green: 0.14, blue: 0.19, alpha: 1)
    ))

    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation
    let selection: SettingsSelection
    @State private var phoneName: String

    init(state: AppState, intents: any AppIntents, navigation: any Navigation, selection: SettingsSelection) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
        self.selection = selection
        _phoneName = State(initialValue: state.config.autoSwitchPhoneName ?? "")
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { Optional(selection.tab) }, set: { tab in
                if let tab { selection.tab = tab }
            })) {
                ForEach(SettingsWindowController.Tab.allCases, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 13, weight: selection.tab == tab ? .semibold : .medium))
                        .padding(.vertical, 5)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 14)
            .frame(width: Self.sidebarWidth)
            .background(Self.sidebarBackground)
            .accessibilityLabel("设置分类")

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selection.tab.title)
                    .font(.system(size: 23, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                switch selection.tab {
                case .screens: ScreensPage(state: state, intents: intents, navigation: navigation)
                case .touch: TouchPage(state: state, intents: intents)
                case .optimization: RemoteOptimizationPage(state: state, intents: intents, phoneName: $phoneName)
                case .general: GeneralPage(state: state, intents: intents, navigation: navigation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Self.accent)
        .frame(width: Self.sidebarWidth + MacTokens.Size.settingsWidth, height: 490)
    }
}

@MainActor
final class SettingsWindowController {
    enum Tab: CaseIterable {
        case screens, touch, optimization, general

        var title: String {
            switch self {
            case .screens: "屏幕"
            case .touch: "触控"
            case .optimization: "UU 优化"
            case .general: "通用"
            }
        }

        var symbol: String {
            switch self {
            case .screens: "rectangle.on.rectangle"
            case .touch: "hand.point.up.left"
            case .optimization: "iphone.gen3"
            case .general: "gearshape"
            }
        }
    }

    private let state: AppState
    private let intents: any AppIntents
    private weak var navigation: (any Navigation)?
    private let selection = SettingsSelection()
    private var window: NSWindow?

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
    }

    /// display：从哪块屏的菜单栏打开的（见 NSWindow.bring）
    func show(_ tab: Tab = .screens, on display: DisplayID? = nil, activating: Bool = true) {
        selection.tab = tab
        if window == nil, let navigation {
            let view = SettingsWorkspace(state: state, intents: intents, navigation: navigation, selection: selection)
            let w = NSWindow(hosting: view, title: "uumm 设置")
            w.styleMask.insert(.miniaturizable)
            window = w
        }
        window?.bring(to: display)
        window?.present(activating: activating)
    }
}
