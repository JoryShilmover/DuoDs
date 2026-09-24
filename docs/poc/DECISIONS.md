# Execution decisions

- D01: Preserve current main checkout at e2558fe. No publishing or git push.
- D02: Pin melonDS DS v1.3.1 (bc4e4b67d2d470d7c682810a1e892cafd6f9082b); interpreter, software renderer, networking/dynamic loading disabled. Minimal source patch may select STATIC library instead of upstream MODULE; retain patch and licenses.
- D03: Baseline minimum iOS 17. Synthetic display adapter until public Duo declarations and runtime can be compiled/tested. No invented selectors or guessed hinge geometry in production adapter.
- D04: Host tests are plumbing evidence only. Physical baseline, approved save/state fixtures, signing, and Duo gates remain independent.
- D05 (user update): Xcode-Beta 27.1 (27A9269), iOS 27.1 SDK and booted iPhone Duo simulator now verified locally. Use per-command DEVELOPER_DIR; supersedes D03's temporary synthetic-only SDK limitation.
- D06 (user instruction): Simulator testing only for this run. Hold off physical device deployment/testing. Personal development team requested for future device signing. G1/G3 remain not run/blocked as applicable; no hardware performance claims.
- D07: melonDS DS declares need_fullpath=false, so the bridge reads the ROM into a host-owned buffer that lives until unload and passes data/size (previously path only → "Loaded an empty file as content").
- D08: Every user-visible AppModel message is also written to os_log (subsystem org.duods.prototype) and session-events.jsonl (`event: message`), and checkpoints record lit-pixel counts per DS screen, so agents can diagnose without screenshots.
- D09: `--diagnostic` auto-launch runs only after the scene is active; launching earlier booted straight into paused (startup race).
- D10: P5 behavior is verified by an in-app `--selftest` driving the same EmulationSession/AppModel APIs as the UI. It does not exercise UIKit touch delivery; UI touch/drag checks still need an XCUITest target or manual trial.
- D11: Layout scoring is lexicographic: first "reserves a usable control band with both screens ≥170 pt", then smallest-screen width. Split still wins ties. Larger screens with unusable controls are not an acceptable trade.
