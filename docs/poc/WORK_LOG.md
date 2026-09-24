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
| P6 | active | root | Manual fold trial on Duo simulator (user-driven; `simctl` has no posture control): one boot, frames continuous through half-fold, close→outer, reopen, 2 rotations (no reboot). Half-fold: `split` layout clear of 40 pt division. Controls were missing on outer display and crammed in portrait → solver fixed; re-trial of portrait/outer pending. |
| P7 | not run | — | Simulator-only run (D06). G1/G3 not run. |
| P8 | not started | — | Fresh read-only reviewer at end. |

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

## How to resume (for any agent)
1. `DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer`; first-time: `scripts/bootstrap-tools.sh`, then `scripts/build-poc.sh --diagnostic --configuration Debug` (full core build) or `--skip-core` if `build/core-simulator/libDuoCoreCombined.a` exists.
2. `scripts/test-poc.sh` for logic tests.
3. Simulator run: `xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/DuoDS.app && xcrun simctl launch --console-pty booted org.duods.prototype --diagnostic`.
4. Scripted checks: add `--selftest` after `--diagnostic`; wait ~20 s, then read `selftest-*` events.
5. Session events: `<app data container>/Library/Application Support/DuoDS/session-events.jsonl`.
6. Read the latest entry in this log and `DECISIONS.md` before changing anything.
