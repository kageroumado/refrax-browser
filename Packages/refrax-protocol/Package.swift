// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "refrax-protocol",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RefraxProtocol", targets: ["RefraxProtocol"]),
    ],
    targets: [
        .target(name: "RefraxProtocol"),
    ],
)
