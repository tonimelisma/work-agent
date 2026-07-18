# ADR-0002 — Monolith except for proven package seams

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

The codebase began as an Xcode template. The Foundation Models adaptation POC and the
agent-framework comparison have now established one concrete reusable boundary, and
Toni confirmed it directly: "the Swift agentic framework ... will be an SPM."

## Decision

Keep product code in the single app target by default. Introduce one SPM package for the
native Swift agent runtime described by ADR-0006. Its boundary is now evidenced rather
than guessed: it has an independent conformance harness, a platform substrate, a clear
dependency direction, and a reusable developer-facing purpose distinct from the app.

The resulting dependency direction is Work Agent app → Swift agent-runtime package →
macOS 27 Foundation Models. App UI, credentials, catalog, task storage and product tool
policy remain outside the package. No other SPM package is created until a specific
seam demonstrably hurts through slow builds, a real testability problem or actual reuse.

"It hurts" means something happened. Not that it might.

## Considered options

**Monolith plus the one proven runtime package** *(chosen)* — Keeps speculative domain
boundaries out while enforcing the dependency direction that the POC and product thesis
now justify. Costs: package/API design overhead arrives in increment 4 rather than after
the app-local implementation.

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

**Good.** Product code arrived before package design, so the one extracted boundary
answers measured questions. The compiler will enforce that the reusable runtime cannot
reach into app UI, credentials or storage.

**Bad.** Increment 4 must design a public package API while integrating the first
durable task. Moving app conveniences across the boundary now requires explicit
protocols instead of direct access.

**Watch for.** Pressure to move app-specific state or UI conveniences into the runtime
package, or to split the package into a graph of speculative modules. Build times over
~30s, a test that cannot be written without another boundary, real reuse, or a second
developer are evidence to revisit this ADR; neatness alone is not.
