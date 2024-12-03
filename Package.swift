// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CallKit",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "CallKit",
            targets: ["FlutterCallkitIncomingPluginPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", branch: "main")
    ],
    targets: [
        .target(
            name: "FlutterCallkitIncomingPluginPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/FlutterCallkitIncomingPluginPlugin"),
        .testTarget(
            name: "FlutterCallkitIncomingPluginPluginTests",
            dependencies: ["FlutterCallkitIncomingPluginPlugin"],
            path: "ios/Tests/FlutterCallkitIncomingPluginPluginTests")
    ]
)