// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "BurnRate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "burnrate", targets: ["BurnRate"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BurnRate",
            dependencies: [],
            path: "Sources/BurnRate",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/BurnRate/Resources/Info.plist"
                ])
            ]
        )
    ]
)
