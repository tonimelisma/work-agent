# Work Agent — Roadmap

**Status:** Living. Last substantive change: 2026-07-18.

Order and deferrals only. What/why is in [PRODUCT.md](PRODUCT.md); testable statements
are in [REQUIREMENTS.md](REQUIREMENTS.md).

Increments are sized to the requirement, biased large — the DOR/DOD/spec overhead is
fixed, so amortize it. There are no dates. There is an order.

---

## Sequencing: engine first, then tasks

Tasks get picked once we have **a working app that talks to an LLM and a set of tools
we've actually tested.** Not before.

The reasoning: choosing tasks up front means choosing them from imagination. Choosing
them after the engine and tools exist means choosing from what the thing demonstrably
does — which is a fundamentally better-informed decision, and cheap, because by then
we'll know the real cost of each candidate.

The failure mode this carries is real and worth naming: an engine with nothing to be
right or wrong about grows forever. The previous draft of this project reached ten
phases and seven Swift packages without one working feature. What keeps us out of that
hole is that increments 2, 4, 5, and 6 each have a concrete, falsifiable exit — a real model call,
a real tool doing a real thing, a second provider working cold. None of those are
opinions. Increment 7 is a hard stop where we pick tasks or admit the engine isn't
done.

---

## Increment 1 — Documentation foundation ✅

Doc-only, straight to main.

This repo's specs, process, ADR format, and research system. Replaces the prior
`MACOS_FRONTEND_ROADMAP.md` draft, which was written without product input and is not
trusted.

## Increment 2 — Settings: add your LLM providers

First code increment. Worktree, PR. **Not started — awaiting DOR go-ahead.**

An idiomatic macOS Settings scene: a simple list of configured providers. Add one, paste
an API key, have it verified, pick which is active. Nothing else.

FR-050, FR-051, FR-052, FR-054, FR-055, FR-056, FR-057, FR-061, FR-062, NFR-007, NFR-008.

### Scope: all eleven providers

*"start with all of the ones I said."* The full curated set in REQUIREMENTS.md ships in
this increment — eleven first-party providers, sixteen models.

A two-provider start was proposed and rejected. Recording why it's not a problem: of the
eleven, only `anthropic` and `google` need bespoke request shapes. The other nine are
OpenAI-compatible — `thinkingmachines`, for instance, is literally `TINKER_API_KEY`
against an OpenAI-compatible endpoint. So eleven providers is roughly three auth styles
and three request shapes, not eleven of anything.

The risk that remains is real but bounded: **verifying eleven providers live needs
eleven accounts with credit.** Any we can't test is a provider we're shipping on faith.
That is a testing problem to name, not a reason to cut the list.

**Done when:** a real key is stored and verified live for every provider we have an
account for, and survives relaunch; the app is fully usable with the network down; no
credential appears in preferences or logs; the menu shows only the curated sixteen; and
any provider that could not be verified against a live account is named in the DOD
rather than quietly assumed to work.

## Increment 3 — Runtime and neutrality research → ADR-0006

Research spike. Produces docs and one ADR; no product code.

The question: **what runs the agent loop, given that model neutrality is
non-negotiable?** Neutrality eliminates the Claude Agent SDK and Claude Code outright —
both are single-vendor by construction. The live options:

- Custom Swift loop over provider-neutral HTTP.
- An embedded neutral framework (Pydantic AI, LangGraph, Mastra, Vercel AI SDK) as a
  bundled subprocess.
- A normalization layer (LiteLLM, or targeting the OpenAI-compatible endpoint most
  providers expose).

Sub-question, same spike: what "neutral" means mechanically — adapter per provider vs
OpenAI-compatible vs proxy. FR-001, FR-005, FR-006, and NFR-001 are the constraints the
answer has to satisfy.

Real POCs against real cloud providers. Findings go to `docs/research/`; the decision
goes to ADR-0006.

**Done when:** ADR-0006 is written with alternatives and evidence, and a research doc
records what we measured so nobody redoes it.

## Increment 4 — A working app that talks to an LLM

The agent loop from ADR-0006, in the monolith, against a provider configured in
increment 2. A durable task the user can create and watch. No tools yet.

**Done when:** a real model call happens, its result lands in a task that survives an
app restart, and the task's status is observable while it runs. The task model has no
requirements yet — its FR IDs get written at this increment's DOR, from whatever Toni
actually specifies.

## Increment 5 — First tools, tested

Tools the engine can actually call, exercised individually until we trust them. The
starter set is decided and specified in
[docs/plans/tool-architecture.md](../plans/tool-architecture.md) — see below.

Approvals deliberately do *not* land here: "specific tool approvals will come later,"
reaffirmed on the tool plan's open questions — "We don't have folders. Permissions
come later." Tools run ungated; the full trace is the accountability mechanism until
the permissions increment exists.

**Done when:** each tool has tests proving it does what it claims, and each has been
exercised live in the app.

## Increment 6 — Second provider, cold: the real neutrality test

Add a provider we did not design against, and make the increment-5 tools work through
it unchanged.

**This is positioned after tools deliberately.** Tool calling is where provider
neutrality actually bites — Anthropic emits `tool_use` blocks, OpenAI emits
`tool_calls`, Ollama varies by model, and some open models approximate it with JSON
mode. Testing neutrality over plain-text conversation would prove almost nothing and
would let us believe FR-001 was satisfied months before it was.

**Done when:** the provider is added without changes outside its adapter and its
registration, and every increment-5 tool works through it — or NFR-001 gets rewritten
to say what's actually true. Both outcomes are acceptable. Quietly keeping a false
NFR-001 is not.

## Increment 7 — Pick the tasks

Not a build increment. A product decision, made with the engine and tools in front of
us, drawn from work Toni actually does — not from a category list.

**Done when:** the real first task is named in PRODUCT.md and its requirements are
written.

---

## Deferred, with the reason

| Deferred | Until |
|---|---|
| **The real first task** | Increment 7 — once a working app talks to an LLM and has tools we've tested. Picked from actual work Toni does. |
| **Which tools to build first** | Decided — see below and [docs/plans/tool-architecture.md](../plans/tool-architecture.md). |
| **Minimum macOS version** | The first increment that wants an API we'd have to gate. Currently nothing does. |
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
| **SPM package extraction** | We know where the seams are. (ADR-0002) |
| **Connections** (Gmail, Drive, M365) | A real task needs one. |
| **Native app control** (Accessibility, screen capture) | Structured APIs demonstrably fall short. ADR-0003 keeps this possible. |
| **Sandboxed code execution** | Something needs to run generated code — shell/exec stays out of the tool set until an isolation ADR exists. |
| **Automations, scheduling** | Post-engine. |
| **Onboarding, multi-user, enterprise policy** | Distribution reaches people who aren't Toni. |

---

## Decided: the increment-5 starter tool set

Answered 2026-07-17/18; the full design, with per-tool implementation detail and
Toni's decisions quoted, is [docs/plans/tool-architecture.md](../plans/tool-architecture.md).
The short version:

- **Local files** — six typed tools (read, list, find, search, write, edit), plain
  paths, no folder-grant model ("We don't have folders. Permissions come later"),
  docx text extraction included. Native Swift throughout, no bundled binaries.
- **Web** — `fetch_url` (paged markdown) plus web search both ways: provider-hosted
  where a vendor offers it, Brave-backed neutral tool otherwise.
- **Interaction** — `ask_user` and `update_plan`, which can land with increment 4.
- **Shell / subprocess** — excluded until an isolation ADR exists.
- **Connected services, native app control** — still deferred as above; MCP arrives
  later as a registry input, per the plan.
