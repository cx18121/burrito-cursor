// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BurritoCursor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BurritoCursor", targets: ["BurritoCursor"]),
        .library(name: "BurritoCursorCore", targets: ["BurritoCursorCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BurritoCursor",
            dependencies: [
                "BurritoCursorCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .target(name: "BurritoCursorCore"),
        .testTarget(
            name: "BurritoCursorCoreTests",
            dependencies: ["BurritoCursorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
