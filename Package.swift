// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NaturalScrollingAuto",
    platforms: [
        .macOS(.v13) // SMAppService (login item API) requires macOS 13+
    ],
    targets: [
        .executableTarget(
            name: "NaturalScrollingAuto",
            path: "Sources/NaturalScrollingAuto",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
