# Copy-ready execution handoff

Paste the prompt below into the orchestration agent assigned to implement the POC. It assumes the agent can read this workspace; if running elsewhere, supply the repository containing these documents and replace the root path.

---

Implement the Duo DS proof of concept described in this repository. This is an execution request: produce a runnable prototype, validation evidence, and a go/no-go recommendation. It does not authorize App Store submission, external publication, messages to others, acquiring unauthorized games/firmware, or a new emulation core.

Workspace: `/Users/joryshilmover/Documents/Personal Programming/Duo DS emulator`.

Read in order:

1. Applicable `AGENTS.md` and `.codex/orchestrate.md`, then the available orchestrate skill.
2. `docs/poc/EXECUTION_PLAN.md` — scope, ownership, packages, and decision rules.
3. `docs/poc/RESEARCH.md` — evidence limitations and local preflight.
4. `docs/poc/TECHNICAL_DESIGN.md` — proposed contracts and architecture.
5. `docs/poc/VALIDATION.md` — authoritative acceptance targets and evidence requirements.

Use subagents for genuinely independent packages. Start by inspecting the current workspace, preserving existing changes, and checking toolchain/source availability. Create `docs/poc/WORK_LOG.md` and `docs/poc/DECISIONS.md`. Freeze shared contracts and build setup before parallel implementation. The root owns Xcode/build configuration and shared contracts; assign each worker exact disjoint files and an observable exit criterion. Follow the package/wave sequence; never let two workers edit the same project file concurrently.

The default is a native SwiftUI/UIKit app with a bundled, source-pinned melonDS DS core through a minimal libretro host, interpreter/no JIT, software rendering, and Metal presentation. Both emulated DS screens belong on the inner display. Use verified public layout-region APIs for geometry and hinge observations for appropriate interactions. Keep beta SDK integration behind an adapter. A fixture-based layout harness is useful but must never be counted as actual fold API or emulator validation.

At planning time Xcode 27.0/iOS 27.0 was selected; the newer Duo SDK was not verified locally. `simctl` runtime discovery failed due to access/service errors, so runtime availability is unknown. Recheck; do not repeat these observations as current facts without inspection. Continue ordinary-iPhone, core, persistence, and synthetic tests when Duo access is unavailable. No JIT workaround, private API, or camera-session workaround is allowed.

Use approved lawful assets, record provenance and hashes, and keep ROMs/BIOS/keys out of source and evidence bundles. Respect dependency licenses and retain source/build provenance. Resolve access and permissions through the normal environment mechanisms only when necessary; do not repeatedly ask for routine reversible work already covered by this execution request.

Run meaningful tests for touch transformations, callback lifetimes, audio pacing, saves, and lifecycle. Build and test against actual available destinations. Collect physical-device evidence according to the validation matrix; host/simulator timing is not physical-device performance. Do not mark target-hardware gates passed based on documentary support or another emulator's behavior.

Before final handoff, use a fresh read-only reviewer to challenge the implementation and claimed evidence. Integrate necessary fixes and rerun affected checks. Return links to build/run instructions, the pinned dependency/license inventory, the evidence report, and unresolved findings. State each gate as passed, failed, blocked, or not run. Select GO, CONDITIONAL GO, or NO-GO exactly as the execution and validation documents define; report assessment pending if baseline evidence is unavailable and no decisive failure exists. A hardware-blocked conditional handoff must clearly state that the full POC remains incomplete.

Begin with P0 preflight and P1 build/contracts; do not stop after proposing another plan.

---

## Worker assignment template

```text
Package: <P-number and name>
Goal: <one observable outcome>
Read: <exact plan sections and frozen contract revision>
Inputs: <source commit, fixture manifest, available destinations>
Owned files: <exact disjoint paths>
Do not edit: <project files/shared headers/other owners' modules>
Dependencies: <completed packages or provided fixtures>
Acceptance: <named tests and evidence required by VALIDATION.md>
Stop rule: <bounded investigation time; report missing access/contracts>
Return: changed files, commands with results, artifact paths, unresolved
failures, assumptions, and next action. Do not claim a gate passed on
simulation or documentary evidence when hardware is required.
```

## Reviewer assignment template

```text
Read-only review of the actual implementation and evidence. Use the
adversarial-review skill. Check the invariants in TECHNICAL_DESIGN.md
and acceptance criteria in VALIDATION.md. Prioritize unsafe callback
lifetimes, dual session creation, incorrect touch transforms, audio
clock drift, held inputs after transitions, save corruption, unintended
JIT dependence, fake fold integration, and unsupported benchmark claims.
Construct concrete failure sequences. Run authorized checks when useful.
Label each finding ran/tested/reasoned and cite files or evidence paths.
Do not edit files. Return ranked findings, what held, and what could not
be verified. Passing tests or a worker's confidence alone is not proof.
```
