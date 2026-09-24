# POC evidence report

Date: 2026-09-23 (last updated after the agent-only task batch, `03ed118`). Operator: root agent (Codex run, then Claude Code resume), with user-driven simulator fold trials and gameplay on simulator and iPhone.
Reviewer: fresh read-only agent (P8), reviewed `cf6cb68`; fixes landed in `0b28849` and later.
Scope: iPhone Duo simulator plus the user's **iPhone 15 Pro Max (iOS 27.0)** from D14 onward, development-signed with the personal team. No physical Duo exists yet.

| Item | Value |
|---|---|
| Core | melonDS DS v1.3.1 `bc4e4b67d2d470d7c682810a1e892cafd6f9082b`, patch `Dependencies/patches/static-core.patch` (static lib, networking off, lid-chord Y mask) |
| Build | Interpreter, no JIT (`-DENABLE_JIT=OFF`; reviewer found no ARMJIT symbols in the simulator library), software renderer, Metal presentation |
| Toolchain | Xcode-Beta 27.1 (27A9269), iOS 27.1 simulator SDK, minimum iOS 17 |
| Targets | iPhone Duo simulator (iOS 27.1); iPhone 15 Pro Max simulator (iOS 17.5, minimum-OS check); iPhone 15 Pro Max device (iOS 27.0) |
| Fixtures | `duo-diagnostic-v1` (authored, MIT, SHA-256 `c8c5e019…d175`); `user-01` user-supplied commercial title (identity kept privately) |
| Core AV rate | 59.8261 fps, 32768 Hz nominal (reported ≈32728 Hz effective) |

Raw evidence is local only, under ignored `artifacts/poc/`: `2026-09-23-resume/` (simulator logs, screens, fold trials), `2026-09-23-device/` (device logs, entitlements, binary hash), `2026-09-23-ui/` (control screenshots). New runs: `scripts/collect-evidence.py`.

## Gates

| Gate | Status | Evidence | Blocker / defect |
|---|---|---|---|
| G0 — toolchain, source, rights | **Partial** | Pinned sources and license notices (`Dependencies/`); fresh-clone rebuild; signed device build with entitlement dump (no JIT entitlement) and 0 JIT symbols | App license and GPLv3 source offer undecided (user decision) |
| G1 — no-JIT spike on physical iPhone | **In progress** | iPhone 15 Pro Max, iOS 27.0, personal-team development build: no JIT entitlement or symbols; `--selftest` passes on device at 100% of core target; `user-01` ran ~32 s at 100% of target; 0 audio underruns after D16 | User's 5-minute run (V03), on-device game save, stylus taps — scheduled (see WORK_LOG "Next session"); development signing (`get-task-allow`) |
| G2 — Duo layout and lifecycle (simulator) | **Partial** | Fold trials: flat, half-fold (landscape + portrait), closed→outer, rotations; one session throughout; layouts avoid hinge; DS Lite–style controls in every pose; V20 save states pass | Not 20 changes per route (V04); held stylus through fold (V05) and multi-scene (V06) not run |
| G3 — physical Duo | **Blocked** | — | No physical Duo |
| G4 — handoff | **Not run** | Same-machine fresh-clone rebuild succeeded after the fix in `7cc609b` | Needs an independent operator (V19) |

## Matrix rows with evidence

| Case | Status | Actual | Evidence |
|---|---|---|---|
| V01 | Partial | Pinned simulator build from a fresh clone; notices inventoried; no JIT flag | `clean-build` log (scratch), `Dependencies/` |
| V02 (analog) | Simulator only | Two screens render; A input changes frame; audio produced; `user-01` in-game save survives close and relaunch (user-observed; `battery.save` + `battery.previous` written) | `selftest3-run*.jsonl`, user report |
| V03 | Not run | Core counter tracks 59.83 Hz on the simulator; not a device measurement | checkpoints in logs |
| V04 | Partial | Poses exercised once or twice each, not 20× | `fold-events.jsonl`, `fold2-events.jsonl` |
| V05 | Not run | — | — |
| V06 | Not run (code ready) | Scene release on disconnect and "Move game here" handoff implemented; not exercised | — |
| V07–V08 | Blocked | Physical Duo required (or iPhone under scope option B) | — |
| V09 | Instrumented | Simulator: 99.7% of core frames presented uniquely; device measurement pending | events `presented_*` |
| V10 | Instrumented | `touch-down` / `touch-consumed` logged with independent mapping check in `collect-evidence.py`; device taps pending | — |
| V11 | Partial | After D16: 0 underruns over boot/resume/relaunch/70 s on iPhone (diagnostic); 30-minute capture pending | `audio-fix-device.jsonl` |
| V12 | Instrumented | Thermal, battery level/state, low power, brightness logged; device run pending | — |
| V13 | Partial | One title, one save round trip; atomic write plus backup unit-tested | PersistenceStore tests, save files |
| V14 | Partial | Pause freezes the core; pause during in-flight resume is honored (3/3 runs); held input released | `selftest3-run1..3.jsonl` |
| V15 | Pass (simulator) | Hold-to-talk mic: granted → core receives samples; denied → one notice, silence, no crash. Device deny/grant/revoke pending | `mic-events.jsonl` |
| V16 | Partial | Lid chord wired; queued pulses unit-tested; game-visible lid effect not observed | native bridge test |
| V17 | Not run | No controller used | — |
| V18 | Not run | Informal play on the simulator only — see UI note below | — |
| V19 | Not run | See G4 | — |
| V20 | Pass (simulator) | `user-01` round trip restores the saved frame (diff 0.56 vs 2.18 advanced, 2/2); homebrew fixture also serializes; cartridge save payload unchanged; rejection cases unit-tested. Device validation pending | `states-events.jsonl` |

## Open defects and backlog

| Severity | Item |
|---|---|
| Fixed | Audio lead/drift/stall (D16): 0 underruns on device over boot, resume, relaunch and 70 s (diagnostic). V11 30-minute capture on the target device still required |
| S3 | UI/control overhaul: first DS Lite–style pass done (D15). Remaining: user-adjustable placement/size, opacity, left-handed option, V18 hands-on trial |
| Fixed | Scene ownership released on disconnect, with a "Move game here" handoff; battery flush after core failure |
| S3 | Transient geometry with stale reserved regions lasts about 1 frame during transitions |
| Decision | App license and GPLv3 corresponding-source offer before any distribution |

## Decision

**Assessment pending.** G1 (physical current iPhone) has not been run, by user choice, and no decisive failure has been found. The simulator results support continuing: real DS execution without JIT, a commercial title with 3D and saves, and fold/pose handling without restarting the session. They are not evidence of device performance, thermals, battery or ergonomics.

Next actions, in order:
1. Run G1 on the paired iPhone with the personal team: release-like signed build, entitlement dump, V02/V03.
2. Exercise V20 with `user-01` (manual state save/restore; rejection of wrong-ROM, corrupt and version-mismatched states).
3. Improve the audio lead (prefill and drift control) before the V11 measurements.
4. Complete V04–V06 on the simulator (20× per route, held stylus through fold, multi-scene).
5. UI/control overhaul (backlog above), then a V18 hands-on trial.
6. Physical Duo for G3 when available; an independent operator for G4.
