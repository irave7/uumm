// 「关于 uumm」集中显示版本、项目链接与上游致谢。
import AppKit
import SwiftUI
import SnugCore

struct AboutView: View {
    private struct Credit: Identifiable {
        let name, url, author, usage: String
        var id: String { name }
    }

    private let credits = [
        Credit(name: "Snug", url: "https://github.com/zephyr4123/snug",
               author: "zephyr4123", usage: "上游项目"),
        Credit(name: "UUyc-companion", url: "https://github.com/aoyamashou/UUyc-companion",
               author: "AoyamaShou", usage: "Snug 的前身"),
        Credit(name: "PermissionFlow", url: "https://github.com/jaywcjlove/PermissionFlow",
               author: "小弟调调（jaywcjlove）", usage: "授权引导"),
        Credit(name: "Better Remote", url: "https://github.com/pincc-debug/better-remote",
               author: "pincc-debug", usage: "单指滚动思路"),
        Credit(name: "FreeDisplay", url: "https://github.com/huberdf/FreeDisplay",
               author: "huberdf", usage: "虚拟屏接口声明"),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("uumm").font(.title2.bold())
                            Text(Updater.current?.description ?? "开发版").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text("为 UU 远程连接提供屏幕、触控和滚轮设置")
                        Link("GitHub 发布页", destination: URL(string: "https://github.com/irave7/uumm/releases")!)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(credits) { c in
                    LabeledContent {
                        Text(c.usage).foregroundStyle(.secondary)
                    } label: {
                        HStack(spacing: 4) {
                            Link(c.name, destination: URL(string: c.url)!)
                            Text("· \(c.author)").foregroundStyle(.secondary)
                        }
                    }
                }
                Text("社区 PR 作者：bubble、gencheng liu、Rongzheng Liu").foregroundStyle(.secondary)
            } header: {
                Text("致谢（MIT 许可）")
            } footer: {
                Text("非 UU远程 官方软件").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: MacTokens.Size.aboutWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    /// display：从哪块屏的菜单栏打开的（见 NSWindow.bring）
    func show(on display: DisplayID? = nil, activating: Bool = true) {
        if window == nil {
            // 先定尺寸再居中（NSWindow(hosting:)），否则按 0×0 居中，窗口偏到右下
            let w = NSWindow(hosting: AboutView(), title: "关于 uumm")
            w.titlebarAppearsTransparent = true
            window = w
        }
        window?.bring(to: display)
        window?.present(activating: activating)
    }
}
