# Research

What we learned from outside this repo, so we never learn it twice.

## When to write one

**Any external lookup or POC that took real work.** API availability, performance
measurements, whether a framework can actually do the thing, what a vendor's docs
actually say versus claim.

The test: *would we have to redo the work to know this again?* If yes, write it down.
Trivial lookups stay in the transcript.

Nobody has to ask for this. It's part of the DOD.

## How these work

**Topic-named, not numbered, not dated.** `provider-neutrality.md`, not
`0003-provider-neutrality.md`. The filename is the topic because these are living docs.

**Update in place.** This is not a journal. New findings on an existing topic edit the
existing doc — including deleting what turned out to be wrong. An outdated research doc
is worse than none, because it gets trusted.

**MECE.** One topic, one doc. If a finding fits two docs, it belongs in one and is
linked from the other.

**Say when you looked.** Findings about live APIs, pricing, and model capabilities rot
fast. Every doc carries a last-verified date, and every claim that depends on the
outside world says when it was checked.

**Record what was measured, not just what was concluded.** A conclusion without its
evidence has to be redone the moment anyone doubts it — which defeats the point.

## Contents

| Doc | Topic | Last verified |
|---|---|---|
| [spec-driven-development.md](spec-driven-development.md) | SDD practice, EARS, ADR formats — the basis for this repo's doc system | 2026-07-16 |
| [llm-provider-registries.md](llm-provider-registries.md) | models.dev and alternatives; live API measurements and gaps | 2026-07-16 |
| [provider-subscription-auth.md](provider-subscription-auth.md) | Whether a third-party app may use someone's ChatGPT/Claude subscription (no) | 2026-07-16 |
| [agent-harness-builtin-tools.md](agent-harness-builtin-tools.md) | Built-in tools in Claude Code/Cowork: full inventory, limits, and how tool output is kept from flooding the context window | 2026-07-17 |
