# POC validation: native DS on iPhone Duo

This is the execution and decision record for the proof of concept described in [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) and [EXECUTION_PLAN.md](EXECUTION_PLAN.md). It tests a bundled, no-JIT melonDS DS core behind a native iOS frontend. It is a feasibility gate, not a product release checklist. **No device performance, Duo behavior, or battery result has been measured by this document.** The executor must enter actual observations and evidence before assigning a pass.

## Rules of evidence

- At execution time, verify current upstream core revision, supported iOS build path, libretro API behavior, dependency and license obligations, Apple's current SDK/Device Hub instructions, and availability of a physical Duo. Record URLs, retrieval dates, commit hashes, SDK/build versions, and any change to this plan. The starting references are [melonDS DS upstream](https://github.com/JesseTG/melonds-ds), [libretro core documentation](https://docs.libretro.com/library/melonds_ds/), and [Apple's Duo preparation talk](https://developer.apple.com/videos/play/tech-talks/111461/). These references are leads, not a substitute for inspection of the pinned source and installed toolchain.
- Status is **Pass** only when the specified observation and evidence exist, **Fail** when an executed check violates its criterion, **Blocked** when an external prerequisite prevents execution, and **Not run** when the team has not attempted it. A simulator, synthetic geometry harness, other iPhone, or desktop build cannot satisfy a physical-Duo row. Mark every row, including unavailable cases.
- Use release-like iOS entitlements and compilation settings for all performance evidence: bundled interpreter/software execution only, no JIT, no downloaded executable code, no debugger, no performance overrides. Record the signed binary's entitlements and build settings plus runtime evidence that the JIT path is disabled. A debug-only run may aid diagnosis but cannot pass G1 or G3.
- Keep fixtures lawful. The minimum corpus is redistributable or locally authored DS homebrew covering 2D motion, 3D motion, stylus coordinates, audio, save writes, microphone and lid behavior where possible. Document authorship/license and SHA-256. A user-supplied lawfully held commercial corpus may add compatibility coverage; log identifiers and checksums privately, never check ROMs, BIOS, firmware, NAND, save data, microphone recordings, or secrets into the repository. Do not download unlicensed assets. Scope DS mode first; DSi requires separate assets and a separate decision.
- Do not call an exploratory result a benchmark. Run measurements on the exact target hardware under stated conditions. Keep raw traces as well as summaries; a screen recording alone cannot establish emulation speed.

Record a fixture capability manifest at P0: ID, provenance/license, SHA-256, storage type (cartridge save or homebrew SD), supported serialization, input/audio/mic/lid coverage, and which rows it satisfies. The documented core does not support homebrew save states. For V20's supported round trip, obtain serialization-capable content through the user with appropriate rights or an authorized rights-holder distribution and inspect actual core support. Missing approved content blocks V20 while other work continues; unsupported homebrew behavior alone cannot pass that row. Cartridge-save checks likewise require a cartridge-save-capable fixture rather than treating homebrew SD persistence as equivalent. G1 can demonstrate either supported persistent-save mechanism, explicitly named; G3 must cover the implemented storage mechanisms separately.

## Run directory and reproducibility

Create `artifacts/poc/<run-id>/` for each attempt, where `<run-id>` is an ISO date/time plus a short build identifier. Keep `manifest.json`, `report.md`, `logs/`, `metrics/`, and redacted screenshots or video in that directory. The manifest records: operator, UTC time, source/core commits and patches, binary hash, bundle ID, Xcode/iOS/SDK/Device Hub versions, signing/profile type, hardware model and identifier class (no serial number), storage/battery state, power source, ambient conditions, graphics/core options, fixture IDs and SHA-256, and evidence paths. Log each run's start/end wall time and monotonic timestamps. Sanitise paths and metadata before sharing; keep private corpus mapping outside the repository. Add `artifacts/poc/` to ignore rules when a repository exists; the report may link to a private evidence archive instead of committing raw artifacts.

Record the core's `retro_get_system_av_info` FPS and sample rate after content/options load and whenever they change. Call this value **core target rate**; never assume a fixed 60 Hz or use display refresh as emulation speed. Instrument completed emulated frames/core callbacks, unique video frames submitted, presentation timestamps, duplicated/dropped presentation frames, audio produced/consumed/underruns, input timestamps, save operations, app/scene state, and thermal/power samples on one monotonic clock. Compute emulation speed as emulated frames divided by elapsed active seconds and the target rate; separately compute presentation cadence and unique-frame ratio. Exclude explicitly logged pause/background intervals from active emulation time, not unexplained stalls. Native baseline renders two 256×192 DS screens at the core's native internal resolution, with any upscaling recorded separately.

## Gate sequence and bounded exit criteria

The numbers below are **proposed project acceptance targets**, not measured facts or claims about the device. They prioritize playable full-speed behavior and avoid hiding sustained slowdown behind an average. If a target proves unsuitable, record the reason and approve a revised criterion *before* using it for a gate decision.

| Gate | Required work and observation | Exit decision |
| --- | --- | --- |
| G0 — toolchain, source, rights | Pin the core and dependencies; inspect licenses and distribution obligations, including GPLv3 source/notice strategy; confirm baseline iOS build inputs, local signing, no-JIT settings and fixture rights. Inventory Duo SDK/runtime access separately as a G2 prerequisite. Capture a build/configuration manifest. | Pass when the pinned source builds for the baseline iOS target and obligations/assets are documented. Missing Duo SDK/runtime alone blocks G2, not this baseline gate. A baseline tool or license question is Blocked/Fail as appropriate; it never silently passes. Other offline work may continue. |
| G1 — no-JIT core spike on a current physical iPhone | Load a legal homebrew fixture through the bundled core in a release-like signed app; show both native screens, responsive buttons/stylus, advancing audio, an ordinary in-game save and reload. Inspect binary/runtime for forbidden JIT/dependency behavior and capture a short frame/audio trace. | Pass on a physical current iPhone with all functions observed and no JIT. This proves integration viability only; it does not establish Duo performance. |
| G2 — Duo layout and lifecycle | In the actual Duo simulator, exercise open/closed/folded poses, both scene locations, rotation, safe areas/hinge, touches and resumed content. Use a synthetic scene/geometry harness if the simulator is unavailable, labeling its rows partial. | Pass only with Duo simulator evidence for the pose/layout rows and no critical lifecycle defect. A synthetic harness can support design work, never complete G2. |
| G3 — physical Duo performance and handling | Run the matrix below on physical Duo, using a release-like build and native internal rendering. Capture 30-minute 2D and 3D sessions, input/audio/thermal/power traces, fold and lifecycle trials, and an ergonomics observation. | Pass only when all G3 must-pass rows meet targets on physical Duo. Missing device gives Blocked, not Pass. |
| G4 — handoff | Reproduce from a clean checkout or documented clean extraction of a hashed source snapshot when Git is unavailable; deliver pinned source/patches, build instructions, matrix, raw and summarized evidence, open defects, license/assets decisions, and a dated reviewer decision. | Pass when an independent agent/operator follows the instructions and audits each gate result without private content in the repository. A human is still required for the hands-on checks. |

Known preflight on 2026-09-23: the selected local Xcode is 27.0 (27A266a), and `xcodebuild -showsdks` exposed iOS/Simulator 27.0. `cmake` and `ninja` were absent from `PATH`. The local `simctl list runtimes` call failed on CoreSimulator access under the sandbox, so it does **not** establish that the Duo runtime is absent. Recheck outside that restriction. Apple's cited talk describes Xcode 27.1 and Device Hub Duo controls; do not mark Duo-specific G0/G2 checks passed from the current preflight. Continue source review, fixture preparation, architecture work and synthetic layout checks while the toolchain/hardware is unavailable.

## Minimum validation matrix

Each row gets a case ID, device/build/fixture, steps, expected/actual result, status, defect ID, and evidence path. Do not collapse failures into a single “works” statement. “Must pass” means the row is required for the corresponding full gate; an unavailable capability is Blocked. Run lifecycle tests at least three times per pose/transition; repeat longer tests after a material core, renderer, or scheduler change.

| ID / gate | Procedure and observable project target | Evidence |
| --- | --- | --- |
| V01 / G0 | Clean signed build from pinned source; verify source notices, binary linkage/entitlements, no JIT permission or dynamic executable download, fixture licenses. | Build log, hashes, entitlement/config dump, license inventory. |
| V02 / G1 | Boot authored 2D fixture on physical current iPhone; visible two screens, button and stylus response, sound, ordinary save survives quit/relaunch. | Short video, event/audio log, save checksum before/after. |
| V03 / G1 | Record core-reported AV rate and compare frame counter to wall time over five active minutes; log presentation separately. No speed target here beyond clearly advancing playable state. | Raw counters with formula and interval. |
| V04 / G2 | Duo simulator: open inner display, closed outer display, half-fold and return, supported rotations; 20 changes per route. No clipped DS pixels/controls, hinge or reserved-region overlap, stale scene, wrong touch target, or lost session. | Pose screenshots/video, scene/safe-area/coordinate logs. |
| V05 / G2 | During continuous held stylus contact, fold/rotate/resize and release. Touch maps only to the intended lower DS screen; a geometry change cancels/remaps safely, with no stuck touch. Test custom layout override and return to automatic layout. | Input-coordinate trace, video, selected layout state. |
| V06 / G2 | Open another app/window or scene, return, and move presentation between available Duo scenes. Exactly one emulation session and one save writer; no duplicated audio/core ticks. | Scene/session identity and callback counters. |
| V07 / G3 | Physical Duo, 30 minutes of representative 2D gameplay at native internal rendering after five-minute warmup; active emulation speed ≥98% of core target for each subsequent 5-minute window, and no unexplained continuous interval >3 seconds below 95%. | Per-second counters, five-minute aggregates, frame/presentation trace. |
| V08 / G3 | Repeat V07 with representative 3D workload and same thresholds; record renderer/core options. | Same metrics plus option manifest. |
| V09 / G3 | In V07/V08, measure unique presentation frames, duplicate frames and dropped presentations. Target ≥95% of core-produced frames presented uniquely during active foreground play; diagnose any divergence despite passing emulation speed. Display refresh is recorded separately. | Frame IDs/timestamps and plotted cadence. |
| V10 / G3 | With instrumentation on device, tap targets at corners/center of the lower screen in each pose. Compare actual view-space contact coordinates with independently calculated expected DS coordinates: mapping error ≤1 DS pixel, not human finger-placement error. Require no upper-screen stylus injection and contact-event-to-core-consumption latency p95 ≤100 ms for 100 taps. This is not optical touch-to-photon latency; report that separately if measured. | Contact coordinates, transformed coordinates, independently computed reference, core-consumption timestamps, and method. |
| V11 / G3 | 30-minute audio capture during each workload: count underruns and listen at start, midpoint, and end. Target zero sustained crackle/gaps; ≤1 isolated underrun per 10 minutes and no audible interruption >100 ms during active play. Note route changes separately. | Audio callback counters, redacted waveform/listener notes. |
| V12 / G3 | Record thermal state and energy samples throughout V07/V08, initial and last 10-minute emulation speed. No serious/critical thermal state, no thermal shutdown, last 10-minute speed ≥95% of first steady 10 minutes while still meeting V07/V08. Record observed battery change or Energy Log with brightness, radios, power source and ambient temperature; **no battery-life percentage is promised**. | Thermal/energy trace and test conditions. |
| V13 / G3 | Save two distinct fixtures; verify separate per-content save directories/identities, normal quit/relaunch, and migration/open with a changed app build. Use an atomic write or backup scheme, validate data integrity after an interrupted write, and state the actual recovery limit. Do not assume iOS grants a final background callback. | Save hashes, file layout, interruption sequence, restore log. |
| V14 / G3 | Background/foreground, lock/unlock, low-memory termination, incoming call/audio interruption, and cold restart. Pause/resume promptly, no duplicate session, corrupt save or permanently stuck audio; state restoration is best effort where iOS kills the process. | Lifecycle timestamps and save/audio trace. |
| V15 / G3 | Deny microphone permission, grant it, then revoke in Settings; test fixture microphone input and safe fallback when denied. No crash, silent capture without consent, or stuck emulated microphone state. | Permission state and core input trace; no raw voice retained. |
| V16 / G3 | Exercise explicit DS lid close/open emulation in every pose; distinguish device fold from the intentional in-game command. No lid input from physical folding in this POC. Confirm lid capability at core selection; a disabled/unsupported control does not pass. | Input event and game-state trace. |
| V17 / G3 | Connect/use/disconnect a controller mid-game; on disconnect, virtual controls remain usable and no button remains held. Reconnect mapping and onscreen layout remain coherent. | Input logs and video. |
| V18 / G3 | One user minimum, a second preferred: 15-minute hands-on trial in each of flat-inner, horizontal partially folded-inner, and compact outer-display play. Record reachability of stylus target, hinge occlusion, screen legibility, control comfort, and layout override use. No blocker prevents completing the fixture task in a required pose. Record Pencil and touch-only separately when available; controller cannot substitute for a required touch-only trial. Missing Pencil access leaves Pencil-specific claims unverified, not ordinary touch functionality. | Short structured observations, anonymized; user count and accessory availability. |
| V19 / G4 | Fresh checkout (or documented clean archive extraction) rebuild and repeat V02 and one G2 pose by an independent agent/operator using handoff instructions, with all evidence links resolving. Keep build/dependency caches separate enough to expose undeclared inputs. | Reproduction log, source revision/archive hash, and reviewer signoff. |
| V20 / G2 and G3 | On content for which the core supports serialization, manually save state, advance, restore, and observe the earlier state. Reject wrong-ROM, corrupted, and incompatible-core snapshots without changing cartridge saves. Separately exercise unsupported homebrew serialization with an explicit unavailable state. Test deterministic storage failures in host tests, then validate supported round-trip on device. | State metadata/round-trip log, battery-save hashes, corruption/version rejection tests. |

The rate and latency targets are provisional feasibility limits. A 2% sustained speed deficit allows small scheduling noise while still exposing perceptible under-speed; a 5% presentation gap and isolated audio underrun allowance avoid treating a single system interruption as a core failure. The thresholds must be evaluated from raw per-interval data, not just a 30-minute average. A test app's own logging should be profiled so it does not materially change results. If instrumentation overhead exceeds 2% speed in an A/B check, use a lower-overhead trace and report both conditions.

Only add narrow automated tests where deterministic logic warrants them: DS-to-view coordinate transforms across representative aspect ratios/hinge bounds, save-key separation and atomic file replacement, one-session ownership, and frame metric calculations. Manual simulator and physical-device checks remain required for fold behavior, audio, thermal performance and comfort. Do not manufacture a green gate by substituting unit tests for unavailable hardware.

## Defects and decision

Severity: **S0** legal/security/privacy violation or data loss; **S1** crash, broken core input/audio/save, persistent under-speed, or unusable required pose; **S2** material but recoverable layout/latency/comfort issue; **S3** cosmetic or isolated issue with no gameplay effect. Record reproduction steps, build/fixture, frequency, evidence and owner. Any open S0/S1 fails the affected gate. S2 requires an explicit documented workaround and acceptance; S3 may remain open.

Use the following release-independent decision vocabulary:

- **NO-GO:** after bounded remediation, an executed must-pass criterion still fails, an S0/S1 remains, a confirmed rights incompatibility blocks the intended use, or evidence contradicts no-JIT viability. Name the failing gate and next experiment. Missing rights information is Blocked, not proof of incompatibility.
- **CONDITIONAL GO (engineering continuation only):** G0/G1 evidence supports a viable no-JIT build and no known S0/S1, but G2 and/or G3 is Blocked or partial because Duo simulator, toolchain, physical hardware, or approved target-validation fixtures are unavailable. Continue bounded independent work; never describe incomplete evidence as full Duo validation.
- **GO (POC feasibility):** G0–G4 pass, every must-pass matrix row has auditable evidence, no open S0/S1, physical Duo sustained tests pass, and reviewer signs the measured power/ergonomics assessment. This does not assert App Store approval or broad game compatibility.

If G0 or G1 is blocked/not run and no decisive failure is established, report **assessment pending** with the blockers rather than forcing a feasibility verdict. Conditional GO requires the baseline physical-iPhone evidence above. A reduced-scope result must name its exclusions and cannot pass the original matrix by quietly omitting a row.

### Report template (`artifacts/poc/<run-id>/report.md`)

```markdown
# POC run <run-id>
Date/operator/reviewer:
Core commit and license review:         App commit and binary hash:
Xcode/SDK/iOS/Device Hub:               Device model and physical/simulator:
Build/entitlement/no-JIT evidence:      Fixture IDs, rights, SHA-256:
Native rendering/options and core AV rate:
Conditions: brightness, power, ambient, audio route, controller, storage, thermal start

| Gate | Status: Pass/Fail/Blocked/Not run | Evidence | Defect/blocker |
| G0 | | | |
| G1 | | | |
| G2 | | | |
| G3 | | | |
| G4 | | | |

| Case ID | Device/fixture | Status | Actual versus target | Evidence | Defect |
| --- | --- | --- | --- | --- | --- |

30-minute 2D/3D: core target FPS; per-window emulation speed; unique presentation ratio;
duplicate/dropped frames; audio underruns; thermal states; observed energy/battery conditions.
Lifecycle/save/pose observations and recovery limits:
Open defects (severity, owner, workaround):
Source/SDK assumptions rechecked and changes:
Decision: NO-GO / CONDITIONAL GO / GO / assessment pending
Reason and next action:
Reviewer/date:
```
