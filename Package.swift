// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LGClimate",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LGClimate", targets: ["LGClimate"])],
    targets: [
        .executableTarget(name: "LGClimate"),
        .testTarget(name: "LGClimateTests", dependencies: ["LGClimate"])
    ],
    swiftLanguageModes: [.v5]
)
