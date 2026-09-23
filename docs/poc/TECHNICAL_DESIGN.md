# Duo DS proof of concept: technical design and execution handoff

## Outcome and proof standard

Build a native iOS frontend that runs a user supplied Nintendo DS homebrew ROM through a pinned emulator core. On an open iPhone Duo, render both DS views within the **same inner display**, place them clear of the hinge and camera regions, and accept lower-screen touch alongside buttons. The proof is a playable, audible, resumable session on an actual Duo, with evidence from an integrated Duo simulator first. A synthetic layout or fake core validates plumbing only; it cannot establish emulation, SDK integration, timing, or device performance.

This is a plan, not an implementation. Contracts below are proposed behavior, not compiled SDK signatures. At execution, verify all Apple beta API names, availability, signatures, and device behavior against the installed SDK and Apple documentation. Record the tested SDK build, core commit, device and OS builds in the final evidence.

## Known basis and open assumptions

* **Documented:** Apple lists a 7.6-inch inner folding display and a separate outer display for iPhone Duo. [Apple specifications](https://www.apple.com/iphone-duo/specs/)
* **Documented:** UIKit exposes a public hinge interaction concept. Apple's guidance favors reserved division/occlusion regions for layout and hinge data for interactions; the fold's division region changes with posture. Confirm the specific beta API surface in the installed SDK. [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction), [adaptive layout talk](https://developer.apple.com/videos/play/tech-talks/111463/), [multiple displays and scenes talk](https://developer.apple.com/videos/play/tech-talks/111464/)
* **Documented:** Duo supports changing window geometry and multiple app scenes on its inner display. Camera capture accessories are tied to camera workflows and are outside this design. [Multiple displays and scenes talk](https://developer.apple.com/videos/play/tech-talks/111464/)
* **Documented candidate:** [JesseTG/melonds-ds](https://github.com/JesseTG/melonds-ds) is a libretro DS core, incorporates standalone melonDS, advertises microphone support through a libretro extension, and carries GPL-3.0 licensing. Its README also notes that some homebrew save data uses a virtual SD image and that homebrew save states are unsupported. These claims do not establish successful iOS linking, all frontend callbacks, touch behavior, or acceptable speed.
* **Observed local preflight (handoff input):** Xcode 27.0 build 27A266a with iOS/iOS Simulator 27.0 SDKs is active; `cmake` and `ninja` are absent from `PATH`. A sandbox block on CoreSimulator inspection is not evidence that the Duo runtime is absent. Repeat environment checks in the execution environment.

The POC is Nintendo DS mode only. It includes no ROM/BIOS catalog or downloads, no cloud sync, netplay, DSi/3DS, custom hardware, JIT, private API, camera accessory workaround, or release-distribution work. Local device signing is required for physical testing. Use legally supplied homebrew ROMs and user supplied system files if the selected core needs them. Do not commit ROMs, BIOS, saves, or licensed binaries to this repository.

## Core choice and decision gate

Start with a **pinned commit** of `JesseTG/melonds-ds`, linked into the app through a minimal native libretro host. Record commit SHA, submodule/dependency revisions, licenses, build options, and how source notices will accompany any later distribution. For the POC, set DS mode and software rendering and disable optional networking. First prove a reproducible arm64 iOS build and a ROM boot on an existing physical iPhone before treating Duo layout as an emulator issue. The host should implement only the libretro services actually requested by this pinned build; unknown environment commands should be logged and rejected safely when permitted by the protocol. Audit mandatory video, audio, input, paths, variables, pixel format, geometry changes, and persistence behavior from the pinned source and upstream libretro API. Do not assume desktop builds or dynamic core packaging apply to iOS.

Fallback to direct upstream melonDS integration only after documenting a concrete blocker in the libretro path: a required feature the pinned core cannot provide, an iOS build failure that cannot be resolved within the POC, or an unfixable video/input contract mismatch. The fallback must preserve the app-facing runtime interfaces below and receive a separate licensing/build review. Do not switch cores solely for theoretical performance gains.

## Architecture and ownership

The app has one `EmulationSession` owner at a time. Swift owns navigation, scene policy, persistence coordination, and display layout. A narrow C ABI hides C++ and the core from Swift. One dedicated serial emulation executor owns every core lifecycle call, `run` invocation, state operation, and core option mutation. Main-thread view updates never call the core directly. Audio output reads a bounded ring buffer, and the renderer consumes immutable frame snapshots; neither blocks the core executor. The runtime is the only component allowed to advance emulated time.

| Path | Responsibility / proposed contract |
| --- | --- |
| `App/` | App and scene entry, dependency wiring, lifecycle dispatch. Route each scene event to the session coordinator. |
| `Emulator/CoreBridge/` | Pinned core build, C ABI shim, libretro host callbacks, capability/geometry discovery. Surface typed `boot`, `runFrame`, `pause`, `flushSave`, `serialize`, `unserialize`, `stop` results; no Swift-visible core globals. |
| `Emulator/Runtime/` | Session state machine (`idle`, `loading`, `running`, `paused`, `stopping`, `failed`), serial executor, frame pacing, input snapshots, teardown and background time budget. |
| `Emulator/Video/` | Software-frame buffer ownership, pixel format conversion if required, bounded latest-frame mailbox, Metal upload/compositing. Maintain two source rectangles derived from actual core output geometry. |
| `Emulator/Audio/` | Core audio callback capture, bounded PCM ring buffer, output format adaptation and interruption handling. Return silence on underrun and discard stale samples on overrun. |
| `Emulator/Input/` | Merge virtual controls, hardware controller and lower-screen pointer into one per-frame snapshot. Track button press counts/sources to avoid one source releasing another. |
| `Emulator/Persistence/` | Per-game save directories, atomic save writes, versioned save-state metadata, import ownership and corruption recovery. |
| `Platform/DisplayEnvironment/` | Isolated Apple SDK adapter reporting window bounds, safe area, reserved division/occlusion rectangles and optional hinge state in one coordinate space. Provide a fake adapter for tests. No inferred geometry from pixel dimensions or a hard-coded fold line. |
| `Features/PlaySession/` | Metal canvas, layout solver, on-screen controls, pause/explicit emulated lid action, status and error UI. |
| `Features/Library/` | Local document import and list of user supplied ROMs; start/stop session. No catalog. |

Proposed dependency direction: `App` composes `Features` and `Emulator`; `PlaySession` consumes immutable frames and geometry from `Video`/`DisplayEnvironment`; `Input` consumes the same solved lower-screen destination rectangle; only `Runtime` talks to `CoreBridge`. Keep platform beta symbols inside `DisplayEnvironment` so fake geometry and core tests can proceed on the installed baseline without pretending that a fake passes real Duo integration.

## Frame, sound, and input contracts

At boot, query the chosen core's reported audio/video information and geometry. Use its frame rate and sample rate for pacing rather than a guessed DS constant. The core callback may deliver a **composed** image, not separate screen images. Verify the pinned core's layout option and actual callback dimensions, orientation, row pitch, pixel format, and screen rectangles with a diagnostic frame before cropping. Select a deterministic two-screen layout in the core; if its output has spacing or borders, capture those source rectangles from that verified layout. Reject geometry that cannot identify both complete screens. On geometry change, atomically publish updated source rectangles and destination layout. The Metal renderer samples the two subrectangles into independent quads on one drawable; preserve aspect ratio and avoid stretching or clipping. A bounded mailbox may drop superseded *video* frames when the GPU lags; it must not cause the core to run faster or drop emulation steps.

Let audio consumption guide the long-term pacing target, with monotonic clock checks and bounded catch-up. Do not run one core frame per display refresh: Duo's display refresh is independent of the core's reported rate. Keep a small audio lead; measure underruns, overruns, emulated-frame cadence, and presentation drops. When audio is interrupted, pause or safely mute according to an explicit policy and prevent uncontrolled run-ahead. Avoid blocking the real-time audio callback on locks, allocation, disk I/O, or core calls. Tune buffer duration only with device measurements.

Pointer mapping must use the **rendered lower-screen destination rectangle**. Convert a contact from view coordinates into normalized lower-screen coordinates, reject contacts outside the rectangle, then map into the core's verified native touchscreen coordinate convention, including rotation, crop, and any libretro pointer range translation. Capture and test that convention against the pinned core; nominal DS touchscreen size alone is insufficient to infer a libretro input range. Clamp only after deciding whether the contact is inside. Preserve one active stylus contact with stable identity; other touches can hold virtual buttons simultaneously. On cancellation, scene loss, or resize, release the stylus and all transient buttons so input cannot stick. Controller connect/disconnect changes only that source's buttons; virtual buttons remain live. Offer visible controls for D-pad, A/B/X/Y, L/R, Start/Select and an explicit **emulated DS lid** toggle if supported by the core. A physical fold changes layout/scene visibility; it must not automatically signal the DS lid. Test a game's input-dependent action to prove button and touch delivery, not merely overlay taps.

Microphone support may follow the first playable slice but is required for final scope validation. Provide a user-controlled microphone enable action; do not assume the host can detect when a game needs a microphone. Request iOS permission on that action, implement the specific libretro extension from the pinned core, and provide a predictable silence/denied state. Denial must not block boot, crash, or masquerade as permission granted. Record whether microphone-driven gameplay was actually tested; do not claim it from a simulated callback.

## Display and lifecycle behavior

With the inner display active, solve layout from current scene bounds, safe areas, and active reserved regions. Flat posture can stack both DS screens with controls in remaining space. When an active division region splits a partially folded inner display, place one whole DS screen in each usable region if both meet a measured minimum legibility size; put controls where reachable without covering either screen. If space is inadequate, prefer an explicit compact fallback with both screens still visible over clipping. Camera occlusion remains clear. Recompute destination rectangles on bounds, safe area, reserved region, orientation, and scene changes; the running session and core state remain the same across resize. The initial layout is a proposal; verify reachability, reading size, and rotation on the Duo simulator and device.

Treat scene visibility independently of app process lifetime. One foreground scene owns the active emulation session; a second scene may show the library or a read-only message but cannot run another core or race the save directory. Define deterministic transfer/denial if another scene requests play. When the owner resigns active, pause input and core, flush persistent save data where supported, and quiesce audio. On reactivation, rebuild render/audio resources as needed and resume the same session after geometry refresh. On background, perform best-effort bounded save/flush work and record completion; iOS can terminate without a close callback, so progress must also be persisted at explicit pause/checkpoints. On process restart, load the last **persistent game save** by default, never silently restore a potentially incompatible save state. Closing the inner display pauses if the owner scene disappears. When the system presents the app on the outer display, offer compact two-screen play or the user's selected pause/library behavior, retaining the same session where possible. This does not require simultaneous use of both physical displays.

Persistent SRAM/flash or core-managed per-game save files are authoritative game progress. Isolate by stable ROM identity and write atomically through the host's save/storage contract. Validate user imports, avoid path traversal, and keep source ROM read-only. Manual save states are required for content the pinned core can serialize, with a versioned envelope containing core commit/version, ROM identity, format version and checksums; explicitly show them unavailable for unsupported content. Refuse incompatible or corrupt states with an explanation and leave persistent saves intact. Inspect the chosen core's actual save interfaces, including homebrew virtual SD behavior; do not equate serialization support with reliable homebrew progress. Follow V20's fixture requirement; homebrew-only testing cannot prove supported serialization.

## Execution sequence and gates

**G0 — environment, source and legal inputs.** Inspect project structure and local instructions; record Xcode/SDK/runtime availability without interpreting a sandbox error as absent software. Inventory the Duo SDK symbols and simulator as G2 prerequisites; their absence does not prevent a baseline G0 pass. Pin the core and its dependencies. Review GPL-3.0 and transitive licenses, obtain approved test fixtures and any needed system files, and prove a reproducible baseline iOS build. Record missing devices against the relevant physical gate and missing lawful content against G0. Follow [VALIDATION.md](VALIDATION.md) for gate status.

**G1 — real core on an existing physical iPhone.** Build the pinned software renderer into a minimal libretro host and boot the test ROM. Capture actual video geometry and pixel format, hear audio, prove stylus/button input, and persist/reload game save data. Log frame and audio metrics. This gate separates core/host feasibility from foldable layout.

**G2 — integrated Duo simulator.** Add the SDK display adapter and Metal two-quad composition. Show both screens in one inner-display scene, clear of reported reserved regions in flat/part-folded layouts. Exercise live resize, scene focus changes, simultaneous button and touch, controller disconnect, audio interruption, and save reload. A fake region fixture remains a unit-test input, not G2 evidence.

**G3 — real Duo.** Run the sustained 2D/3D workload sessions and separate posture/lifecycle trials defined in [VALIDATION.md](VALIDATION.md). That document is authoritative for duration and numeric targets; do not mix deliberate interruptions into sustained performance windows. Confirm screen visibility, touch targeting, frame/audio stability, no stuck inputs, resume in the same session where the OS keeps it alive, and saved progress after a forced process restart. Capture screenshots/video plus device logs and metrics. If hardware is unavailable, explicitly report G3 unverified; do not claim the POC complete.

**G4 — handoff.** Deliver source and build steps, pinned revisions/license notices, a short architecture note matching the implemented interfaces, test and device evidence, performance table, and a list of remaining compatibility gaps. State which gates passed, failed, or could not be run.

## Tests and acceptance evidence

| Test owner / suggested test | Meaningful assertion | Gate |
| --- | --- | --- |
| `Platform/DisplayEnvironment/DisplayEnvironmentTests` | Fake flat, division, occlusion and resized windows produce non-overlapping, fully visible screen rectangles; adapter integration reports real regions. | G2/G3 |
| `Emulator/Input/TouchMappingTests` | Corners/center/outside bounds, rotation, crop and live resize map to the verified core input range; concurrent touch and button holds remain independent; cancellation releases input. | G1/G2 |
| `Emulator/Runtime/SessionLifecycleTests` | One core owner; pause/resume/stop transitions run in serial; background/scene loss releases input; second scene cannot start a competing session. | G2 |
| `Emulator/Persistence/SavePersistenceTests` | Persistent save survives restart, atomic write failure keeps previous data, corrupt/mismatched save state is refused without harming game save. | G1/G2 |
| `Emulator/Video/FrameGeometryTests` | Representative recorded core frames yield correct top/bottom source crops and safe updates on geometry change; stale frames are discarded without advancing core time. | G1/G2 |
| `Emulator/Audio/AudioBufferTests` | Underrun is silent, overrun bounded, route interruption cannot block callback; measured real output has no recurring dropout. | G1/G3 |

Collect a dated evidence matrix: core commit/build log; ROM title/hash (do not publish ROM); core-reported AV data and screen geometry; phone/simulator/Duo model and OS build; flat/partial/closed screenshots; touch target recording; measured emulated-frame cadence, display drops, audio underruns/overruns and memory for the validation intervals; lifecycle and save-restart result. Separate automated fixture results, integrated simulator results, and physical-device observations. A passing compiler and synthetic test suite alone are insufficient.

## Decisions to resolve during execution

1. Confirm the exact pinned core options and source rectangles for a composed two-screen software frame, and whether its iOS build requires tools missing from the current `PATH`.
2. Confirm libretro touch and lid controls and microphone extension against that source revision. Lid support is a hard selection criterion for the full POC. If absent, record the blocker and evaluate the defined upstream fallback or report no-go after bounded investigation; a disabled control is an honest temporary UI, not a V16 pass. Never synthesize lid input from physical hinge motion in this POC.
3. Choose the smallest legible layout and control placement from actual Duo simulator/device observations; record measured thresholds instead of hard-coding guessed hinge or screen dimensions.
4. Validate manual save states after persistent save proof using approved serialization-capable content. They are not a prerequisite for G1 and never replace in-game saves; missing lawful content blocks V20 rather than silently waiving it.

## Primary references

* [Apple iPhone Duo technical specifications](https://www.apple.com/iphone-duo/specs/)
* [Apple UIHingeInteraction documentation](https://developer.apple.com/documentation/uikit/uihingeinteraction)
* [Apple: Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
* [Apple: Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
* [JesseTG/melonds-ds source and README](https://github.com/JesseTG/melonds-ds)
