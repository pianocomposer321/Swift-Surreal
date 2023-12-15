// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "websocket-test",
    dependencies: [
        .package(url: "https://github.com/vapor/websocket-kit", from: "2.14.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "websocket-test",
            dependencies: [
                .product(name: "WebSocketKit", package: "websocket-kit"),
            ]),
    ]
)
