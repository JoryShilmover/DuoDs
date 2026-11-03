# DuoDS

DuoDS is a native iOS Nintendo DS emulator prototype built for standard iPhones and folding displays. It pairs a SwiftUI app with the [melonDS DS](https://github.com/JesseTG/melonds-ds) core and uses [DualPane](https://github.com/JoryShilmover/DualPane) to arrange the two game screens around display cutouts and folding regions.

The app runs games you provide. It does not include or download games. The core uses its built-in FreeBIOS by default.

## Project status

DuoDS is a work-in-progress prototype, not an App Store release. Gameplay, audio, touch input, and saves have been tested on an iPhone 15 Pro Max. Layout changes have been exercised in the iPhone Duo simulator. Performance and usability on a physical folding device remain untested, and game compatibility needs broader testing. See the [validation report](docs/poc/REPORT.md) for measured results and open gaps.

## What it does

- Imports `.nds` files from Files and displays game titles and icons when cartridge banner data is available.
- Presents both DS screens with Metal and adapts their placement to standard and folding display layouts.
- Supports lower-screen touch, on-screen buttons, and configurable control size, opacity, and handedness.
- Provides in-game saves, manual and automatic save states, and save backup import and export.
- Includes fast-forward, microphone input, and extended gamepad support. Some of these controls still need more device testing.

The emulator runs in interpreter mode without just-in-time (JIT) compilation. A narrow C++ bridge hosts the core; Swift manages the app, layouts, input, audio, and persistence.

## Build and run

You need macOS, Xcode with an iOS SDK and simulator, Python 3, and Git. The last documented build used Xcode 27.1 beta. To test folding layouts, use an Xcode version that includes the iPhone Duo simulator.

From a fresh clone:

```sh
./scripts/bootstrap-tools.sh
./scripts/build-poc.sh --diagnostic --configuration Debug
./scripts/test-poc.sh
```

The bootstrap script installs pinned CMake and Ninja versions in `build/tools`. The build script fetches pinned core dependencies, builds the static emulator core, generates the Xcode project, and builds the app. `--diagnostic` includes a small, locally authored test program so you can inspect the emulator without supplying a game.

To launch the diagnostic build on a booted iPhone simulator:

```sh
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/DuoDS.app
xcrun simctl launch booted org.duods.prototype --diagnostic
```

To build for an iPhone, sign in to Xcode with your Apple development team, then replace the placeholders with your team ID and device identifier:

```sh
./scripts/build-poc.sh --sdk iphoneos --team YOUR_TEAM_ID --destination "id=YOUR_DEVICE_UDID"
```

The build script creates `build/DerivedData/Build/Products/Release-iphoneos/DuoDS.app`. Device installation and signing depend on your Xcode account and device setup.

## Repository layout

- `App/` contains the SwiftUI app, library, settings, and scene handling.
- `Emulator/` contains the melonDS bridge, emulation runtime, audio, input, and persistence code.
- `Features/` and `Platform/` contain the play interface and display adaptation.
- `Shared/` contains models shared with the Swift package tests.
- `Tests/` contains logic and native bridge tests.
- `Dependencies/` pins upstream revisions, the core patch, and license notices.
- `scripts/` contains dependency, build, test, and diagnostic tools.

## License

DuoDS is licensed under [GPL-3.0-or-later](LICENSE). The integrated emulator core has the same license. Third-party license notices are in [`Dependencies/Notices/`](Dependencies/Notices/) and [`Dependencies/CORE-NOTICES.txt`](Dependencies/CORE-NOTICES.txt). The diagnostic test program is [MIT licensed](Fixtures/Diagnostic/LICENSE).
