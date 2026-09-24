# POC evidence report — simulator-scope run

Date: 2026-09-23. Operator: root agent (Codex run, then Claude Code resume), with user-driven simulator fold trials and gameplay.
Reviewer: fresh read-only agent (P8), reviewed `cf6cb68`; fixes landed in `0b28849` and later.
Scope: **iPhone Duo simulator only** (user instruction D06). No physical iPhone or physical Duo was used.

| Item | Value |
|---|---|
| Core | melonDS DS v1.3.1 `bc4e4b67d2d470d7c682810a1e892cafd6f9082b`, patch `Dependencies/patches/static-core.patch` (static lib, networking off, lid-chord Y mask) |
| Build | Interpreter, no JIT (`-DENABLE_JIT=OFF`; reviewer found no ARMJIT symbols in the simulator library), software renderer, Metal presentation |
| Toolchain | Xcode-Beta 27.1 (27A9269), iOS 27.1 simulator SDK, minimum iOS 17 |
| Simulator | iPhone Duo, iOS 27.1 |
| Fixtures | `duo-diagnostic-v1` (authored, MIT, SHA-256 `c8c5e019…d175`); `user-01` user-supplied commercial title (identity kept privately) |
| Core AV rate | 59.8261 fps, 32768 Hz nominal (reported ≈32728 Hz effective) |

Raw evidence is local only, under ignored `artifacts/poc/2026-09-23-resume/`: `logs/*.jsonl` (session events), `screens/`, `fold/`, `fold2/`.

## Gates

| Gate | Status | Evidence | Blocker / defect |
|---|---|---|---|
| G0 — toolchain, source, rights | **Not run** (partial) | Pinned sources and license notices (`Dependencies/`); simulator build reproduced from a fresh clone (WORK_LOG) | Signed device build, entitlement dump and no-JIT runtime check not attempted (D06). App license and GPLv3 source offer undecided |
| G1 — no-JIT spike on physical iPhone | **Not run** | Simulator analog only: fixture and `user-01` boot, render both screens, take input, produce audio; cartridge save round trip OK | Physical device deferred by user (D06) |
| G2 — Duo layout and lifecycle (simulator) | **Partial** | Fold trials: flat, half-fold (landscape + portrait), closed→outer, rotations; one session throughout; layouts avoid hinge; controls in every pose after fix | Not 20 changes per route (V04); held-stylus-through-fold (V05), multi-scene (V06), save-state round trip (V20) not run |
| G3 — physical Duo | **Blocked** | — | No physical Duo |
| G4 — handoff | **Not run** | Same-machine fresh-clone rebuild succeeded after the fix in `7cc609b` | Needs an independent operator (V19) |

## Matrix rows with evidence

| Case | Status | Actual (simulator) | Evidence |
|---|---|---|---|
| V01 | Partial | Pinned simulator build from a fresh clone; notices inventoried; no JIT flag | `clean-build` log (scratch), `Dependencies/` |
| V02 (analog) | Simulator only | Two screens render; A input changes frame; audio produced; `user-01` in-game save survives close and relaunch (user-observed; `battery.save` + `battery.previous` written) | `selftest3-run*.jsonl`, user report |
| V03 | Not run | Core counter tracks 59.83 Hz on the simulator; not a device measurement | checkpoints in logs |
| V04 | Partial | Poses exercised once or twice each, not 20× | `fold-events.jsonl`, `fold2-events.jsonl` |
| V05, V06 | Not run | — | — |
| V07–V12 | Blocked | Physical Duo required | — |
| V13 | Partial | One title, one save round trip; atomic write plus backup unit-tested | PersistenceStore tests, save files |
| V14 | Partial | Pause freezes the core; pause during in-flight resume is honored (3/3 runs); held input released | `selftest3-run1..3.jsonl` |
| V15 | Not run | Microphone not implemented | — |
| V16 | Partial | Lid chord wired; queued pulses unit-tested; game-visible lid effect not observed | native bridge test |
| V17 | Not run | No controller used | — |
| V18 | Not run | Informal play on the simulator only — see UI note below | — |
| V19 | Not run | See G4 | — |
| V20 | Not run | `user-01` supports serialization; manual save/restore state not yet exercised | — |

## Open defects and backlog

| Severity | Item |
|---|---|
| S2 | Audio: thin lead (5–7 underruns at each boot or resume, about 25 ms steady), no drift correction, silent stall if the engine stops unobserved. Must be measured on device (V11) |
| S2 | **UI and on-screen control overhaul needed (user request, 2026-09-23).** The current 7×2 button grid is a placeholder. Future work: redesign the layout and placement of controls per pose (flat, half-fold, outer, portrait), with thumb reach, a D-pad/face-button arrangement like the DS, and user-adjustable placement. Candidate for V18 ergonomics work |
| S2 (unverified) | Scene `owner` is never released on scene disconnect, so a new scene may be locked out |
| S3 | Battery flush is skipped after a runtime core failure (≤10 s of cartridge writes lost) |
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
