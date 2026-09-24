# Execution decisions

- D01: Preserve current main checkout at e2558fe. No publishing or git push.
- D02: Pin melonDS DS v1.3.1 (bc4e4b67d2d470d7c682810a1e892cafd6f9082b); interpreter, software renderer, networking/dynamic loading disabled. Minimal source patch may select STATIC library instead of upstream MODULE; retain patch and licenses.
- D03: Baseline minimum iOS 17. Synthetic display adapter until public Duo declarations and runtime can be compiled/tested. No invented selectors or guessed hinge geometry in production adapter.
- D04: Host tests are plumbing evidence only. Physical baseline, approved save/state fixtures, signing, and Duo gates remain independent.
- D05 (user update): Xcode-Beta 27.1 (27A9269), iOS 27.1 SDK and booted iPhone Duo simulator now verified locally. Use per-command DEVELOPER_DIR; supersedes D03's temporary synthetic-only SDK limitation.
- D06 (user instruction): Simulator testing only for this run. Hold off physical device deployment/testing. Personal development team requested for future device signing. G1/G3 remain not run/blocked as applicable; no hardware performance claims.
