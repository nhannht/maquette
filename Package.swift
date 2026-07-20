// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "maquette",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../depthcard")
    ],
    targets: [
        .target(
            name: "MaquetteKit",
            dependencies: [.product(name: "DepthCardKit", package: "depthcard")],
            path: "Sources/MaquetteKit"),
        .executableTarget(
            name: "MaquetteApp",
            dependencies: ["MaquetteKit"],
            path: "Sources/MaquetteApp"),
        .testTarget(
            name: "MaquetteKitTests",
            dependencies: ["MaquetteKit"],
            path: "Tests/MaquetteKitTests")
    ]
)
