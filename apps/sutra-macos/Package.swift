// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SutraMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SutraMac", targets: ["SutraMac"])
    ],
    targets: [
        .executableTarget(
            name: "SutraMac",
            path: "Sources/SutraMac"
        )
    ]
)
