# Work Agent — Product

**Status:** Living. Last substantive change: 2026-07-18.

This doc holds the bet: what we're building, for whom, why it can exist, and what it
is not. Testable statements live in [REQUIREMENTS.md](REQUIREMENTS.md). Sequencing
lives in [ROADMAP.md](ROADMAP.md).

---

## 1. The thesis

Every serious agent product today is welded to the model company that ships it. Claude
Cowork is Anthropic's. ChatGPT Work is OpenAI's. Both will be good. Both are structurally
incapable of being neutral, because neutrality would undermine the thing they're selling.

We're betting that:

- **Inference commoditizes.** The gap between frontier and good-enough narrows, open
  models get genuinely usable for real work, and price per token keeps collapsing.
- **The app layer is where the durable value ends up** — the interaction model, the
  trust model, the memory, the integrations, the judgment about what to show a user
  and when to ask.
- **Users already pay for a model subscription** and don't want to pay again per app.
  A ChatGPT or Claude subscription they already pay for should just work.
  **Partly blocked — see below.**

If that's right, an app that innovates independently of any model vendor wins ground
that the vendors' own apps cannot contest. If it's wrong — if one model runs away with
it and vertical integration wins — this product is worse than a wrapper.

That's the bet. It's stated plainly so we can notice if it stops being true.

### The subscription plank is blocked (2026-07-16)

Researched because Toni asked for ChatGPT subscription auth. Full evidence:
[research/provider-subscription-auth.md](../research/provider-subscription-auth.md).

**Anthropic bans it outright** — OAuth is "intended exclusively for Claude Code and
Claude.ai," enforced since early 2026 with account suspensions. **Google closed the same
path.** **OpenAI is genuinely unclear**: it documents sign-in for its own clients only,
but prohibits nothing. The claim that OpenAI "explicitly supports" third-party
subscription OAuth comes from OpenClaw's own docs and cites no OpenAI source.

So the plank half-survives: the Claude half is dead, the ChatGPT half rests on one
vendor's silence (FR-067).

**The wedge survives in its stronger form.** Planks 1 and 2 are untouched, and the
structural advantage was never really the subscription: **no vendor's own app will ever
let you swap to a competitor's model.** Cowork will never offer GPT. ChatGPT Work will
never offer Claude. We can offer both. That is permanent, and no amount of vertical
integration fixes it for them.

**The honest cost:** BYO-API-key is a worse start than BYO-subscription for exactly the
non-technical audience in §2. "Paste an API key" is a real wall for someone who doesn't
know what one is. That is a genuine product problem to solve as a product problem — not
by impersonating someone's CLI.

**Open decision.** This contradicts what Toni asked for, so it is flagged, not settled.

**The consequence for engineering:** model neutrality is not a feature to add later. Any
decision that couples us to a single provider is wrong by default and needs an ADR to
become right.

---

## 2. Who this is for

**Not developers. Not power users.** People who have work to do and no interest in how
it gets done.

Distribution follows a deliberate path, and scope grows with it:

| Stage | User | What that means for scope |
|---|---|---|
| Now | Toni | No onboarding polish, no multi-account, no enterprise policy. Paste a key, pick a model, go. |
| Later | Friends | Onboarding must work without the author present. Failure states must explain themselves. |
| Eventually | Public | Trust model, permission explanation, recovery, and support all become load-bearing. |

We build for stage 1 and avoid decisions that make stages 2 and 3 impossible. We do
**not** build stage 3's features now. When something claims to be needed "for later,"
that's a roadmap item, not this increment.

The user should never need to know what MCP, AppleScript, Accessibility, XPC, OAuth
scopes, tool schemas, or a sandbox runtime are. If those words appear in the normal UI,
we've failed.

---

## 3. What it is

A native macOS 27-or-later application that:

- runs agent orchestration **locally**, on the user's Mac;
- talks to **whatever model the user chose**, via an API key they own — from a curated
  set of the best agentic models across vendors. Cloud only, and no local models ever;
- does real work against local files, native Mac applications, and connected services;
- keeps configuration, traces, and history on the Mac;
- makes what it did legible after the fact.

## 4. What it is not

- A wrapper around one vendor's model.
- A developer console, or a GUI for editing MCP JSON.
- A terminal coding agent.
- A remote desktop.

## 5. Product principles

Only what Toni has actually said. The inherited draft's principles — "task not chat,"
"show outcomes not tool calls," effect-based approvals, partial completion — were
removed: two were never his, and one was the reverse of what he wants.

1. **Model neutrality is structural.** Not a setting bolted on at the end.
2. **Never neuter a model.** Every capability a model has, including provider-exclusive
   ones, is exposed. We don't cut features down to a common denominator.
3. **Show the machinery, made friendly.** Reasoning and tool calls are visible, in
   human terms — not hidden behind outcomes, and not dumped as raw protocol.
4. **Keep everything, show what's useful.** Full traces are always persisted; what's
   displayed is a view, never the limit of what was recorded.
5. **Curate ruthlessly.** A short list of genuinely good agentic models beats a menu of
   five thousand. The user is not a model researcher.
6. **Calm and native.** No anthropomorphic assistant. macOS patterns, restrained color,
   simple lists over clever surfaces.

---

## 6. Current non-goals

Explicit, so they don't get smuggled in:

- Multi-user, teams, or enterprise policy.
- A plugin marketplace.
- Exposing local capabilities to external agents (the draft's "cloud gateway").
- Mac App Store distribution — see ADR-0003.
- **Locally-hosted models. Ever.** "no local models ever."
- **Resellers and aggregators** — first-party providers only, for now.
- Mobile or web companion.

---

## 7. Open questions

These are unresolved and blocking nothing yet. They get answered before the increment
that depends on them.

- **Background execution.** Does work survive the window closing in v1? Deciding "yes"
  later costs a painful retrofit; deciding "yes" now costs XPC and a LaunchAgent before
  the product is validated.
- **The first real task.** Deferred to increment 7, deliberately. It gets picked once we
  have a working app that talks to an LLM and a set of tools we've actually tested — so
  the choice is made against what the thing demonstrably does, not against imagination.
  The risk this carries, and what bounds it, is in ROADMAP.md.
- **OpenAI subscription sign-in (FR-067).** Toni asked for it. Anthropic's equivalent is
  explicitly banned; OpenAI's is undocumented — neither permitted nor prohibited. The
  "OpenAI explicitly supports this" claim comes from OpenClaw's docs and cites nothing.
  Risk is unquantified. His call. See §1.
- **How a non-technical user gets an API key.** The subscription plank was going to
  solve onboarding. It's gone, and nothing replaces it yet. This is the sharpest open
  product problem.
