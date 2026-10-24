// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PackFitSchemas",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PackFitSchemas", targets: ["PackFitSchemas"]),
    ],
    targets: [
        // Resources/fixtures is a symlink to schemas/fixtures. `.process` resolves it and
        // flattens the files into the bundle (`.copy` would copy the dangling link).
        .target(name: "PackFitSchemas", resources: [.process("Resources")]),
        .testTarget(name: "PackFitSchemasTests", dependencies: ["PackFitSchemas"]),
    ]
)
