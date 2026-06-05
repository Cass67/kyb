// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KyB",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KyB", targets: ["KyB"]),
    ],
    targets: [
        .executableTarget(
            name: "KyB",
            path: "Sources/KyB",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
