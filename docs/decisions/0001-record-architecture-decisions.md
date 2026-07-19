# ADR-0001 — Record architecture decisions, in this format

- **Status:** Accepted
- **Date:** 2026-07-16; lifecycle changed to living docs 2026-07-18
- **Deciders:** Toni

## Context

Decisions on this project get made in conversation, mostly with agents, and then
evaporate. Six weeks later nobody — human or agent — remembers whether a choice was
reasoned or accidental. The reliable symptom is an agent "fixing" a deliberate decision
because the reasoning wasn't written down, or relitigating a settled question because
the alternatives weren't recorded.

The previous roadmap draft demonstrated the failure precisely: it asserted
architecture as though it were fact rather than choice, with no alternatives and no
reasoning. Unreviewable, because there was nothing to disagree with.

We also need a home for decisions that is *not* the engineering doc. They answer
different questions: ENGINEERING.md says what is true now, an ADR says why we chose
it and what we rejected. Merging them buries the reasoning inside the synthesis.

## Decision

Record architecturally significant decisions as numbered Markdown files in
`docs/decisions/`, named `NNNN-kebab-title.md`, using the format of this file — a
lightly trimmed [MADR](https://adr.github.io/madr/).

**Significant** means: expensive to reverse, constrains later decisions, or a reader
would reasonably ask "why on earth is it like this?" Library picks and naming
conventions are not ADRs. If it's arguable and durable, it's an ADR.

**Living, MECE, deleted when stale** *(Toni, 2026-07-18: "ADRs are not append only.
They are to be kept up to date and MECE… deleted when stale.")* An ADR always states
the *current* decision and its reasoning. When the decision changes, the ADR is
updated in place — reasoning, alternatives, consequences, all of it. When the
decision stops mattering, the file is deleted. Git history is the archive of what we
used to believe; the working tree carries no dead decisions. Numbers are never
reused, so references in history stay unambiguous. (This paragraph originally said
the opposite — append-only with supersession chains — and was rewritten under its
own new rule.)

**Considered options carry their tradeoffs.** An ADR listing alternatives without saying
what was bad about the winner and good about the losers hasn't recorded a decision, it
has recorded a preference. The rejected options are why the file exists.

The sections: Context, Decision, Considered options (with tradeoffs), Consequences
(including bad ones), and — where it exists — Validation.

## Considered options

**MADR, trimmed** *(chosen)* — Widely used, Markdown, keeps tradeoff analysis as a
first-class section. Costs some ceremony per decision, and the full template has
sections we'd leave empty.

**Nygard's original ADR format** — Lighter: context, decision, consequences. Genuinely
less friction. Rejected because it has no dedicated place for considered options, which
is the section that stops a future agent from redoing the analysis. That's the section
we most need.

**Decisions inside ENGINEERING.md** — One less file to find. Rejected: they answer
different questions (what is vs. why), and merging them buries alternatives-and-
tradeoffs inside a doc that gets rewritten for unrelated reasons. MECE dies first.

**No ADRs; rely on git history and PRs** — Zero overhead. Rejected: commit messages
record *what* changed, and PR threads are unsearchable, unindexed, and lost if the repo
moves. Neither survives an agent's context window, which is the actual reader here.

## Consequences

**Good.** Decisions become reviewable and refusable. Agents can read why and stop
reflexively fixing intent. Every ADR on disk is current, so nothing needs to be
cross-checked against a supersession chain before trusting it.

**Traded away.** The old append-only rule kept wrong turns visible in the working
tree; now recovering superseded reasoning means reading git history. Accepted cost —
a doc that must be checked for staleness before use is worse than a history lookup.

**Bad.** Overhead per decision, and it lands hardest exactly when momentum is highest.
The predictable failure is ADRs written after the fact to satisfy the DOD — fiction with
a number on it. The DOR asks which ADRs an increment will need *before* work starts,
specifically to catch this.

**Also bad.** "Architecturally significant" is a judgment call and will be applied
inconsistently. Better than the alternatives, which are ADRs for everything (noise) or
for nothing (amnesia).
