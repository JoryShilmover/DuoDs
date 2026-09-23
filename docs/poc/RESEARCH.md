# Research baseline and prerequisites

Date: September 23, 2026. Sources were inspected during the feasibility investigation. This document records evidence provenance; it is not a build or performance certification. Re-open the decisive sources and check installed SDK declarations at the start of execution.

## Confidence labels

- **Observed locally:** A command was run in the planning workspace; its scope is stated below.
- **Documented:** A primary source describes a capability. No implementation or device test was performed here.
- **Proposed:** A design choice or acceptance target for the POC.
- **Unverified:** Requires toolchain access, compilation, hardware, legal review, or measurement.

## Source register

| ID | Primary source | Finding used by the plan | Limit / execution action |
| --- | --- | --- | --- |
| S1 | [Apple Duo announcement](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) | Documented announcement September 9, 2026; availability October 23 | Recheck shipping status; this session has no target device |
| S2 | [Apple Duo specifications](https://www.apple.com/iphone-duo/specs/) | Documented 7.6-inch inner display, 1878 × 2670 pixels, A20 Pro, Pencil USB-C support | Do not derive app layout from physical pixel constants; use scene geometry and regions |
| S3 | [Prepare your app for Duo](https://developer.apple.com/videos/play/tech-talks/111461/) | Documented Xcode/iOS 27.1 beta preparation and simulator support | Installed toolchain here is older; validate runtime availability and exact deployment requirements |
| S4 | [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction) | Documented public beta hinge observation | Verify availability/signatures in the chosen SDK; no handwritten private-API fallback |
| S5 | [Adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/) | Documented fold division and occlusion regions for layout | Account for inactive fold regions when flat; verify actual coordinates under rotation and multitasking |
| S6 | [Multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/) | Hinge observations and geometry have different roles; camera accessory has camera-session conditions | No assumption of unrestricted simultaneous inner/outer gameplay; retain one emulator session across scenes |
| S7 | [melonDS DS repository](https://github.com/JesseTG/melonds-ds) | Documented iOS arm64 support and libretro frontend integration | Pin a source revision; verify interpreter, software renderer, and simulator build; listed support is not our build proof |
| S8 | [melonDS DS docs](https://docs.libretro.com/library/melonds_ds/) | Documented saves/states, layout/input features, and optional DS BIOS/firmware | Built-in replacements are not an all-games compatibility guarantee; avoid DSi scope |
| S9 | [Upstream melonDS](https://github.com/melonDS-emu/melonDS) | GPLv3-or-later; firmware boot needs original system dumps | Audit selected code and dependencies; direct integration is a fallback, not a parallel second emulator |
| S10 | [Delta App Store listing](https://apps.apple.com/us/app/delta-game-emulator/id1048524688) | Existing iOS DS emulator precedent | Does not establish performance, approval, or licensing compliance for this new app |
| S11 | [Delta source](https://github.com/rileytestut/Delta) | AGPLv3 app; useful iOS integration reference | Do not casually copy application code; retain provenance and evaluate obligations if reused |
| S12 | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Retro emulator allowance in 4.7; public APIs/self-contained app requirements in 2.5; rights in 5.2 | Future distribution needs its own review; do not include unauthorized ROMs/firmware/artwork |

## Local preflight

Read-only checks were performed on September 23, 2026:

| Check | Observed result | Interpretation |
| --- | --- | --- |
| Workspace listing | Empty before these docs were created; no repository-local `AGENTS.md` or `.codex/orchestrate.md` found | Execution must recheck for new project instructions and work |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` | Selected developer directory only |
| `xcodebuild -version` | Xcode 27.0, build 27A266a | Does not establish Duo SDK support |
| `xcodebuild -showsdks` | iOS 27.0 and iOS Simulator 27.0 among listed SDKs | Required newer beta SDK not present in this selected installation's listing |
| `xcrun simctl list runtimes` | Failed with CoreSimulatorService connection/access errors; log access reported `Operation not permitted` | Runtime inventory is unknown; do not report runtimes as missing |
| `git --version` | 2.39.0 | Git executable available; workspace is not yet an initialized repository |
| `command -v rg` | `/opt/homebrew/bin/rg` | Text search tool available |
| `command -v cmake`, `command -v ninja` | No path returned | Not on the current PATH; not proof they are absent elsewhere |

No dependencies were downloaded, no SDK installed, no devices paired, no credentials inspected, no app compiled, and no game run. The simulator check was not retried with elevated permissions because runtime access is not needed to author this plan.

## Assumptions that must not become hidden dependencies

1. **Device access:** An existing physical iPhone may allow an early performance check; a Duo is still required for the final claim. If neither is accessible, only simulator/host milestones can pass.
2. **Public APIs:** Beta names and signatures can change. Source-check and compile the adapter before describing it as implemented. Read-only source research cannot substitute for compilation.
3. **No JIT:** The chosen core must expose a working interpreter configuration. An app that requires debugger-assisted executable memory has not met the POC premise.
4. **Graphics:** Metal presentation of software-rendered frames does not mean the emulator's 3D renderer is Metal-accelerated. Keep these performance costs separate.
5. **Licenses:** Open-source availability is not permission to ignore GPL/AGPL obligations or third-party rights. Preserve notices and corresponding-source information. A proprietary-only requirement changes feasibility and must be resolved explicitly.
6. **Assets:** Use redistributable homebrew or user-provided software with appropriate rights. Do not fetch commercial ROMs, BIOS, or keys. A cartridge ownership claim is not a substitute for determining permitted acquisition and use.
7. **Ergonomics:** Pencil support and a physical hinge do not prove that the chosen game/control layout is comfortable. Human testing is required.
8. **Lifecycle:** A final hinge or background callback is not guaranteed before termination. Save integrity must not rely on receiving one.

## Decisions still needed during execution

These do not block documentation or all engineering work: exact source commit; actual SDK and simulator; minimum supported OS; available physical devices; test corpus; signing access; source-distribution model; and final control placement. Record them in `DECISIONS.md` as they are resolved. Ask the user only for facts/access that cannot be established independently, and continue unaffected packages.
