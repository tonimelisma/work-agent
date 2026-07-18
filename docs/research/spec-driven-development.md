# Spec-driven development, requirements syntax, and decision records

**Last verified:** 2026-07-16
**Why we looked:** To design this repo's doc system on existing practice rather than
inventing one. Directly produced CLAUDE.md, the requirements format, and ADR-0001.

---

## Findings

### SDD converged on a common shape during 2025–26

Every major toolkit — [GitHub Spec Kit](https://github.com/github/spec-kit), AWS Kiro,
OpenSpec, BMAD, Tessl, Google Antigravity — independently arrived at roughly the same
structure:

1. A **constitution**: non-negotiable project principles the agent must not violate.
2. Per-increment **requirements → design → tasks**.
3. Specs **committed alongside code**, version-controlled, treated as source of truth.

The convergence is the signal. Independent teams reaching the same shape suggests it's
load-bearing rather than fashionable.

It emerged as a reaction to "vibe coding" — agents producing plausible code that drifts
from intent and decays at scale. The claimed mechanism is that when the spec is
authoritative, a wrong result means regenerate from a corrected spec rather than patch
the output.

**What we took:** the constitution idea, as CLAUDE.md's Non-negotiables. Specs in-repo
next to code.

**What we rejected:** Spec Kit's per-feature `/specify → /plan → /tasks → /implement`
command pipeline. It generates a spec directory per feature, which fragments
requirements across features and makes MECE impossible — the exact opposite of what we
want. We keep one living requirements doc. Toni also explicitly wants *fewer, larger*
increments, and the pipeline optimizes for many small ones.

### EARS makes requirements individually testable

[EARS](https://alistairmavin.com/ears/) (Mavin et al., IEEE RE'09) constrains
requirements to five patterns via keyword grammar:

| Pattern | Form |
|---|---|
| Ubiquitous | *The system shall …* |
| State-driven | *While `<state>`, the system shall …* |
| Event-driven | *When `<trigger>`, the system shall …* |
| Optional | *Where `<feature>`, the system shall …* |
| Unwanted | *If `<condition>`, then the system shall …* |

Ruleset: zero-or-many preconditions, zero-or-one trigger, one system name, one-or-many
responses.

AWS Kiro uses EARS for acceptance criteria and stores specs under `.kiro/specs`.
There's an [open request](https://github.com/github/spec-kit/issues/1356) to add it to
Spec Kit — it isn't there as of this check.

**Why it matters here:** EARS is what makes ID-based traceability work rather than
decorate. A requirement in EARS form maps to one test. Prose requirements map to
arguments about what the requirement meant. Adopted in REQUIREMENTS.md.

### MADR is the de facto ADR standard

[MADR](https://adr.github.io/madr/), ~2017, now the common answer. Convention:
`docs/decisions/nnnn-title.md`. Ships full/minimal × annotated/bare variants.

Core: context/problem, decision, consequences. Supplemental: decision drivers,
considered options, validation, links.

The consistent finding across sources: **considered-options-with-tradeoffs is the
section that earns the format**, and the one most often skipped. It's what prevents
rediscovery of a rejected path.

Alternative considered: Nygard's original (context/decision/consequences). Lighter, but
no dedicated options section — rejected for exactly the reason above. See ADR-0001.

**What we took:** MADR, trimmed. (Originally with append-only/supersession discipline;
changed 2026-07-18 — Toni: ADRs are living, kept up to date and MECE, deleted when
stale. See CLAUDE.md and ADR-0001.)
Rationale in ADR-0001.

### Requirement ID schemes

Not much rigorous published comparison; this is the practitioner consensus:

- **Hierarchical IDs (1.2.3) are actively harmful** when code references them. Inserting
  a requirement renumbers its siblings and silently invalidates every reference. This is
  well-attested and is why we use flat IDs.
- **IDs must be permanent.** Dropped requirements are never renumbered; the common
  practice is tombstoning, though this repo now deletes instead (next-free counters
  guard against reuse — changed 2026-07-18).
- **Domain prefixes** (`TASK-001`, `APPR-001`) make IDs self-describing but require a
  stable taxonomy up front and make re-homing awkward when a domain splits.

**What we took:** flat `FR-###` / `NFR-###`, permanent, deleted on removal with
next-free ID counters in REQUIREMENTS.md (tombstoning dropped 2026-07-18: "No
tombstones ever. All docs always up to date").

---

## Open / not investigated

- **Whether SDD's claimed benefits are real.** Everything above is vendor and
  practitioner claims. No independent evaluation found. The [arXiv process
  taxonomy](https://arxiv.org/pdf/2606.04967) is descriptive, not evaluative. We're
  adopting on plausibility, not evidence — worth remembering if the process starts
  costing more than it returns.
- **swift-testing tag ergonomics at scale.** ADR-0004 rejects per-requirement tags on
  reasoning, not measurement. If we ever want filtering, measure first.
- **Whether agents actually follow a constitution** under pressure, or rationalize past
  it. Directly relevant to whether CLAUDE.md's Non-negotiables work. No data.

## Sources

- [GitHub Spec Kit](https://github.com/github/spec-kit) · [spec-driven.md](https://github.com/github/spec-kit/blob/main/spec-driven.md) · [docs](https://github.github.com/spec-kit/)
- [EARS, Alistair Mavin](https://alistairmavin.com/ears/) · [IEEE RE'09 paper](https://ieeexplore.ieee.org/document/5328509/) · [Jama Software on adoption](https://www.jamasoftware.com/requirements-management-guide/writing-requirements/adopting-the-ears-notation-to-improve-requirements-engineering/)
- [MADR](https://adr.github.io/madr/) · [adr/madr repo](https://github.com/adr/madr) · [Zimmermann's MADR primer](https://ozimmer.ch/practices/2022/11/22/MADRTemplatePrimer.html) · [ADR templates](https://adr.github.io/adr-templates/)
- [Amazon Kiro intro](https://builder.aws.com/content/3CuKNklw8cDhXjreLYoznoj6dyx/amazon-kiro-use-cases-and-introduction)
- [Process taxonomy of AI dev agent frameworks (arXiv)](https://arxiv.org/pdf/2606.04967)
