# Exit checklist: from proof of concept to product work

Status as of 2026-09-23 (updated through the agent-only tasks). Criteria and case IDs (V01–V20, G0–G4) come from [VALIDATION.md](VALIDATION.md). Current evidence is in [REPORT.md](REPORT.md).

The plan's **GO** requires G0–G4 to pass, including a physical Duo (G3). The Duo is not released, so the POC cannot reach GO on the original scope yet. Two ways forward:

- **A. Wait for Duo hardware.** Finish everything else, then run G3.
- **B. Revise the scope (user decision).** Make an ordinary iPhone the primary target and the Duo a follow-up. Record this in DECISIONS.md, move the must-pass V07–V18 rows to the iPhone, and keep the Duo rows as a later gate. The plan allows a clearly recorded scope revision; it does not allow quietly skipping rows.

Legend: **[agent]** an agent can do it alone · **[you]** needs you (device, play, judgment) · **[Duo]** blocked until Duo hardware exists · **[decide]** a decision for you.

## 1. Finish G1 on the physical iPhone
- [ ] **[you]** V03: 5-minute play trace with `user-01` (planned for this evening). Pull logs; check speed ≥ core target, underruns and thermal state.
- [ ] **[you]** V02: on-device cartridge save survives close and relaunch (the simulator already passed).
- [ ] **[you]** V02: stylus taps land where touched on the lower screen.
- [ ] **[agent]** Use a release-like build for G1/G3 numbers. Current builds are development-signed (`get-task-allow`); the report and the evidence manifest record this.

## 2. Features that are missing or unverified
| Item | State | Owner |
|---|---|---|
| Microphone input (V15): permission flow, core mic feed, safe fallback when denied | Implemented; passes on simulator (granted and denied) | [you] device: deny → grant → revoke, and a game that uses the mic |
| Manual save states (V20): save/restore with `user-01`; reject wrong-ROM, corrupt and old-version states | Done on simulator; confirm on device | [you] |
| Physical controller (V17): connect, disconnect mid-game, no stuck buttons | Code exists; untested | [you] (needs a controller) |
| Apple Pencil | Untested | [you] if you have one |
| Emulated lid (V16): visible in-game effect | Wired and unit-tested; not observed in a game | [you] |
| Scene ownership release and battery flush after core failure | Done (`8e08fd9`) | — |
| Homebrew SD (DLDI) save durability | Enabled and flushed (D18); end-to-end unverified without an SD-writing homebrew | [you] if you have a homebrew that saves to SD |
| Presentation metrics (V09) | Instrumented; 99.7% unique on simulator | [you] device run |
| Touch accuracy and latency (V10) | Instrumented (`touch-down`/`touch-consumed`) | [you] tap test on device |
| Energy/battery sampling (V12) | Battery level/state, low power, brightness, thermal logged | [you] device run |

## 3. UI follow-ups (after the DS Lite–style pass)
- [ ] **[you]** Hands-on feel in portrait and landscape: size, reach, anything misplaced.
- [x] **[agent]** Adjustable control size and opacity; left-handed swap (menu → Controls…). Free-form drag-to-place is not done.
- [ ] **[agent]** Landscape iPhone layout check on device (unit-tested with an estimated size only).
- [ ] **[you]** V18 ergonomics: a 15-minute trial per pose. One user minimum, two preferred.

## 4. Simulator-completable G2 rows
- [ ] **[agent + you]** V04: 20 transitions per route (flat ↔ half-fold ↔ closed/outer, rotations) with no lost session. You drive the Simulator; logs are automatic.
- [ ] **[agent + you]** V05: hold the stylus through a fold or rotation; the touch must cancel or remap, never stick. Also test layout override and returning to Automatic.
- [ ] **[agent]** V06: second window/scene; exactly one session, one save writer, no duplicate audio.

## 5. Physical Duo (G3)
V07/V08 30-minute 2D and 3D runs, V09 presentation cadence, V10 touch accuracy and latency, V11 30-minute audio, V12 thermal/energy, V13 two-title saves and upgrade migration, V14 lifecycle (lock, call, low memory, cold restart), V16 lid in every pose, V18 ergonomics per pose. **[Duo]** — or **[you]** on iPhone under option B.

## 6. Reproducibility and handoff (G4)
- [ ] **[you or another person]** V19: an independent operator follows the README/WORK_LOG steps from a fresh clone and repeats V02 plus one Duo pose. The same-machine fresh clone already builds.
- [x] **[agent]** Per-run `manifest.json`, metrics and report: `scripts/collect-evidence.py`.

## 7. Decisions before anything leaves your devices
- [ ] **[decide]** License for the app's own code. It links GPLv3 code, so it needs a GPL-compatible license and a corresponding-source offer before any distribution.
- [ ] **[decide]** Distribution path: free team (7-day installs, personal only), TestFlight/paid account, or App Store. Check the current App Store rules for emulators at that time.
- [ ] **[decide]** BIOS/firmware policy. Today it uses the core's built-in FreeBIOS only. Some games may need real firmware, which users would have to supply themselves.
- [ ] **[decide]** Scope option A or B above.

## After the POC (product work, not POC exit criteria)
Broader game compatibility testing, older supported iPhones (the minimum is iOS 17), 3D-heavy performance tuning, settings UI, cloud sync, and polish. See the "Explicitly deferred" list in EXECUTION_PLAN.md.
