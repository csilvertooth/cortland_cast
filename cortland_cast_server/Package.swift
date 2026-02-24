// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CortlandCastServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Vapor web framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
    ],
    targets: [
        // Core server logic
        .target(
            name: "CortlandCastServerCore",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        // macOS GUI app
        .executableTarget(
            name: "CortlandCastServer",
            dependencies: [
                "CortlandCastServerCore"
            ]
        )
    ]
)
