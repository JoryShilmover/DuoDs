# Execution work log

Starting revision: `e2558fe` on `main`, clean tracked working tree; origin and branch preserved. Execution date: 2026-09-23.

| Package | Status | Owner | Evidence / next action |
|---|---|---|---|
| P0 | passed (simulator scope) | root | Xcode-Beta 27.1 (27A9269), iOS 27.1 SDK, booted iPhone Duo simulator. Core v1.3.1 pinned at bc4e4b67d2d470d7c682810a1e892cafd6f9082b (`Dependencies/lock.json`). Paired iPhone 15 Pro Max exists but device work deferred (D06). |
| P1 | passed | root | `scripts/build-poc.sh` / `scripts/test-poc.sh`; contracts in `CONTRACTS.md`. Core patch `Dependencies/patches/static-core.patch` (static lib + offline networking stubs). |
| P2 | active | core_runtime → root | Bridge `Emulator/CoreBridge/DuoCore.cpp`, session `Emulator/Runtime/EmulationSession.swift`. Native bridge tests pass under ASan/UBSan. Static core `build/core-simulator/libDuoCoreCombined.a` built. Real-emulation run not yet demonstrated. |
| P3 | passed (synthetic) | layout_input | 6 layout/input tests pass; display adapter typechecks against 27.1 SDK. Real Duo fold behavior unverified. |
| P4 | passed (unit) | library_saves | 10 library/persistence tests pass (duplicates, corruption, interrupted writes, version/ROM mismatch, traversal). |
| P5 | active | root | App wiring exists (`App/`). Integrated simulator build succeeds. Diagnostic ROM imports but boot fails (see session log below). |
| P6 | not started | — | Needs P5 boot working. |
| P7 | not run | — | Simulator-only run (D06). G1/G3 not run. |
| P8 | not started | — | Fresh read-only reviewer at end. |

No ROMs, firmware, keys, saves, or device identifiers belong in tracked evidence. Raw local evidence goes in ignored artifacts/poc/.

## Session log

### 2026-09-23 — Codex run (orchestrated, 3 workers)
P0–P4 as above. Run ended (usage limit) ~17:42 local while root was rebuilding the patched core and the core worker was about to run the diagnostic fixture in the simulator. Codex transcripts: `~/.codex/sessions/2026/09/23/rollout-2026-09-23T16-50-13-*.jsonl` (root) and 17-32/17-33 files (workers).

### 2026-09-23 — Claude Code resume
- Re-verified: `scripts/test-poc.sh` → 17 tests, 0 failures. `scripts/build-poc.sh --skip-core --diagnostic --configuration Debug` → BUILD SUCCEEDED with core linked. Dependency working-tree diff matches `static-core.patch` exactly.
- Installed on iPhone Duo simulator, launched with `--diagnostic`: ROM imported into library, but session stays `idle` with 0 frames; an alert is shown and dismissed; no `boot` event in `session-events.jsonl`. Cause under investigation (next: log launch errors to console).
- Checkpoint commit made of all P0–P5 work in progress.

## How to resume (for any agent)
1. `DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer`; first-time: `scripts/bootstrap-tools.sh`, then `scripts/build-poc.sh --diagnostic --configuration Debug` (full core build) or `--skip-core` if `build/core-simulator/libDuoCoreCombined.a` exists.
2. `scripts/test-poc.sh` for logic tests.
3. Simulator run: `xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/DuoDS.app && xcrun simctl launch --console-pty booted org.duods.prototype --diagnostic`.
4. Session events: `<app data container>/Library/Application Support/DuoDS/session-events.jsonl`.
5. Read the latest entry in this log and `DECISIONS.md` before changing anything.
