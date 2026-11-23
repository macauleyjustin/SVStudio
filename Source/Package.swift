// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SVStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SatellaCore", targets: ["SatellaCore"]),
        .library(name: "SatellaRender", targets: ["SatellaRender"]),
        .executable(name: "svstudio-tool", targets: ["SatellaTool"]),
        .executable(name: "SVStudio", targets: ["SatellaApp"]),
        .executable(name: "satella-tests", targets: ["SatellaTestRunner"])
    ],
    targets: [
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "SatellaCore",
            dependencies: ["CZlib"],
            path: "Sources/SatellaCore"
        ),
        .target(
            name: "SatellaRender",
            dependencies: ["SatellaCore"],
            path: "Sources/SatellaRender"
        ),
        .executableTarget(
            name: "SatellaTool",
            dependencies: ["SatellaCore", "SatellaRender"],
            path: "Sources/SatellaTool"
        ),
        .executableTarget(
            name: "SatellaApp",
            dependencies: ["SatellaCore", "SatellaRender"],
            path: "Sources/SatellaApp"
        ),
        .executableTarget(
            name: "SatellaTestRunner",
            dependencies: ["SatellaCore", "SatellaRender"],
            path: "Sources/SatellaTestRunner"
        )
    ]
)
