# Exit checklist: from proof of concept to product work

Status as of 2026-09-24 (updated after the first device playtest). Criteria and case IDs (V01–V20, G0–G4) come from [VALIDATION.md](VALIDATION.md). Current evidence is in [REPORT.md](REPORT.md).

The plan's **GO** requires G0–G4 to pass, including a physical Duo (G3). The Duo is not released, so the POC cannot reach GO on the original scope yet. Two ways forward:

- **A. Wait for Duo hardware.** Finish everything else, then run G3.
- **B. Revise the scope (user decision).** Make an ordinary iPhone the primary target and the Duo a follow-up. Record this in DECISIONS.md, move the must-pass V07–V18 rows to the iPhone, and keep the Duo rows as a later gate. The plan allows a clearly recorded scope revision; it does not allow quietly skipping rows.

Legend: **[agent]** an agent can do it alone · **[you]** needs you (device, play, judgment) · **[Duo]** blocked until Duo hardware exists · **[decide]** a decision for you.

## 1. Finish G1 on the physical iPhone
- [x] **[you]** V03: 11.3 min of `user-01` at 100.0% of core target, 0 underruns, thermal fair at most (`artifacts/poc/2026-09-24-overnight-device/`).
- [x] **[you]** V02: on-device cartridge save survives close and relaunch (user-observed).
- [x] **[you]** V02: stylus taps land where touched (204 taps, ≤1 DS px mapping error).
- [x] **[you]** ⋯ menu items respond after the fix; manual Save/Restore state works on device (V20).
- [ ] **[agent]** Use a release-like build for G1/G3 numbers. Current builds are development-signed (`get-task-allow`); the report and the evidence manifest record this.

## 2. Features that are missing or unverified
| Item | State | Owner |
|---|---|---|
| Microphone input (V15): permission flow, core mic feed, safe fallback when denied | Implemented; passes on simulator (granted and denied) | [you] device: deny → grant → revoke, and a game that uses the mic |
| Manual save states (V20): save/restore with `user-01`; reject wrong-ROM, corrupt and old-version states | Done on simulator and iPhone (round trip user-observed); rejection cases unit-tested | — |
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
- [x] **[decide]** License: GPL-3.0-or-later for the app's own code; the source offer is the public repository at the build's commit (D19).
- [x] **[decide]** Development-signed G1 build accepted as release-like (D20). Decision: **CONDITIONAL GO** (REPORT.md).
- [ ] **[decide]** Distribution path: free team (7-day installs, personal only), TestFlight/paid account, or App Store. Check the current App Store rules for emulators at that time.
- [ ] **[decide]** BIOS/firmware policy. Today it uses the core's built-in FreeBIOS only. Some games may need real firmware, which users would have to supply themselves.
- [ ] **[decide]** Scope option A or B above.

## Release roadmap (product work, not POC exit criteria)
Added 2026-09-24. Items are ordered by priority within each tier; the suggested build order is Tier 1 top to bottom. Everything in Tiers 1–2 can be built and tested on the iPhone; Tier 3 needs Duo hardware to validate. Some items were deferred in EXECUTION_PLAN.md; they are listed here as post-POC work.

### Tier 1: needed for a credible release
- [ ] **Save backup export/import.** Per game: Export/Import Save (raw `.sav`; DeSmuME `.dsv` accepted) from the library's touch-and-hold menu. All games: Back Up All Saves / Restore from Backup (a plain ZIP of saves and manual states, no ROMs). — *built 2026-09-24, awaiting device test*
- [ ] **Library icons and titles.** Icon, title and publisher read from each game's banner; filename fallback. — *built 2026-09-24, awaiting device test*
- [ ] **Multiple save-state slots and an automatic state on exit.** Five slots with thumbnails and times (⋯ → Save States…); an automatic state when leaving a game or the app, used on the next launch (D21). — *built 2026-09-24, awaiting device test*
- [ ] **Fast-forward.** ▶▶ pill (toggle) and ⋯ menu; 2×/3×/4× in Settings; plays one frame's audio in N (D21). — *built 2026-09-24, awaiting device test*
- [ ] **3D performance headroom.** Threaded renderer now on by default (Settings → Performance). Still needed: a 30-minute 3D run (V08-style) on the iPhone, and on the oldest supported iPhone (iOS 17). — *built 2026-09-24, awaiting device test*
- [ ] **Settings screen.** Controls, haptics, volume/mute, fast-forward speed, resume toggle, DS profile (nickname, language, birthday, colour), threaded rendering. Gear in the Library; ⋯ → Settings… in game. — *built 2026-09-24, awaiting device test*
- [ ] **First-run help.** Empty-library screen; `.nds` files copied to the app's Files folder appear under "In your Duo DS folder" with an Add button. — *built 2026-09-24, awaiting device test*

### Tier 2: expected by experienced users
- [ ] Controller button remapping (after V17 verifies controller basics).
- [ ] Drag to place on-screen controls; per-game control layouts.
- [ ] Screen options: gap between screens, integer scaling vs. fill, smoothing filter.
- [ ] Screenshot of both screens to Photos.
- [ ] Import `.zip`/`.7z` archives and games shared from other apps.
- [ ] Cheat codes (Action Replay), if the pinned core supports them.
- [ ] Open a game from Shortcuts or a Home-screen icon.

### Tier 3: things that set it apart on the Duo
- [ ] Fold-aware layouts that feel like a real DS: half-folded with the top screen above the hinge and controls below.
- [ ] Optional physical lid: closing the Duo sends the in-game lid event (the POC deliberately left this out).
- [ ] Outer-screen play: a single-screen mode with a quick screen swap for playing while folded.

### Deferred until after launch
Cloud sync, rewind, higher internal resolution and shaders, local wireless or online multiplayer, DSi support, achievements. Measure the CPU cost of rewind and higher resolution without JIT before committing to them.

### Needed before release (not features)
- [ ] Distribution path: App Store vs. AltStore or other EU alternative marketplaces; resolve how the App Store's terms sit with the GPL (D19).
- [ ] Firmware/BIOS policy: built-in FreeBIOS by default; decide whether users may supply their own firmware for games that need it.
- [ ] Privacy manifest and privacy policy (currently no data collected), crash reporting decision, and a support contact.
- [ ] Broader game compatibility testing and a known-issues list.
