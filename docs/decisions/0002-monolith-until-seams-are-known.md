# ADR-0002 — Monolith except for proven package seams

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni

## Context

Module boundaries are cheap to add and expensive to move. A wrong boundary drawn early
doesn't announce itself; it gets defended, because by then there's code on both sides of
it. Every subsequent decision routes around it. So boundaries here are derived from
evidence, not asserted up front.

The Foundation Models adaptation POC and the agent-framework comparison established one
concrete reusable boundary, and Toni confirmed it directly: "the Swift agentic
framework ... will be an SPM." On 2026-07-18 Toni also settled what the package
carries: the native tool implementations are "one of the most valuable parts of this
SPM" and "absolutely not in the app."

## Decision

**One SPM package, many small library products.** Swift's unit of encapsulation is the
module (target/product); the package is the unit of versioning. Pre-1.0, everything
co-evolving against a beta OS belongs in one package so releases stay atomic — but no
module inside it is allowed to sprawl. The product family and its dependency DAG are
specified in [plans/runtime-api.md](../plans/runtime-api.md) §6: the durable-run core,
the provider executors, the tool vocabulary and ToolKit tool products, testing
support, replay/evals, and MCP (isolated because it carries the one external
dependency).

The dependency direction is Work Agent app → runtime package products → iOS/macOS 27
Foundation Models. App UI, credentials, catalog, task storage, and tool *selection and
approval policy* remain in the app; tool *implementations* are package products. A
second package (or a repo split) is created only when release cadences demonstrably
diverge or an external consumer needs a piece standalone — a thing that happened, not
a thing that might.

## Considered options

**Monolith plus the one proven runtime package** *(chosen)* — Keeps speculative domain
boundaries out while enforcing the dependency direction that the POC and product thesis
now justify. Costs: package/API design overhead arrives in increment 4 rather than after
the app-local implementation.

**Many packages up front** — Clean from commit one, enforced dependency direction.
Rejected: separate packages version separately, and during OS-27 beta churn every
Apple ABI change would force coordinated releases across all of them. Small *products*
inside one package buy the same import hygiene without the release tax.

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
