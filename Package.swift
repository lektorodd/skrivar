// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Skrivar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Skrivar",
            path: "Sources/Skrivar",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
