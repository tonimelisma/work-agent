# Work Agent — Working Agreement

Native macOS app: an AI agent that does real work on the user's Mac, for people who
are not developers and not power users.

**The thesis:** every competing agent is welded to one vendor's model. We bet inference
commoditizes and the durable value is at the app layer. Model neutrality is not a
feature of this product — it is the reason it exists. Any decision that quietly
couples us to one provider is wrong by default.

---

## The docs

Read the ones your increment touches. Do not read all of them by reflex.

| Doc | Answers | Rule |
|---|---|---|
| [docs/product/PRODUCT.md](docs/product/PRODUCT.md) | What are we building, for whom, why, and what are we *not* building | Changes when the product bet changes |
| [docs/product/REQUIREMENTS.md](docs/product/REQUIREMENTS.md) | What must be true, testably, with IDs | Changes every increment that adds or alters behavior |
| [docs/product/ROADMAP.md](docs/product/ROADMAP.md) | What order, and what's deliberately deferred | Changes when sequencing changes |
| [docs/engineering/ENGINEERING.md](docs/engineering/ENGINEERING.md) | How the system is built *right now* | Always reflects reality — never aspiration |
| [docs/decisions/](docs/decisions/) | Why we chose this over the alternatives | Kept up to date and MECE; updated when the decision changes, deleted when stale |
| [docs/research/](docs/research/) | What we learned from outside this repo | Living — update in place, don't append journal entries |
| [docs/plans/](docs/plans/) | What we intend to build and how, in enough detail to start | A proposal until its increment's DOR; decisions recorded in place as Toni makes them |

**ENGINEERING.md vs ADRs** is the distinction people get wrong. ENGINEERING.md says
*what is true now*; an ADR says *why we chose it*, with the alternatives and their
tradeoffs. Both are living: when a decision changes, its ADR is updated in place, and
an ADR whose decision no longer matters is deleted. Git history is the archive —
nothing in the working tree exists to memorialize a dead decision.

These docs are MECE. If a fact belongs in two of them, it belongs in one and is linked
from the other. Duplicated facts drift and then lie.

---

## Non-negotiables

0. **Never invent a requirement.** Every requirement traces to something Toni actually
   said. Not to something he implied, not to a reasonable inference from what he said,
   not to what a sensible product would obviously need. If he hasn't said it, it is an
   **open question**, and open questions go in a list and get asked — they do not get
   written down as requirements and then quietly become true.

   This has already gone wrong once. FR-002 required a locally-hosted open model because
   Toni said "maybe there's a great cheap open source model that will do the trick," and
   an agent turned *open-source model* into *locally-hosted model*. He then had to argue
   against his own spec to correct a thing he never said. That is the failure this rule
   exists to prevent, and it is exactly what made the original inherited draft worthless.

   A fabricated requirement is worse than a missing one. A missing requirement is a
   question. A fabricated one is a lie with an ID that code gets written against.

   When drafting a requirement from a conversation, quote the words it came from. If you
   can't, you're inventing.

1. **Specs are the source of truth, and they lose to you.** If a requirement or ADR
   contradicts what Toni just asked for, that is not a blocker and not an argument.
   Surface it as a clarification — "this contradicts FR-062 / ADR-0003, are we changing
   that decision?" — and if the answer is yes, update the spec *in the same increment*.
   Never leave code and spec disagreeing. Never use a spec to refuse a request.

   **But first check the spec is real.** Before telling Toni his request contradicts a
   requirement, confirm that requirement came from him. If it didn't, the contradiction
   is fiction and raising it wastes his time defending a position he never took.

2. **Every behavior change updates the requirements.** No exceptions, including for
   changes that feel too small to document. A requirement that describes last month's
   behavior is worse than no requirement.

3. **Requirements have IDs and code points back.** See Traceability below.

4. **Research gets written down without being asked.** Any external lookup or POC that
   took real work — API availability, performance measurements, whether a framework can
   actually do the thing — produces or updates a doc in `docs/research/`. The test is:
   *would we have to redo this work to know it again?* If yes, write it. Trivial lookups
   stay in the transcript.

5. **Prefer larger increments.** The process below has fixed overhead. Amortize it. An
   increment should be a meaningful, deliverable slice — not a chore.

---

## Traceability

Requirements use flat, prefixed, permanent IDs: `FR-001` (functional), `NFR-001`
(non-functional). **IDs are never reused and never renumbered.** A dropped requirement
is **deleted outright** — no tombstone rows, no "Removed" status lingering in the doc.
Git history is the archive; REQUIREMENTS.md records the next-free ID counters so a
dead number is never handed out again. Renumbering breaks every reference in the
codebase, which is the whole failure mode we're avoiding.

**No stale references, ever.** The increment that drops or changes a requirement
scrubs every mention of it — ROADMAP, ENGINEERING.md, plans, code comments, tests —
in that same increment. All docs are always up to date; a doc citing a dead ID is a
bug, not a historical curiosity. ADRs included — they are kept up to date like
everything else.

In code, at the point where the requirement is actually satisfied:

```swift
// REQ: FR-001 — provider adapters are selected at runtime, never compiled in.
```

In tests, the ID goes in the display name so it's greppable with zero ceremony:

```swift
@Test("FR-001: selecting a provider does not require a rebuild")
func providerSelectionIsRuntime() async throws { ... }
```

We deliberately do **not** declare a Swift Testing `@Tag` per requirement. Tags would
give us `--filter` by requirement, but cost a tag declaration per ID forever. If we
later want filtering badly enough to pay that, an ADR revisits it.

Grep is the traceability tool: `rg "FR-001"` finds the requirement, the code, and the
tests. If it finds only the requirement, the requirement is unimplemented — that is a
signal, not a bug in the scheme.

---

## Increment workflow

An increment is one unit of deliverable work. **Code increments** use a worktree and a
PR. **Doc-only increments** commit straight to main — no worktree, no PR — since they
can't break anyone else's build.

### Doc increments: the lightweight path

Doc increments skip the full DOR/DOD ceremony below — that machinery exists to stop
code being built on unverified assumptions, and a doc can't ship a bug to a build.
What replaces it:

**Gate (one question):** did Toni ask for this, and is what he asked for clear? An
explicit request for research or a doc *is* the go-ahead — no separate DOR post, no
waiting. Anything beyond what he asked for is an open question to ask, not a thing to
write (Non-negotiable 0 applies to docs with full force — it was invented for one).

**Done (short report, honest):**
- Content traces to what was actually said, read, or measured — sources named,
  Toni's words quoted where they're the authority
- MECE holds: each fact lives in one doc and is linked from the others
- Indexes and cross-references updated (research README, this file's doc table)
- Committed straight to main, and anything stale the work uncovered is flagged
  rather than silently left

Everything below this line is the **code-increment** process.

### Before starting: Definition of Ready

**The DOR is a gate, not an announcement.** Post the list, then stop. Toni gives an
explicit go-ahead. No code is written before that go-ahead — not a scaffold, not a
"quick start while we discuss," nothing. Posting a DOR and building in the same turn is
not a DOR; it's a courtesy notice, and it defeats the entire point of aligning first.

If any item is ❌ or ⚠️, that is the thing to resolve. It is never a thing to note and
proceed past.

- ✅/❌ **Every requirement in play traces to something Toni said** — quote it. Requirements
  I inferred are open questions, not requirements. See Non-negotiable 0.
- ✅/❌ The requirement is clear, and we know which FR/NFR IDs are in play (new or existing)
- ✅/❌ We know which specs change: requirements, ENGINEERING.md, which ADRs
- ✅/❌ Any decision with real alternatives has an ADR planned, not an assumption
- ✅/❌ We have read the affected code paths and can say concretely how they change
- ✅/❌ Research needed to make this decision is done, or is explicitly this increment's first step
- ✅/❌ **Toni has given an explicit go-ahead.** His words, this increment. Not inferred
  from enthusiasm, not from "let's build," not from a previous increment's approval.

Don't fake a ✅. A ❌ with a sentence about why is the point of the list.

### During

The DOR comes first. Only once it's clear and the work begins does the rest of this run —
starting with the review backlog.

**First task of the work: triage open review comments.**

1. Read the review comments on the **last 10 PRs** (`gh pr list --state all --limit 10`,
   then `gh api` per PR). A comment is **unclaimed** if nobody has replied to take it.
2. **Claim each one you'll act on by replying to it** — so parallel agents don't collide.
3. **Fix them properly. No band-aids.** A review comment is a defect in the design or the
   code; the fix addresses the cause, not the symptom. If a comment is wrong or stale,
   reply saying why you're not acting — don't silently skip it.
4. Fixes ride in this increment's normal commits and specs (a behaviour change updates
   requirements, etc.). Empty backlog: say so in one line and move on.

Then the increment's actual work:

```bash
git worktree add ../wa-<slug> -b <slug>    # code increments only
```

Work in the worktree. Doc-only increments that won't collide with another agent skip
this entirely and commit to main.

### Before finishing: Definition of Done

Post this list with ✅/❌ per item. A ❌ needs a sentence saying why it's acceptable —
or it isn't done.

- ✅/❌ The deliverable works, and I verified it by running it — not by inferring from tests
- ✅/❌ Tests written for the new requirement IDs, and the full suite is green (paste the result)
- ✅/❌ Requirements updated: new IDs added, changed IDs edited, dropped requirements deleted and every reference to them scrubbed
- ✅/❌ ENGINEERING.md reflects reality after this change
- ✅/❌ ADRs written for decisions made; ADRs whose decision changed updated in place; stale ADRs deleted
- ✅/❌ Research docs written or updated for anything learned the hard way
- ✅/❌ CLAUDE.md updated if the process itself changed
- ✅/❌ Code references its requirement IDs
- ✅/❌ Review comments claimed this increment are fixed at the cause, and annotated with
  where — done after merge (see First: triage open review comments)

Then:

```bash
gh pr create ...          # code increments
# squash merge, delete branch
git worktree remove ../wa-<slug>
git branch -d <slug>
# then: reply to each claimed review comment with where it was fixed
```

Report the DOD list honestly. A red ❌ that's explained is useful. A green ✅ that's
wrong destroys the value of every other line.

---

## Conventions

- Swift, SwiftUI, `swift-testing`. Monolith for now — SPM packages get extracted when
  we know where the seams are, not before. See ADR-0002.
- **Never add UI tests.** The project has no UI-test target and will not gain one;
  acceptance is verified by running the app, while automated coverage stays unit and
  contract-level.
- Distribution is Developer ID + notarized, never Mac App Store. The sandbox would
  forbid most of what this product does. See ADR-0003.
- Never present MCP, tool schemas, JSON-RPC, OAuth scopes, or AXUIElement to the user.
  They are implementation. Users see work, sources, actions, and approvals.

`AGENTS.md` is a symlink to this file.
