// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SutraIOS",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SutraIOS", targets: ["SutraIOS"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SutraIOS",
            dependencies: [],
            path: "Sources/SutraIOS"
        )
    ]
)
