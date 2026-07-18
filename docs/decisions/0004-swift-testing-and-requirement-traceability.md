# ADR-0004 — swift-testing, with requirement IDs in test names

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni

## Context

Requirements carry permanent IDs (`FR-001`, `NFR-001`) and code must point back at them
(NFR-005). For that to be more than decoration, a requirement's tests have to be
findable from its ID, and an unimplemented requirement has to be visible as one.

Two questions, and they're coupled: which test framework, and how IDs attach to tests.

The second matters more than it looks. Traceability schemes fail by being too expensive
to maintain — every ID needing a declaration somewhere, every new requirement touching a
registry. The maintenance cost gets paid a hundred times; the benefit is diffuse. Cheap
schemes survive. Expensive ones get abandoned halfway, which is worse than never
starting, because a half-maintained trace is a trace that lies.

## Decision

**swift-testing**, unit and contract tests. No XCUITest for now.

Requirement IDs go in the test's display name:

```swift
@Test("FR-001: selecting a provider does not require a rebuild")
func providerSelectionIsRuntime() async throws { ... }
```

and in code at the point of satisfaction:

```swift
// REQ: FR-001 — provider adapters are selected at runtime, never compiled in.
```

`rg "FR-001"` returns the requirement, the code, and the tests. That's the mechanism.
No registry, no per-ID declaration, nothing to keep in sync.

## Considered options

### Framework

**swift-testing** *(chosen)* — Modern, async-native, parameterized tests, better failure
output, Apple's direction. Costs: younger, less written about, and Xcode integration is
still occasionally rough.

**XCTest** — Mature, universally documented, every answer already exists online.
Rejected: no meaningful advantage for a greenfield project, and it's the framework being
migrated away from. Starting on it means a migration later for nothing.

**Both** — XCTest for UI, swift-testing for units. Rejected for now with XCUITest below;
revisit if UI tests ever earn their place.

### Attaching IDs

**Display name** *(chosen)* — Zero maintenance cost. Greppable. Visible in failure
output, which means a failing test names the requirement it broke. Costs: no
`--filter`-by-requirement, and nothing enforces the format — a typo'd ID is invisible
until someone greps and finds nothing.

**A `@Tag` per requirement** — Real filtering: run every test for FR-001. Rejected on
cost: swift-testing tags are static members, so each ID needs a declaration in a Tag
extension, forever, growing with the requirements doc. That's the expensive scheme that
gets abandoned. If filtering ever becomes worth that price, this ADR gets updated —
and the display names remain valid alongside tags, so it's not a one-way door.

**A traceability matrix file** — Explicit, auditable, the classic answer. Rejected: a
third artifact to keep in sync with two others, and it's stale the first time someone's
in a hurry. Grep can't lie about what's in the code; a matrix can.

**Comments only, no test-name convention** — Simplest. Rejected: it makes requirements
traceable to code but not to *evidence*, which is the half that matters. "FR-001 is
implemented" and "FR-001 is verified" are different claims.

### XCUITest

**Skip it** *(chosen)* — Slow, flaky, and it would dominate increment time while the UI
changes weekly. It would also be the layer that most directly demonstrates acceptance
criteria, which is a real loss, honestly stated. The DOD's "I ran it" line is the
stopgap, and it's a human check, not an automated one.

## Consequences

**Good.** Traceability costs a substring in a string literal. `rg "FR-0"` across
`docs/` and code shows, roughly, which requirements have evidence. Nothing to abandon
because there's nothing to maintain.

**Bad.** Nothing enforces the ID format or catches a reference to a requirement that
doesn't exist. A renamed test silently drops its trace. No filtering by requirement. The
scheme relies entirely on discipline, and its failure mode is quiet — traces don't break
loudly, they just stop being true.

**Watch for.** If `rg` starts returning noise, or IDs drift out of test names, a linter
in CI is the cheap fix and doesn't need a new ADR. Wanting filtering does.
