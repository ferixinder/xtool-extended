// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DistributionValidation",
    platforms: [.iOS(.v17), .watchOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "DistributionValidation", targets: ["DistributionValidation"]),
        .library(name: "DistributionValidationWatch", targets: ["DistributionValidationWatch"]),
        .library(name: "DistributionValidationWidget", targets: ["DistributionValidationWidget"]),
    ],
    targets: [
        .target(name: "DistributionValidation"),
        .target(name: "DistributionValidationWatch"),
        .target(
            name: "DistributionValidationWidget",
            // Keep WidgetBundle.main when xtool uses Foundation's extension entry point.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]
        ),
    ]
)
