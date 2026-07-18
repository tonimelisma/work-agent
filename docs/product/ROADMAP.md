# Work Agent — Roadmap

**Status:** Living. Last substantive change: 2026-07-16.

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

## Increment 2 — Settings + a working chat ✅

First code increment. Worktree, PR. **Done.**

An idiomatic macOS Settings scene — a plain list of providers you add/remove by API key —
plus the main window as a **chat that actually talks to the models**, streaming replies.
Resequenced from the original plan (which had inference land in increment 4) because Toni
asked to "start by building the fucking app," then to make the chat real across all
providers. Plain streaming chat is far smaller than the agent runtime, so bringing it
forward is cheap; the runtime ADR still governs tools/loop later (now increment 3).

FR-050, FR-051, FR-052, FR-054, FR-055, FR-056, FR-057, FR-061, FR-062, FR-063, FR-065,
FR-066, FR-068, FR-069, FR-070, NFR-007, NFR-008. New ADR-0006 (provider chat abstraction).

### Scope: all eleven providers, chat streaming

*"start with all of the ones I said."* The full curated set — eleven first-party
providers, sixteen models — appears in the menu. Chat streams through two adapters:
OpenAI-compatible (ten providers, including Google via its `/v1beta/openai` endpoint and
MiniMax via `/v1`) and Anthropic Messages (one). See ADR-0006 and
[research/provider-chat-endpoints.md](../research/provider-chat-endpoints.md).

**Live-verified (streaming, real replies):** DeepSeek, Anthropic, Google, Moonshot,
Alibaba. **Key valid but account unfunded** (endpoint confirmed, not smoke-tested):
OpenAI (429), MiniMax (402). **Needs custom auth:** Zhipu/GLM rejects a raw bearer token
and appears to require JWT signing — flagged, not fixed. No keys held: xAI, Meta, Thinking
Machines — in the menu, unverifiable until keyed.

**Also this increment:** App Sandbox disabled (`ENABLE_APP_SANDBOX = NO`), which the Xcode
template had silently enabled and which blocked all outbound network. This realizes
ADR-0003 (Developer ID, not MAS, *because* the sandbox forbids what the product needs).
Hardened Runtime stays on for notarization.

## Increment 3 — Runtime and neutrality research → ADR-0007

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
OpenAI-compatible vs proxy. FR-001 through FR-007 and NFR-001 are the constraints the
answer has to satisfy.

Real POCs against real cloud providers. Findings go to `docs/research/`; the decision
goes to ADR-0007.

**Done when:** ADR-0007 is written with alternatives and evidence, and a research doc
records what we measured so nobody redoes it.

## Increment 4 — A working app that talks to an LLM

The agent loop from ADR-0007, in the monolith, against a provider configured in
increment 2. A durable task the user can create and watch. No tools yet.

**Done when:** a real model call happens, its result lands in a task that survives an
app restart (FR-010, FR-011), and the task's status is observable while it runs
(FR-012).

## Increment 5 — First tools, tested

Tools the engine can actually call, exercised individually until we trust them. Scope
of the starter set is an open question below.

This increment is where approval lands too — the first tool with a consequential effect
forces FR-020 through FR-025 to become real rather than specified.

**Done when:** each tool has tests proving it does what it claims, and a tool with a
consequential effect cannot run without approval.

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
| **Which tools to build first** | Increment 5's scope. Open — see below. |
| **Minimum macOS version** | The first increment that wants an API we'd have to gate. Currently nothing does. |
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
| **SPM package extraction** | We know where the seams are. (ADR-0002) |
| **Connections** (Gmail, Drive, M365) | A real task needs one. |
| **Native app control** (Accessibility, screen capture) | Structured APIs demonstrably fall short. ADR-0003 keeps this possible. |
| **Sandboxed code execution** | Something needs to run generated code. NFR-004 holds the line meanwhile. |
| **Automations, scheduling** | Post-engine. |
| **Onboarding, multi-user, enterprise policy** | Distribution reaches people who aren't Toni. |

---

## Open: the increment-5 starter tool set

Needs answering before increment 5.

The tools we pick determine which tasks are available to choose from in increment 7, so
this is a smaller version of the same decision — it constrains the product while
looking like an engineering choice. Worth deciding deliberately.

The obvious candidates, roughly in order of cost:

- **Local files** — read, search, write within user-approved folders. Cheapest, no
  OAuth, no network, and exercises approval (writing) and sources (reading). Almost
  certainly in the set.
- **Shell / subprocess** — powerful and general, but NFR-004 forbids arbitrary host
  execution, so this needs an isolation story first. Probably not in the starter set.
- **A connected service** (Gmail, Drive) — the most representative of real work, and by
  far the most expensive: OAuth, token refresh, revocation, API surface. Likely too
  much for increment 5.
- **Native app control** — deferred; ADR-0003 keeps it possible.

Not decided. Local files is the likely floor; the question is whether anything joins it.
