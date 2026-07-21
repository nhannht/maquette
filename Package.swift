// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "maquette",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MaquetteKit",
            path: "Sources/MaquetteKit",
            resources: [.copy("Resources")]),
        .executableTarget(
            name: "MaquetteApp",
            dependencies: ["MaquetteKit"],
            path: "Sources/MaquetteApp"),
        .executableTarget(
            name: "maquette-cli",
            dependencies: ["MaquetteKit"],
            path: "Sources/maquette-cli"),
        .testTarget(
            name: "MaquetteKitTests",
            dependencies: ["MaquetteKit"],
            path: "Tests/MaquetteKitTests")
    ]
)
