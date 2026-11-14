// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HookMeUp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "hook-me-up", targets: ["hook-me-up"]),
        .executable(name: "hook-me-up-setup", targets: ["hook-me-up-setup"]),
        .executable(name: "HookMeUp", targets: ["HookMeUp"]),
    ],
    targets: [
        .target(name: "HookMeUpCore"),
        .target(name: "HookMeUpIPC", dependencies: ["HookMeUpCore"]),
        .target(name: "HookKit", dependencies: ["HookMeUpCore", "HookMeUpIPC"]),
        .target(name: "AgentKit", dependencies: ["HookMeUpCore", "HookMeUpIPC"]),
        .target(name: "SetupKit", dependencies: ["HookMeUpCore"]),
        .target(name: "DoctorKit", dependencies: ["HookMeUpCore", "HookMeUpIPC", "SetupKit"]),
        .executableTarget(name: "hook-me-up", dependencies: ["HookKit"]),
        .executableTarget(name: "hook-me-up-setup", dependencies: ["SetupKit", "DoctorKit", "HookMeUpCore"]),
        // AppKit and UserNotifications adapters only; the logic lives in AgentKit.
        .executableTarget(name: "HookMeUp", dependencies: ["AgentKit", "HookMeUpCore", "HookMeUpIPC"]),
        .testTarget(name: "HookMeUpCoreTests", dependencies: ["HookMeUpCore"]),
        .testTarget(name: "HookMeUpIPCTests", dependencies: ["HookMeUpIPC", "HookMeUpCore"]),
        .testTarget(name: "HookKitTests", dependencies: ["HookKit", "HookMeUpIPC", "HookMeUpCore"]),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit", "HookMeUpCore"]),
        .testTarget(name: "SetupKitTests", dependencies: ["SetupKit", "HookMeUpCore"]),
        .testTarget(name: "DoctorKitTests", dependencies: ["DoctorKit", "HookMeUpCore", "HookMeUpIPC"]),
        .testTarget(name: "HookMeUpTests", dependencies: ["HookMeUp", "HookMeUpCore"]),
    ]
)
