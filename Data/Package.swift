// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CriterionData",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CriterionData", targets: ["CriterionData"]),
    ],
    targets: [
        .target(name: "CriterionData"),
        .testTarget(name: "CriterionDataTests", dependencies: ["CriterionData"], exclude: ["Fixtures"]),
    ]
)