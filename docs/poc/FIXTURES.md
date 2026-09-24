# Lawful fixture manifest

`duo-diagnostic-v1` is original assembly in `Fixtures/Diagnostic`, MIT licensed. `scripts/build-fixture.py` assembles it using Apple clang and constructs a homebrew header without copyrighted logo/BIOS/firmware assets. Output stays under ignored `build/fixtures/`.

Initial output SHA-256 was `fbfb9cc8…ad39`; it rendered black because BG2CNT selected a paletted bitmap (0x4080). Fixed to direct color (0x4084): current SHA-256 `c8c5e019171b5ede3842f4de48444ac6a77865c8fb9dfe1804c09d867005d175` (131072 bytes). Build-generated manifest is authoritative after source changes.

Observed 2026-09-23 on iPhone Duo simulator (iOS 27.1): both native bitmaps lit (top 47616 / lower 49152 non-black pixels), frames advance at core 59.83 Hz, PSG audio produced/consumed. Button-dependent color observed via `--selftest` (top-screen mean G 0 → 8 → 0 on A hold/release). Lid not observable: the fixture does not read lid state.

Intended checks: two native 2D bitmaps, visible frame advancement, button-dependent color, generated PSG audio; explicit emulated lid via core. Runtime behavior must be observed before a check passes.

Not covered: 3D workload, touch-coordinate reporting, microphone, cartridge save, homebrew SD save, supported serialization. In particular this fixture cannot pass V02's persistent-save requirement or V20. No approved serialization-capable title or cartridge-save fixture has been supplied. Do not acquire commercial content to fill that gap.

No generated ROM, BIOS, firmware, save or state is tracked. User content is imported locally through the system picker. Raw evidence cannot include those assets.

## User-supplied corpus

`user-01`: a commercial DS title supplied by the user for local testing (cartridge save, 3D overworld). Identifier and SHA-256 are kept privately in ignored `artifacts/poc/private-corpus.md`, never in the repository. Placed in the simulator's Files "On My iPhone" storage for import through the app's file picker. No BIOS/firmware supplied; the core's built-in FreeBIOS is used, so compatibility is not guaranteed.
