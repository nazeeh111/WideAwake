// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WideAwake", platforms: [.macOS(.v26)], products: [.executable(name: "WideAwake", targets: ["WideAwake"])], targets: [.executableTarget(name: "WideAwake"), .testTarget(name: "WideAwakeTests", dependencies: ["WideAwake"])])
