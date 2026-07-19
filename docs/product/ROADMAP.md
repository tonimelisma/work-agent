# Work Agent — Roadmap

**Status:** Living. Last substantive change: 2026-07-18.

Order and deferrals only. What/why is in [PRODUCT.md](PRODUCT.md); testable statements
are in [REQUIREMENTS.md](REQUIREMENTS.md).

Increments are sized to the requirement, biased large — the DOR/DOD/spec overhead is
fixed, so amortize it. There are no dates. There is an order.

---

## Sequencing: engine first, then priorities from real use

The product is a chat — the user asks for whatever they need (PRODUCT.md §3; there is
no task catalog to design). So what gets prioritized *after* the engine — which
tools, which connectors, when permissions — is decided once we have **a working app
that talks to an LLM and a set of tools we've actually tested**, by using it. Not
before.

The reasoning: choosing priorities up front means choosing them from imagination.
Choosing them after the engine and tools exist means choosing from what real chats
demonstrably need — a fundamentally better-informed decision, and cheap, because by
then we'll know the real cost of each candidate.

The failure mode this carries is real and worth naming: an engine with nothing to be
right or wrong about grows forever. What keeps us out of that hole is that
increments 2, 4, 5, and 6 each have a concrete, falsifiable exit — a real model call,
a real tool doing a real thing, a second provider working cold. None of those are
opinions. Increment 7 is a hard stop where real use starts steering, or we admit the
engine isn't done.

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
FR-066, FR-068, FR-069, FR-070, NFR-007, NFR-008. New ADR-0007 (provider chat abstraction).

### Scope: all eleven providers, chat streaming

*"start with all of the ones I said."* The full curated set — eleven first-party
providers, sixteen models — appears in the menu. Chat streams through two adapters:
OpenAI-compatible (ten providers, including Google via its `/v1beta/openai` endpoint and
MiniMax via `/v1`) and Anthropic Messages (one). See ADR-0007 and
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

## Increment 3 — Runtime and neutrality research → ADR-0006 ✅

Research spike; done 2026-07-18. Live tool-calling POCs in
[research/agent-loop-runtimes.md](../research/agent-loop-runtimes.md);
[ADR-0006](../decisions/0006-native-swift-agent-loop.md) **accepted and revised after
the macOS 27 POC**: Apple Foundation Models supplies the intelligence session, a native
Swift SPM package supplies durable agent runtime semantics, and the Work Agent app
supplies product state, UI, credentials and Mac capabilities.

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

## Increment 4 — The three-layer runtime and a durable conversation ✅

Created the one deliberate SPM boundary from ADR-0002: **AgentKit**, a local Swift
package (RuntimeCore, Executors, ToolVocabulary, RuntimeTesting) supporting iOS 27 and
macOS 27 Foundation Models and any injected `LanguageModel`. The POC's proven cloud
executors migrated into `Executors`; `TaskCoordinator` drives `LanguageModelSession`
durably with an append-only journal, checkpoints, and automatic cross-provider failover
(FR-006); the macOS app integrates it with a SwiftData-backed (ADR-0008) conversation
sidebar (FR-071), pause-and-offer-resume on quit (FR-072), and restart durability
(FR-073). The `Experiments/FoundationModelsPOC/` spike is deleted — migrated, not
duplicated.

Toni's answers to the plan's §10 open questions, given at this increment's DOR:
multiple concurrent conversations with a sidebar (not one), pause-and-offer-resume
(not auto-resume) on quit, and automatic (not manual) failover — recorded as FR-071,
FR-072, and the FR-006 update in REQUIREMENTS.md.

The build plan is [docs/plans/agent-loop-implementation.md](../plans/agent-loop-implementation.md);
the API it must converge on is [docs/plans/runtime-api.md](../plans/runtime-api.md);
the product frame is [RUNTIME.md](RUNTIME.md).

**Done, with two named gaps.** A real model call crosses all three layers, lands in a
conversation that survives an app restart, and the conversation's status is observable
while a run is in flight. AgentKit has no dependency on the app target or SwiftUI; its
25-test conformance suite builds and passes on both macOS and iOS. Not done: **no gated
on-device `SystemLanguageModel` test was written** (no eligible-device cycle exists yet —
increment 3's scripted on-device pass is the closest evidence so far), and **the
interactive UI path (send, stream, quit mid-run, relaunch, resume) was not exercised in
the running app** — screen-control access to drive it was declined; the app was only
confirmed to launch and quit cleanly. Both are named in
[ENGINEERING.md](../engineering/ENGINEERING.md), not silently skipped.

## Increment 5 — First tools, tested

Tools the engine can actually call, exercised individually until we trust them. The
starter set is decided and specified in
[docs/plans/tool-architecture.md](../plans/tool-architecture.md) — see below. They
are built as the package's first ToolKit products, not app code
([runtime-api.md](../plans/runtime-api.md) §6); the app selects and exercises them.

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

## Increment 7 — Real use starts steering

Not a build increment, and **not a task catalog** — Toni, 2026-07-18: "real tasks as
in evals… no, we don't need that. … the user chats." The product is a chat; there is
nothing to pre-select. This increment is Toni doing his actual work through the app,
and the observed gaps — a missing tool, a needed connector, permission friction, a
context limit — choosing the next increments from the horizon table below.

**Done when:** the increment after 6 is chosen from observed real use and its DOR is
posted.

---

## The horizon after increment 7

The 2026-07-18 north star ([RUNTIME.md](RUNTIME.md),
[plans/runtime-api.md](../plans/runtime-api.md)) runs past increment 7 to a published
runtime SPM and two reference apps. These are **direction with dependencies, not
numbered increments** — each gets its number, plan, and DOR when Toni schedules it,
and the dependency arrows are the only ordering claimed:

| Future increment | Depends on | What it delivers |
|---|---|---|
| **Permissions and approvals** | Real use showing what needs gating (increment 7) | The deferred approval model, designed against observed friction rather than imagined risk |
| **MCP** | Tool host proven (increment 5) | MCP client + the schema degradation ladder (runtime-api.md §4) |
| **Runtime API hardening** | Increments 4–6 stable | Public-API review against runtime-api.md, DocC, `Examples/`, conformance suite made public |
| **App moves to its own repo** | Toni's call — "soon" (2026-07-19) | This repo becomes the SPM; the macOS app references it as a dependency from its own repo |
| **Publication** | API hardening **and OS 27 GA** (release gate, RUNTIME.md §7) | Package.swift at repo root, the name decision (license is decided: MIT; the README already follows [plans/package-readme.md](../plans/package-readme.md)), first public tag |
| **iOS tool modules + iOS reference app** | Runtime published or near it; macOS app proving it | The sibling product: scoped-access tools, suspension-safe durable runs (see deferred table) |
| **The studio** | Unscheduled candidate (RUNTIME.md §6) | Local-first trace/replay/eval app, generalized from Work Agent's trace UI |

An agent asked to "implement the next increment" works the numbered list first
(4 → 5 → 6 → 7); when that's exhausted, the next increment is proposed from this
table's dependency order and confirmed at its DOR — not assumed.

---

## Deferred, with the reason

| Deferred | Until |
|---|---|
| **Post-engine priorities** (next tools, connectors, permissions timing) | Increment 7 — chosen from observed real use, not imagination. |
| **Which tools to build first** | Decided — see below and [docs/plans/tool-architecture.md](../plans/tool-architecture.md). |
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
| **Connections** (Gmail, Drive, M365) | A real task needs one. |
| **Native app control** (Accessibility, screen capture) | Structured APIs demonstrably fall short. ADR-0003 keeps this possible. |
| **Sandboxed code execution** | Something needs to run generated code — shell/exec stays out of the tool set until an isolation ADR exists. |
| **Automations, scheduling** | Post-engine. |
| **Onboarding, multi-user, enterprise policy** | Distribution reaches people who aren't Toni. |
| **iOS reference app + iOS tool modules** | The runtime exists and the macOS app proves it. Decided direction, not scheduled — see [RUNTIME.md](RUNTIME.md) §5. Checkpoints are designed suspension-safe from the start so this doesn't force a rework. |

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
