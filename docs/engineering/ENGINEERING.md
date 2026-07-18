# Work Agent — Engineering

**Status:** Living. Must always describe reality, never aspiration. Last substantive
change: 2026-07-18.

If this doc and the code disagree, the doc is a bug. Fix it in the increment that
caused the drift.

For *why* a choice was made, read the ADR. This doc says what is true now;
[docs/decisions/](../decisions/) says why and what we rejected.

---

## Current reality

Be clear about this: **the codebase is an unmodified Xcode SwiftUI template.** One
`ContentView.swift`, one `Work_AgentApp.swift`, a stub test file. Nothing below
describes working software except where it says so.

```
Work Agent.xcodeproj
Work Agent/
  Work_AgentApp.swift      App entry — template
  ContentView.swift        Template
  Assets.xcassets/
Work AgentTests/           Stub
Work AgentUITests/         Stub
docs/                      Specs (increment 1)
```

## Stack

| | | Why |
|---|---|---|
| Language | Swift | Native macOS is the point |
| UI | SwiftUI | — |
| Tests | swift-testing | ADR-0004 |
| Structure | Single app target, monolith | ADR-0002 |
| Distribution | Developer ID, notarized | ADR-0003 |
| Agent runtime | **Undecided** | ADR-0006, deferred |
| Min macOS | **Undecided** | Nothing needs it yet |

## Architecture

There isn't one yet, and that's deliberate rather than an omission. ADR-0002 commits us
to a monolith until we know where the seams are. The prior draft specified seven SPM
packages and a dependency graph before a single line of product code existed; we're not
repeating that.

The one structural commitment that exists today comes from the product thesis: **all
inference goes through a provider abstraction** (FR-001, NFR-001). That seam is real
before the code is, because it's the reason the product exists. Everything else earns
its boundary by hurting first.

## Testing

`swift-testing`, unit and contract. No XCUITest while the UI churns — it would dominate
increment time and tell us little.

Requirement IDs go in test display names:

```swift
@Test("FR-001: selecting a provider does not require a rebuild")
func providerSelectionIsRuntime() async throws { ... }
```

`rg "FR-001"` finds the requirement, the code, and the test. That's the whole scheme —
see [CLAUDE.md](../../CLAUDE.md) § Traceability for why there are no per-requirement
tags.

Tests are necessary and not sufficient. The DOD asks whether the deliverable was
actually run, because a green suite over a feature nobody exercised is how agents
convince themselves of things that aren't true.

## Conventions

- Requirement references at the point of satisfaction: `// REQ: FR-001 — <what and why>`.
  On the code that satisfies it, not on the file.
- Comments state constraints the code can't. Not what the next line does.
- No implementation vocabulary in user-facing strings (PRODUCT.md �2).

## Deferred, and why it's not here

No CI, no linter, no logging framework, no error taxonomy. Each is a real need, and
each is a decision better made with code to point at. They land in the increment that
needs them, with an ADR if there's a genuine alternative.
