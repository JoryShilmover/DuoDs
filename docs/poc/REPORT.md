# POC evidence report

Date: 2026-09-24 (last updated after the user's device playtest of `9a8c9ac`). Operator: root agent (Codex run, then Claude Code resume), with user-driven simulator fold trials and gameplay on simulator and iPhone.
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
| G1 — no-JIT spike on physical iPhone | **Pass, with a signing caveat** | iPhone 15 Pro Max, iOS 27.0, Release configuration: no JIT entitlement or symbols; `--selftest` passes; `user-01` 11.3 min at 100.0% of core target, 0 audio underruns; 204 stylus taps mapped within 1 DS px; in-game save survived close and relaunch (user-observed) | Development signing (`get-task-allow`), not distribution-signed. The authored 2D fixture was used for the selftest; gameplay, save and stylus used `user-01` |
| G2 — Duo layout and lifecycle (simulator) | **Partial** | Fold trials: flat, half-fold (landscape + portrait), closed→outer, rotations; one session throughout; layouts avoid hinge; DS Lite–style controls in every pose; V20 save states pass | Not 20 changes per route (V04); held stylus through fold (V05) and multi-scene (V06) not run |
| G3 — physical Duo | **Blocked** | — | No physical Duo |
| G4 — handoff | **Not run** | Same-machine fresh-clone rebuild succeeded after the fix in `7cc609b` | Needs an independent operator (V19) |

## Matrix rows with evidence

| Case | Status | Actual | Evidence |
|---|---|---|---|
| V01 | Partial | Pinned simulator build from a fresh clone; notices inventoried; no JIT flag | `clean-build` log (scratch), `Dependencies/` |
| V02 | Pass (iPhone) | Device: selftest shows two screens, A input and audio; `user-01` in-game save loaded after Library → relaunch (user-observed, 2026-09-24); stylus taps land on the lower screen. Save checksum before/after not captured | `2026-09-24-overnight-device/`, user report |
| V03 | Pass (iPhone) | `user-01`: 40,537 frames in 677.6 s active = 100.0% of 59.8261 fps; all 10 s windows ≥0.999 except one at 0.887 during a screen swap, recovered in the next windows (50 s around it = 100%) | `2026-09-24-overnight-device/` |
| V04 | Partial | Poses exercised once or twice each, not 20× | `fold-events.jsonl`, `fold2-events.jsonl` |
| V05 | Not run | — | — |
| V06 | Not run (code ready) | Scene release on disconnect and "Move game here" handoff implemented; not exercised | — |
| V07–V08 | Blocked | Physical Duo required (or iPhone under scope option B) | — |
| V09 | Measured on iPhone (Duo pending) | 40,077 / 40,537 core frames presented uniquely (98.9%), 459 skipped (~90 during the screen swap), 0 repeated. Target ≥95% | `2026-09-24-overnight-device/` |
| V10 | Measured on iPhone (Duo pending) | 204 taps in portrait: max mapping error 1 DS px; contact → core latency p50 32 ms, p95 43 ms, max 47 ms (203 samples). No corner taps (x 30–218, y 46–138) and one pose only | `2026-09-24-overnight-device/` |
| V11 | Partial | iPhone, `user-01`: 0 underruns and 0 overruns in 11.3 min, cushion 61–85 ms. 30-minute capture pending | `2026-09-24-overnight-device/` |
| V12 | Measured on iPhone (short) | 11.3 min unplugged at ~4% brightness: thermal nominal → fair after ~7.5 min, never serious; battery 40% → 35% (iOS reports 5% steps) | `2026-09-24-overnight-device/` |
| V13 | Partial | One title, one save round trip; atomic write plus backup unit-tested | PersistenceStore tests, save files |
| V14 | Partial | Pause freezes the core; pause during in-flight resume is honored (3/3 runs); held input released | `selftest3-run1..3.jsonl` |
| V15 | Pass (simulator) | Hold-to-talk mic: granted → core receives samples; denied → one notice, silence, no crash. Device deny/grant/revoke pending | `mic-events.jsonl` |
| V16 | Partial | Lid chord wired; queued pulses unit-tested; game-visible lid effect not observed | native bridge test |
| V17 | Not run | No controller used | — |
| V18 | Not run | Informal play on the simulator only — see UI note below | — |
| V19 | Not run | See G4 | — |
| V20 | Pass (simulator + iPhone round trip) | `user-01` round trip restores the saved frame (diff 0.56 vs 2.18 advanced, 2/2); homebrew fixture also serializes; cartridge save payload unchanged; rejection cases unit-tested. iPhone 15 Pro Max: save/restore works in `user-01` (user-observed, 2026-09-24) | `states-events.jsonl`, user report |

## Open defects and backlog

| Severity | Item |
|---|---|
| Fixed | Audio lead/drift/stall (D16): 0 underruns on device over boot, resume, relaunch and 70 s (diagnostic). V11 30-minute capture on the target device still required |
| S3 | UI/control overhaul: first DS Lite–style pass done (D15). Remaining: user-adjustable placement/size, opacity, left-handed option, V18 hands-on trial |
| Fixed | Scene ownership released on disconnect, with a "Move game here" handoff; battery flush after core failure |
| Fixed (confirmed on device) | S2: the in-game ⋯ menu opened but its items ignored taps (device playtest 2026-09-24). Cause: `RootView` observed `EmulationSession`, which publishes every frame, so the toolbar Menu was rebuilt at 60 Hz while open. The per-frame view now lives in `PlayArea`; the root no longer observes the session |
| S3 | Transient geometry with stale reserved regions lasts about 1 frame during transitions |
| Decision | App license and GPLv3 corresponding-source offer before any distribution |

## Decision

**Assessment pending, now blocked only on G0.** G1 has device evidence (2026-09-24): `user-01` held 100% of core target for 11.3 minutes on an iPhone 15 Pro Max with no JIT, no audio underruns, accurate stylus mapping and a working in-game save. No decisive failure has been found. CONDITIONAL GO needs G0 to pass, and G0 is still partial until the app license and GPLv3 source offer are decided. The G1 build was development-signed, not distribution-signed. None of this is Duo evidence.

Next actions, in order:
1. V15 (mic permission) and V10 corner taps on the iPhone; a landscape stretch.
2. Decide the app license and GPLv3 source offer (unblocks G0 and therefore CONDITIONAL GO).
3. Decide scope option A/B (EXIT_CHECKLIST.md); under B, 30-minute 2D/3D runs (V07/V08/V11/V12) on the iPhone.
4. Complete V04–V06 on the simulator (20× per route, held stylus through fold, multi-scene).
5. V18 hands-on trial per pose; landscape iPhone check.
6. Physical Duo for G3 when available; an independent operator for G4.
