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

## Increment 4 — The three-layer runtime and a durable task

Create the one deliberate SPM boundary from ADR-0002: a native Swift agent-runtime
package built on macOS 27 Foundation Models. Adapt the two shipped provider transports
to `LanguageModelExecutor`, drive `LanguageModelSession` from a durable coordinator,
and integrate it into the app against a provider configured in increment 2. The app
owns task persistence and presentation; the package owns provider-neutral execution.
No general work tools yet.

**Done when:** a real model call crosses all three layers, its result lands in a task
that survives an app restart, and the task's status is observable while it runs. The
package has no dependency on the app target or SwiftUI, its deterministic conformance
suite passes, and the task model's FR IDs are written at this increment's DOR from
whatever Toni actually specifies.

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
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
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
