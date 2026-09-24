// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DuoDS", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "DuoLogic", targets: ["DuoLogic"])], targets: [
    .target(name: "DuoLogic", path: ".", exclude: ["App", "Emulator/CoreBridge", "Emulator/Runtime", "Emulator/Video", "Emulator/Audio", "Features/PlaySession", "docs", "scripts", "Dependencies", "Tests", "build", "artifacts", "README.md"], sources: ["Shared", "Emulator/Input", "Emulator/Persistence", "Platform/DisplayEnvironment", "Features/Library"]),
    .testTarget(name: "LogicTests", dependencies: ["DuoLogic"], path: "Tests/LogicTests")
])
