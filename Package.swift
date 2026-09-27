// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HumanRAM",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HumanRAMShared",
            path: "Sources/HumanRAMShared"
        ),
        .target(
            name: "HumanRAMCore",
            dependencies: ["HumanRAMShared"],
            path: "Sources/HumanRAMCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        .executableTarget(
            name: "HumanRAM",
            dependencies: ["HumanRAMCore", "HumanRAMShared"],
            path: "Sources/HumanRAM",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        .executableTarget(
            name: "HumanRAMWidget",
            dependencies: ["HumanRAMShared"],
            path: "Sources/HumanRAMWidget",
            linkerSettings: [
                .linkedFramework("WidgetKit"),
            ]
        ),
        .testTarget(
            name: "HumanRAMTests",
            dependencies: ["HumanRAMCore"],
            path: "Tests/HumanRAMTests"
        )
    ]
)
