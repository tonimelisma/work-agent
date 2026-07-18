# ADR-0002 — Monolith until the seams are known

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni

## Context

The inherited roadmap draft opened with "Phase 0": create seven Swift packages
(`WorkAgentContracts`, `Client`, `UI`, `Core`, `Mac`, `Sandbox`, `Connections`), a
dependency graph, an `AgentClient` protocol, and a mock implementation — before any
product code ran.

Those boundaries were invented by an agent that had never seen the domain, for a product
whose requirements didn't exist. They might be right. Nothing about them was derived
from anything.

Module boundaries are cheap to add and expensive to move. A wrong boundary drawn early
doesn't announce itself; it gets defended, because by then there's code on both sides of
it. Every subsequent decision routes around it.

The codebase today is an Xcode template. We do not know where this system wants to be
divided.

## Decision

Build in the single existing app target. Extract SPM packages only when a specific seam
demonstrably hurts — slow builds, a real testability problem, an actual reuse need.

**One exception**, and it's derived rather than guessed: the provider abstraction
(FR-001, NFR-001). That seam exists because model neutrality is the product thesis, not
because it looks tidy. It doesn't have to be a package to be a boundary.

"It hurts" means something happened. Not that it might.

## Considered options

**Monolith, extract on pain** *(chosen)* — Boundaries derived from evidence. Fastest to
a working product. Costs: a period of genuinely ugly code, and the risk that "extract
later" becomes "never," leaving a ball of mud. Mitigated by the fact that there's one
developer and no coordination cost to refactoring.

**The draft's seven packages up front** — Clean from commit one, enforced dependency
direction, UI provably can't import tool implementations. Rejected: it commits to a
domain model we don't have, and the enforcement it buys is enforcement of a guess. Weeks
before anything runs. This is the specific failure the draft exhibits.

**Two packages: Core and UI** — A middle path with the one boundary most projects
eventually want. Genuinely tempting. Rejected because even this is a guess: the real
split may be provider/runtime/UI, or task-engine/everything-else. Picking the *plausible*
boundary early is still picking early, and half-right boundaries are the hardest to move
because they're defensible.

**Never extract; monolith forever** — Honest for a solo project and cheaper than anyone
admits. Rejected as a *commitment* rather than as an outcome: if the app ships and build
times stay tolerable, this is where we end up, and that's fine. We're not deciding
against it, we're declining to decide for it.

## Consequences

**Good.** Product code in increment 3, not increment 8. Boundaries, when they come,
answer real questions. Refactoring is cheap now and stays cheap while there's one
developer.

**Bad.** The code will get ugly before it gets extracted, and it may get ugly enough
that extraction is a real project rather than a move. There's no compiler-enforced
guardrail against the UI reaching into things it shouldn't — the discipline is
convention only, and conventions lose to deadlines.

**Watch for.** Build times over ~30s, a test that can't be written without a boundary,
or a second developer. Any of those makes this ADR due for supersession.
