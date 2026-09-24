# Execution work log

Starting revision: `e2558fe` on `main`, clean tracked working tree; origin and branch preserved. Execution date: 2026-09-23.

| Package | Status | Owner | Evidence / next action |
|---|---|---|---|
| P0 | passed (simulator scope) | root | Xcode-Beta 27.1 (27A9269), iOS 27.1 SDK, booted iPhone Duo simulator. Core v1.3.1 pinned at bc4e4b67d2d470d7c682810a1e892cafd6f9082b (`Dependencies/lock.json`). Paired iPhone 15 Pro Max exists but device work deferred (D06). |
| P1 | passed | root | `scripts/build-poc.sh` / `scripts/test-poc.sh`; contracts in `CONTRACTS.md`. Core patch `Dependencies/patches/static-core.patch` (static lib + offline networking stubs). |
| P2 | passed (simulator) | root | Real DS execution of the authored fixture on iPhone Duo simulator: both screens rendered, 59.83 Hz core, audio flowing (`artifacts/poc/2026-09-23-resume/screens/fixture-fixed.png`, local only). Native bridge tests pass under ASan/UBSan. No physical-device performance evidence (D06). |
| P3 | passed (synthetic) | layout_input | 6 layout/input tests pass; display adapter typechecks against 27.1 SDK. Real Duo fold behavior unverified. |
| P4 | passed (unit) | library_saves | 10 library/persistence tests pass (duplicates, corruption, interrupted writes, version/ROM mismatch, traversal). |
| P5 | active | root | `--diagnostic --selftest` passes: A input changes frame, release reverts, pause freezes core (0 frames/1 s), held input released across pause/resume, stop→relaunch. Not observed: lid (fixture ignores lid), battery save round trip (no lawful cartridge-save fixture; see FIXTURES.md), real audio interruption, touch on lower screen via UI, layout swap/override. |
| P6 | active | root | Manual fold trial on Duo simulator (user-driven; `simctl` has no posture control): one boot, frames continuous through half-fold, close→outer, reopen, 2 rotations (no reboot). Half-fold: `split` layout clear of 40 pt division. Controls were missing on outer display and crammed in portrait → solver fixed (D11) and re-verified on the simulator: half-fold landscape and portrait splits with full controls, outer landscape with controls. Remaining: outer-display portrait under the fix (covered by unit test only), lower-band control placement (unit-level change, not re-observed), real hardware. |
| P7 | active | root + user | G1 on iPhone 15 Pro Max (iOS 27.0), personal team (D14). Release build signed and installed; entitlements show no JIT/dynamic-codesigning; 0 JIT symbols in app and core. Launch blocked until the user trusts the developer profile on the phone. G3 blocked (no Duo). |
| P8 | passed (simulator scope) | reviewer → root | Review of `cf6cb68` ("ship with fixes"); fixes 1–4 landed and race fix verified 3/3 on simulator. Open items in `REPORT.md`. Decision: **assessment pending**. |

No ROMs, firmware, keys, saves, or device identifiers belong in tracked evidence. Raw local evidence goes in ignored artifacts/poc/.

## Session log

### 2026-09-23 — Codex run (orchestrated, 3 workers)
P0–P4 as above. Run ended (usage limit) ~17:42 local while root was rebuilding the patched core and the core worker was about to run the diagnostic fixture in the simulator. Codex transcripts: `~/.codex/sessions/2026/09/23/rollout-2026-09-23T16-50-13-*.jsonl` (root) and 17-32/17-33 files (workers).

### 2026-09-23 — Claude Code resume
- Re-verified: `scripts/test-poc.sh` → 17 tests, 0 failures. `scripts/build-poc.sh --skip-core --diagnostic --configuration Debug` → BUILD SUCCEEDED with core linked. Dependency working-tree diff matches `static-core.patch` exactly.
- Installed on iPhone Duo simulator, launched with `--diagnostic`: ROM imported into library, but session stays `idle` with 0 frames; an alert is shown and dismissed; no `boot` event in `session-events.jsonl`. Cause under investigation (next: log launch errors to console).
- Checkpoint commit `f48c8d2` of all P0–P5 work in progress.
- Root cause of boot failure: bridge passed only `path` but the core needs `data`/`size` (D07). Fixed in `DuoCore.cpp`; native test now asserts bytes are supplied.
- Added error logging (D08) and fixed diagnostic auto-launch race (D09).
- Frames were then all black: fixture bug, not rendering (BG2CNT 0x4080 → 0x4084). After fix, both screens render in the Duo simulator (side-by-side in unfolded landscape). 17 logic tests still pass.
- Added `--selftest` (scripted P5 checks → `selftest-*` events with per-screen lit counts and mean RGB) and `geometry` events (bounds, safe area, active reserved regions, chosen mode/rects). Evidence copy: `artifacts/poc/2026-09-23-resume/logs/selftest-events.jsonl` (local).
- Fixed: Resume button was a stacked row, so every pause resized the play area and moved both screens; now an overlay (no geometry change on pause).
- Fold trial (`artifacts/poc/2026-09-23-resume/fold/`, `logs/fold-events.jsonl`, local): see P6 row. Geometry observed: inner landscape 867×523 pt; half-fold division `456,-82 40x669`; outer display 382×532 pt; inner portrait 669×805 pt. Transient geometry with stale reserved regions appears for ~1 frame during transitions (harmless; each change cancels touches).
- Fixed solver ranking: control-band candidates now outrank larger screens when both screens stay ≥170 pt wide. Regression test `testObservedDuoGeometriesKeepUsableControls` uses the observed sizes. 18 tests pass.
- Not yet explained: a horizontal seam in the fixture's top screen in one portrait screenshot. Likely the fixture writing VRAM past vblank (tearing in emulated content), not host presentation — unverified.
- Re-trial (`fold2/`, `logs/fold2-events.jsonl`, local): 1 boot, frames continuous through half-fold → half-fold portrait → outer landscape (594×320 pt) → unfold. Controls present in every posture. Outer landscape put controls in the top band; canvas now prefers the lowest qualifying band.
- Fresh-clone reproduction (V19-style, same machine, by root agent — not an independent operator): first attempt at `3f6fc38` FAILED in `fetch-dependencies.py` ("Core local diff differs from retained patch") because the patch stored abbreviated blob hashes whose length depends on clone size. Fixed in `7cc609b` (`--full-index`). Re-run from a fresh clone of `7cc609b`: bootstrap → fetch (all revisions + patch verified) → core build → app build SUCCEEDED in 53 s; fixture SHA-256 `c8c5e019…d175` matches FIXTURES.md; 18 tests pass. Separate caches (scratch clone), shared Xcode/SwiftPM system caches.
- P8 review findings → resolution:
  1. [med-high] Pause during in-flight resume was dropped (scene inactive while audio activating → game runs in background). FIXED: `EmulationSession` defers the pause until resume completes; stop during resume is not overwritten. `--selftest` step `selftest-pause-during-resume` verified 3/3 on simulator (phase stays paused, 0 frames); first attempt was a test-ordering bug (pause ran before resume started), fixed by waiting on `isResuming`.
  2. [med] Router/view held input never cancelled on pause (stuck controller button after background). FIXED: `releaseInputs()` bumps `inputEpoch`; `PlaySessionCanvas` cancels contacts and router state on change. Needs a real controller to observe.
  3. [med] Lid chord L2+Y also pressed DS Y for a frame; queued toggles merged. FIXED: core patch masks DS Y while L2 held (`input/joypad.cpp`); bridge queues pulses with a release frame between (native test covers 2 toggles).
  4. [med] ROM resident 3× (core copies bytes in `retro/info.cpp`). FIXED: bridge frees its buffer after `retro_load_game` (D07 corrected).
  5. [med] Pause on every audio route change; thin audio lead (5–7 underruns per boot/resume, ~25 ms steady lead); no drift correction; silent freeze if engine stops unobserved. PARTIAL: route-change pause now only on `.oldDeviceUnavailable`. Audio lead/prefill, drift control and engine-stop detection remain OPEN (S2 on simulator; must be measured on device, V11).
  6. [low] Battery flush skipped after runtime core failure (≤10 s of cartridge writes lost). OPEN, documented.
  7. [low] Docs/licensing: FIXTURES button-color now marked observed. OPEN for user decision: app LICENSE and GPLv3 corresponding-source offer needed before any distribution.
  Reviewer could not verify: device audio/route behavior, device JIT symbols, homebrew SD (DLDI) save durability, multi-scene ownership (`owner` never released on scene disconnect).
- User-supplied commercial title `user-01` (see FIXTURES.md; identity private) imported through the file picker on the Duo simulator: boots with built-in FreeBIOS, 3D overworld renders, gameplay reached, 59.83 Hz core, 4 underruns over ~19k frames (simulator — not a performance result). Cartridge save round trip: user saved in-game, closed to Library, relaunched — save loaded (user-observed); `battery.save` and backup `battery.previous` written by PersistenceStore.
- Final report: `docs/poc/REPORT.md` (gate table, matrix rows, open defects, next actions). Decision **assessment pending** (G1 not run by user choice).
- Pushed `36c840d` to origin/main (user approved).
- Device build (D14): signed Release app built and installed on the iPhone 15 Pro Max; evidence in `artifacts/poc/2026-09-23-device/logs/` (entitlements, binary SHA-256 `13f3cf80…cadd`, build log). `get-task-allow=true` (development signing) — not a distribution-signed binary.

## Backlog (user requests)
- **UI and on-screen button overhaul** (2026-09-23): the current 7×2 grid is a placeholder. Redesign the controls' layout and placement for each pose (flat, half-fold, outer, portrait), with thumb reach, a DS-like D-pad and face buttons, and user-adjustable placement. Track as S2 in REPORT.md; ties into the V18 ergonomics trial.

## How to resume (for any agent)
1. `DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer`; first-time: `scripts/bootstrap-tools.sh`, then `scripts/build-poc.sh --diagnostic --configuration Debug` (full core build) or `--skip-core` if `build/core-simulator/libDuoCoreCombined.a` exists.
2. `scripts/test-poc.sh` for logic tests.
3. Device build: `scripts/build-poc.sh --sdk iphoneos --team 9TZU9LRJV9 --configuration Release --diagnostic --destination id=<device UDID>` (a specific destination lets Xcode register the device with the free team); install: `xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Release-iphoneos/DuoDS.app`. First launch requires trusting the developer in Settings → General → VPN & Device Management.
3b. Simulator run: `xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/DuoDS.app && xcrun simctl launch --console-pty booted org.duods.prototype --diagnostic`.
4. Scripted checks: add `--selftest` after `--diagnostic`; wait ~20 s, then read `selftest-*` events.
5. Session events: `<app data container>/Library/Application Support/DuoDS/session-events.jsonl`.
6. Read the latest entry in this log and `DECISIONS.md` before changing anything.
