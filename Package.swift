// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeoTube",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "LeoTube", targets: ["LeoTube"]),
        .executable(name: "ytm-probe", targets: ["ytm-probe"]),
    ],
    targets: [
        .target(
            name: "YTMusicKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LeoTube",
            dependencies: ["YTMusicKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ytm-probe",
            dependencies: ["YTMusicKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
