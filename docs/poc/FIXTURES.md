# Lawful fixture manifest

`duo-diagnostic-v1` is original assembly in `Fixtures/Diagnostic`, MIT licensed. `scripts/build-fixture.py` assembles it using Apple clang and constructs a homebrew header without copyrighted logo/BIOS/firmware assets. Output stays under ignored `build/fixtures/`.

Initial output SHA-256: `fbfb9cc8b209c75294511699cca02be0db4a136ec5faa1d927a5526b7ec4ad39` (131072 bytes). Build-generated manifest is authoritative after source changes.

Intended checks: two native 2D bitmaps, visible frame advancement, button-dependent color, generated PSG audio; explicit emulated lid via core. Runtime behavior must be observed before a check passes.

Not covered: 3D workload, touch-coordinate reporting, microphone, cartridge save, homebrew SD save, supported serialization. In particular this fixture cannot pass V02's persistent-save requirement or V20. No approved serialization-capable title or cartridge-save fixture has been supplied. Do not acquire commercial content to fill that gap.

No generated ROM, BIOS, firmware, save or state is tracked. User content is imported locally through the system picker. Raw evidence cannot include those assets.
