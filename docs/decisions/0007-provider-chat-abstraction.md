# ADR-0007 — Provider chat abstraction: two native adapters

- **Status:** Accepted
- **Date:** 2026-07-17
- **Deciders:** Toni

## Context

Increment 2 makes the chat actually talk to all eleven curated providers, streaming
replies. That needs a concrete answer to: how does one Swift app speak to eleven
providers without eleven bespoke clients, and without coupling to any one of them
(FR-001)?

This is narrower than the agent-runtime question (ADR-0006, planned), which is about the
tool-calling loop. This ADR is only about **streaming a chat reply**. Getting it right
here sets the seam the runtime later builds on.

Evidence: every curated endpoint was probed live on 2026-07-16/17 — see
[research/provider-chat-endpoints.md](../research/provider-chat-endpoints.md).

## Decision

Define a `ChatProvider` protocol — `stream(messages:model:apiKey:) -> AsyncThrowingStream<ChatChunk, Error>`
— and implement it with **two adapters**:

- **`OpenAICompatibleChatProvider`** — POST `{base}/chat/completions`, SSE, bearer auth.
  Serves ten of the eleven curated providers.
- **`AnthropicChatProvider`** — POST `{base}/v1/messages`, SSE event stream, `x-api-key`.
  Serves Anthropic.

A small factory routes by provider id: `anthropic` → Anthropic adapter, everything else →
OpenAI-compatible. Two providers get a **chat base-URL override** in `ProviderCatalog`
because their registry `api` isn't the OpenAI-compatible surface:

- **google** → `…/v1beta/openai` (Gemini's OpenAI-compatible endpoint), so it uses the
  OpenAI adapter with bearer auth rather than needing a third code path.
- **minimax** → `…/v1` (its registry `api` is the Anthropic-shaped `/anthropic/v1`).

Chunks are `.text` or `.reasoning`; the reasoning field name varies (`reasoning_content`
vs `reasoning` vs Anthropic `thinking_delta`) and each adapter normalizes it.

## Considered options

**Two native adapters** *(chosen)* — Minimal code for maximum coverage: one adapter
already covers ten providers because the OpenAI wire format is a de facto standard.
Native means we can later expose provider-specific features (FR-060) without fighting an
abstraction. Costs: we own SSE parsing and each provider's small deviations (base paths,
reasoning field names, MiniMax's dual endpoints), and a genuinely different provider (a
third wire format) needs a third adapter.

**One universal adapter via an OpenAI-compatible proxy** (e.g. route everything through a
local LiteLLM) — One code path, broadest coverage. Rejected: it puts a process we bundle
and manage between us and every call, it flattens provider-specific features (against
FR-060), and it's a heavy dependency for a plain chat. Reconsider only if adapter count
grows painfully — an ADR-0006 concern, not this one.

**Eleven bespoke clients** — Maximum fidelity per provider. Rejected as obviously wasteful
when ten share a format. This is what the abstraction exists to avoid.

**Use each provider's OpenAI-compatible endpoint uniformly, including Anthropic's** —
Anthropic does publish an OpenAI-compatible surface. Tempting for one code path. Rejected:
it's a compatibility shim that lags Anthropic's native features (the ones FR-060 wants),
and Anthropic is our single most important provider (it's a direct competitor's model).
Native Messages is the right call for the one provider where it matters most.

## Consequences

**Good.** Ten providers work through one tested adapter. The seam is real and small;
`rg FR-001` lands here. Streaming, reasoning, and friendly errors are uniform across
providers. Adding an OpenAI-compatible provider is a curated-catalog entry and nothing
else (NFR-001 holds for the common case).

**Bad.** We own the wire details and they drift: a provider can change its base path,
rename a reasoning field, or (like MiniMax) expose two incompatible endpoints under one
id. Each is a small maintenance surface, and staleness is silent until a provider breaks.
`reasoning_content` vs `reasoning` is exactly this kind of papercut.

**Known gap.** Zhipu/GLM rejects a raw bearer token at both its endpoints and appears to
require a JWT signed from its `id.secret` key — a third auth style this ADR does not
implement. GLM is in the menu but unusable until that's built. Named, not hidden.

**Deferred to ADR-0006.** Tool calling, the agent loop, retries/orchestration, and
whether a heavier runtime replaces these thin adapters. This ADR deliberately does the
smallest correct thing.

## Validation

Both adapters have unit tests parsing captured SSE fixtures (`.text`, `.reasoning`,
error mapping). Five providers — DeepSeek, Anthropic, Google, Moonshot, Alibaba — were
verified **live**, streaming real replies through the actual adapter code (the
`LiveSmoke` suite, gated on keys). OpenAI and MiniMax returned billing errors (valid key,
no funds), which confirms the request shape reaches the account.
