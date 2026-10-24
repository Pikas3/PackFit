// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Packer",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Packer", targets: ["Packer"]),
        .executable(name: "GenPlans", targets: ["GenPlans"]),
    ],
    dependencies: [
        .package(path: "../PackFitSchemas"),
    ],
    targets: [
        .target(name: "Packer", dependencies: ["PackFitSchemas"]),
        .executableTarget(name: "GenPlans", dependencies: ["Packer", "PackFitSchemas"]),
        .testTarget(name: "PackerTests", dependencies: ["Packer", "PackFitSchemas"]),
    ]
)
