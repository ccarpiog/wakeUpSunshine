// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WakeUpSunshine",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WakeUpSunshine", targets: ["WakeUpSunshine"]), .library(name: "WakeCore", targets: ["WakeCore"])],
    targets: [
        .target(name: "WakeCore"),
        .executableTarget(name: "WakeUpSunshine", dependencies: ["WakeCore"]),
        .testTarget(name: "WakeCoreTests", dependencies: ["WakeCore"]),
        .testTarget(name: "WakeAppTests", dependencies: ["WakeUpSunshine", "WakeCore"])
    ]
)
