# AgentKit — Working Agreement

This repo is a native Swift SPM package: an agent runtime, provider executors, and
native tool implementations on top of Apple's Foundation Models framework (macOS 27 /
iOS 27). The Work Agent macOS app still lives here but is moving to its own repo —
[docs/plans/app-carveout.md](docs/plans/app-carveout.md) — and is not this repo's
subject. MIT licensed, Toni Melisma.

**The thesis:** the Swift model-access layer is commoditizing (Apple's protocol,
vendor packages, community clones); the durable work layer above it is empty. We
build that layer, model-neutral and local-first, with the Work Agent apps as the
canonical reference implementations.

---

## The process

A one-way pipeline. Each step has one input and one output document. Work flows
forward only; documents never share a role.

```
                 ┌──────────────┐
  strategy ────▶ │ 1 research/  │ ◀──── anything learned during any step
                 └──────┬───────┘
                        ▼
                 ┌──────────────┐   future only: prioritized features & vision.
  refinement ──▶ │ 2 ROADMAP.md │   The only place work is picked from.
                 └──────┬───────┘
                        ▼
                 ┌──────────────┐   a smarter agent turns the top roadmap items
  planning ────▶ │ 3 plans/     │   into codebase- and research-verified plans
                 └──────┬───────┘   detailed enough to implement without questions
                        ▼
                 ┌──────────────┐   a cheaper agent implements a plan, then writes
  execution ───▶ │ 4 the code   │   down what now exists:
                 └──────┬───────┘
                        ▼
        ┌───────────────┴───────────────┐
        ▼                               ▼
 ┌──────────────┐              ┌────────────────┐
 │ 5 PRODUCT.md │              │ 6 ENGINEERING  │   implemented product features     /
 │  implemented │              │  implemented   │   implemented architecture,
 │  features +  │              │  design + why  │   with rationale for every
 │  why, w/ IDs │              │  it works so   │   decision made
 └──────────────┘              └────────────────┘
                        ▼
                 ┌──────────────┐   a smarter agent audits the built work against
  review ──────▶ │ 7 top-up     │   the plan and PRODUCT/ENGINEERING; findings
                 │   plans/     │   become top-up plans and new ROADMAP items
                 └──────────────┘
```

**Step by step:**

1. **Research** (`docs/research/`) — produced whenever something is learned the hard
   way, in strategy *or* execution. Topic-named, living, last-verified dates,
   evidence not just conclusions. Input: the outside world. Output: a doc nobody has
   to re-derive.
2. **Roadmap** (`docs/product/ROADMAP.md`) — the future, and only the future:
   features and vision in priority order, each item with enough words to plan from,
   traceable to Toni. No status log, no history — a shipped item is deleted from the
   roadmap (PRODUCT.md now owns it). Input: strategy sessions + review findings.
   Output: an ordered backlog.
3. **Planning** (`docs/plans/`) — a smarter agent takes the top roadmap item(s) and
   writes an implementation plan: verified against the actual codebase and the
   research, specific enough that the implementing agent needs no product judgment.
   The plan is the quality gate — there is no separate DOR ceremony. Open questions
   that need Toni are resolved *while planning*, not left in the plan. Input:
   roadmap item + codebase + research. Output: an executable plan.
4. **Execution** — a cheaper agent implements the plan in a worktree with a PR
   (doc-only changes go straight to main). Blocked or surprised → stop and say so;
   never improvise product decisions.
5. **Product record** (`docs/product/PRODUCT.md`) — the implementer documents each
   shipped feature: what it does, its permanent FR/NFR IDs, and *why it was built
   this way*, quoting Toni where he decided. Implemented only.
6. **Engineering record** (`docs/engineering/ENGINEERING.md`) — the implementer
   updates the as-built architecture: how it works and the rationale for every
   structural decision (this doc absorbed the old ADRs; there is no separate
   decisions log). Reality only, never aspiration.
7. **Review** — a smarter agent audits the last N increments: code vs plan vs
   PRODUCT/ENGINEERING claims. Findings become top-up plans in `plans/` and/or new
   roadmap items. Output: errata the pipeline consumes like any other work.

After execution the consumed plan is **deleted** — its content now lives in code,
PRODUCT, and ENGINEERING. Plans directory always contains only the unimplemented.

**The five documents, one line each:**

| Doc | Role | Tense |
|---|---|---|
| [docs/research/](docs/research/) | What we learned, with evidence | timeless |
| [docs/product/ROADMAP.md](docs/product/ROADMAP.md) | Vision and features we intend to build, prioritized | future only |
| [docs/plans/](docs/plans/) | Verified implementation plans for the top roadmap items | future only, deleted on completion |
| [docs/product/PRODUCT.md](docs/product/PRODUCT.md) | Features that exist, their IDs, and why they're shaped this way | past only |
| [docs/engineering/ENGINEERING.md](docs/engineering/ENGINEERING.md) | Architecture that exists and the rationale behind it | past only |

Docs are MECE: a fact lives in exactly one place and is linked from the others. No
stale references, ever — the change that invalidates a mention scrubs it in the same
commit. Git history is the only archive; nothing in the working tree memorializes a
dead decision.

---

## Non-negotiables

0. **Never invent direction.** Roadmap items, plan decisions, and product claims
   trace to something Toni actually said — quoted, not inferred. What he hasn't
   decided is an open question to ask during planning, never a thing to write down
   and let become true. A fabricated decision is worse than a missing one.
1. **Docs lose to Toni.** If any doc contradicts what he just asked for, surface the
   contradiction in one sentence and, on his confirmation, update the doc in the
   same increment. Never use a doc to refuse a request — but first check the doc's
   claim actually came from him.
2. **Everything shipped is recorded.** No feature lands without its PRODUCT.md entry
   and ID; no structural choice lands without its ENGINEERING.md rationale. A record
   describing last month's behavior is worse than none.
3. **Research is written without being asked** whenever redoing the work would cost
   real effort. Trivial lookups stay in the transcript.
4. **Honest reports.** Gaps are named, never silently skipped. Tests that didn't run,
   features not exercised live, keys nobody had — say so in the PR and the docs.

## Traceability

Permanent, flat IDs: `FR-001` / `NFR-001`, minted during planning from Toni's words,
written as individually testable [EARS](https://alistairmavin.com/ears/)-style
statements (*The system shall… / When X, the system shall…*), recorded in PRODUCT.md
when implemented. **Never reused, never renumbered**; dropped
IDs are deleted outright and PRODUCT.md tracks the next-free counters. In code, at
the point of satisfaction:

```swift
// REQ: FR-006 — failed provider attempts fail over automatically; the switch is traced.
```

In tests, the ID goes in the display name. `rg "FR-006"` finds the feature record,
the code, and the tests — grep is the whole traceability system.

## Local provider credentials

The repository-root `.env` (gitignored) supplies provider API keys for live probes
and gated smoke tests. Check a key's presence with a non-printing test before
reporting it unavailable; source `.env` in the invoking shell for authorized live
probes. Never print keys, persist them in fixtures, or copy them into traces; scrub
recorded provider traffic before committing.

## Conventions

- Swift 6, strict concurrency, swift-testing. One SPM package (many small products —
  module = encapsulation, package = versioning); the app targets leave with the
  carve-out. Dependencies: Apple frameworks only, except ZIPFoundation, SwiftSoup,
  and (opt-in) the MCP swift-sdk.
- **Never add UI tests.** Coverage is unit and contract level; acceptance is
  verified by running things.
- Code increments: worktree + PR, squash merge, delete branch. Doc-only increments:
  straight to main.
- No secrets in commits. No telemetry anywhere in the package.

`AGENTS.md` is a symlink to this file.
