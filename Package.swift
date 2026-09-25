// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import PackageDescription
let package = Package(name: "DuoDS", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "DuoLogic", targets: ["DuoLogic"])], dependencies: [
    // Screen layout solver, extracted from this project. 0.x minor releases may break the API.
    .package(url: "https://github.com/JoryShilmover/DualPane.git", .upToNextMinor(from: "0.1.0")),
], targets: [
    .target(name: "DuoLogic", dependencies: [.product(name: "DualPaneCore", package: "DualPane")], path: ".", exclude: ["App", "Emulator/CoreBridge", "Emulator/Runtime", "Emulator/Video", "Emulator/Audio", "Features/PlaySession", "docs", "scripts", "Dependencies", "Tests", "build", "artifacts", "README.md"], sources: ["Shared", "Emulator/Input", "Emulator/Persistence", "Platform/DisplayEnvironment", "Features/Library"]),
    .testTarget(name: "LogicTests", dependencies: ["DuoLogic", .product(name: "DualPaneCore", package: "DualPane")], path: "Tests/LogicTests")
])
