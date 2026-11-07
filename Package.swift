// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "healthandeye",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v14)],
    products: [
        .library(name: "HealthAndICore", targets: ["HealthAndICore"]),
    ],
    targets: [
        .target(name: "HealthAndICore", path: "Sources/HealthAndICore"),
        .testTarget(name: "HealthAndICoreTests", dependencies: ["HealthAndICore"], path: "Tests/HealthAndICoreTests"),
    ]
)
