// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Astra",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Astra", targets: ["Astra"])],
    targets: [
        .target(name: "AstraCore"),
        .executableTarget(name: "Astra", dependencies: ["AstraCore"], resources: [.process("Resources")]),
        .executableTarget(name: "AstraCoreTests", dependencies: ["AstraCore"], path: "Tests/AstraCoreTests")
    ]
)
