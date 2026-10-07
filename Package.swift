// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroNotch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PomodoroNotch", targets: ["PomodoroNotch"])],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(name: "PomodoroNotch", dependencies: ["PomodoroCore"]),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"])
    ]
)
