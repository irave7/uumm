// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uumm",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "uumm", targets: ["Snug"]),
        .executable(name: "snug-release", targets: ["SnugRelease"]),
    ],
    dependencies: [
        // 权限引导：打开系统设置隐私页 + 拖拽授权悬浮面板（MIT，内置副本见 Vendor/PermissionFlow/VENDORED.md）
        .package(path: "Vendor/PermissionFlow"),
    ],
    targets: [
        // 纯逻辑：远控适配层的端口与会话判定、屏幕调度（ScreenPlan、ScreenSet、DeskSet、Desk）、手势翻译、持久化、日志、启动参数。
        // 只依赖 Foundation（含 os.Logger）和 CoreGraphics 的几何类型，不碰 AppKit、不调系统接口，全部可以用假的系统能力测试。
        // 不认识任何一家远控：SnugCore、SnugSystem 都不依赖 Remote* 目标
        .target(name: "SnugCore"),
        // 私有 API（CGVirtualDisplay）头文件
        .target(name: "CGVirtualDisplayBridge"),
        // 系统层：建屏撤屏、切模式、设主屏、搬窗口、发按键、事件监听、截图。实现 SnugCore 定义的系统能力
        .target(name: "SnugSystem", dependencies: ["SnugCore", "CGVirtualDisplayBridge"]),
        // 远控适配器，每家两个目标：Logic 是纯逻辑（只依赖 SnugCore，可以单独测），System 调系统、实现 RemoteAdapter。
        // 接一家新的远控照 UU 的样子加两个目标和一个测试目标，再在 Snug/App/Remotes.swift 登记（见 docs/remotes/README.md）
        // UU远程：三路信号怎么认、怎么算在场，推流日志的解析，兼容自检的判定
        .target(name: "RemoteUU", dependencies: ["SnugCore"], path: "Sources/Remotes/UU/Logic"),
        // UU远程：读 UU 的界面（辅助功能）、盯推流日志（log 子进程）、看进程；--dump-remote、--check-remote 的实现
        .target(name: "RemoteUUSystem", dependencies: ["RemoteUU", "SnugCore", "SnugSystem"], path: "Sources/Remotes/UU/System"),
        .executableTarget(
            name: "Snug",
            dependencies: [
                "SnugCore",
                "SnugSystem",
                "RemoteUUSystem",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ]
        ),
        // 发版工具（只由 scripts/snug 调）：打更新包、写 update.json。和 App 共用 SnugCore 里的包格式
        .executableTarget(name: "SnugRelease", dependencies: ["SnugCore"]),
        .testTarget(name: "SnugCoreTests", dependencies: ["SnugCore"]),
        .testTarget(name: "RemoteUUTests", dependencies: ["RemoteUU", "SnugCore"], path: "Tests/Remotes/UU", resources: [.copy("Fixtures")]),
        // 契约测试：每家远控一个驱动，跑同一组断言（接入新远控时的验收清单）
        .testTarget(name: "RemoteContractTests", dependencies: ["SnugCore", "RemoteUU"]),
    ]
)
