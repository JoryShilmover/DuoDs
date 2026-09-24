# Duo DS proof of concept

Execution handoff for a native iOS Nintendo DS emulator that uses the folding inner display of iPhone Duo. A work-in-progress prototype (SwiftUI app, melonDS DS core via a minimal libretro host, layout/input, library/saves) is in the tree. Current status and resume steps: [work log](docs/poc/WORK_LOG.md); gate results: [evidence report](docs/poc/REPORT.md); what's left: [exit checklist](docs/poc/EXIT_CHECKLIST.md). Build: `scripts/build-poc.sh`; tests: `scripts/test-poc.sh`.

**Start here:** [Execution plan](docs/poc/EXECUTION_PLAN.md). To dispatch the work to another orchestration agent, use the [handoff prompt](docs/poc/HANDOFF.md).

| Document | Purpose |
| --- | --- |
| [Execution plan](docs/poc/EXECUTION_PLAN.md) | Scope, dependency graph, work packages, agent ownership, gates, and completion rules |
| [Technical design](docs/poc/TECHNICAL_DESIGN.md) | Runtime, core integration, screen composition, input, audio, and persistence contracts |
| [Validation](docs/poc/VALIDATION.md) | Test cases, measurement procedure, acceptance targets, and evidence templates |
| [Research and preflight](docs/poc/RESEARCH.md) | Sources, evidence confidence, local environment, and assumptions to recheck |
| [Handoff prompt](docs/poc/HANDOFF.md) | Copy-ready instructions for the execution orchestrator |

Planning baseline: September 23, 2026. Product details and beta SDK APIs must be rechecked at execution time. The intended first result is a reproducible prototype and an evidence-backed go/no-go decision, not an App Store release.
