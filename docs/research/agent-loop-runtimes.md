# What should run the agent loop

**Last verified: 2026-07-18.** The increment-3 spike behind ADR-0006. Evidence here is
live: tool-calling probed over the wire against five curated providers with the
`.env` keys, plus assessment of the framework alternatives. Toni's constraint going
in: *"I'd prefer a clean native Swift module but need your research and input."*

The question, from ROADMAP increment 3: what runs the agent loop, given model
neutrality (FR-001, NFR-001), full capability exposure (FR-060), and mid-task
provider failover (FR-006)? Increment 2 changed the starting position: the app now
ships two working native streaming adapters (ADR-0007) covering all eleven curated
providers — any option that discards them starts from behind.

For the deeper developer-facing comparison of current framework features, production
runtime practices, and what could justify a native Swift AgentKit beyond the loop,
see [agent-framework-comparison.md](agent-framework-comparison.md).
The macOS 27 Foundation Models APIs materially change the native option; the proposed
hybrid and the POC evidence that revised ADR-0006 are in
[foundation-models-adaptation.md](foundation-models-adaptation.md).

---

## Live POC: tool calling over our two wire formats

Probed 2026-07-18 with `curl` against real endpoints, same shapes ADR-0007's adapters
already parse. One `read_file` tool, a prompt that forces its use, then a full
round-trip (tool result fed back → final answer).

| Provider (model) | Emits tool call | Streaming delta shape | Round-trip |
|---|---|---|---|
| DeepSeek (`deepseek-v4-pro`) | ✅ OpenAI `tool_calls` | ✅ `delta.tool_calls[].function.arguments` fragments, index-keyed | ✅ **but see quirk 1** |
| Moonshot (`kimi-k3`) | ✅ OpenAI `tool_calls` | not probed | not probed |
| Alibaba (`qwen3.7-max`) | ✅ OpenAI `tool_calls` | not probed | not probed |
| Google (`gemini-3.5-flash`, `/v1beta/openai`) | ✅ OpenAI `tool_calls` **+ quirk 2** | not probed | not probed |
| Anthropic (`claude-sonnet-5`) | ✅ `tool_use` block | ✅ `content_block_start` + `input_json_delta` partial-JSON fragments | ✅ |

**The headline: it works.** The OpenAI-compatible surface our ten providers share
carries tool calling uniformly, streaming included, and Anthropic's native format is
a second, well-documented shape. The loop needs exactly the two adapters we already
have, extended with tool serialization and delta accumulation.

**The quirks are the real findings** — each is provider-specific state the loop must
carry and echo back, and each is invisible until the *second* request of a loop:

1. **DeepSeek requires reasoning round-tripping.** Continuing after a tool call
   without the assistant's `reasoning_content` fails hard:
   `"The reasoning_content in the thinking mode must be passed back to the API."`
   Echoing it back fixed it (verified live). Reasoning isn't display-only for us —
   it's conversation state.
2. **Google attaches `extra_content.google.thought_signature`** (an opaque blob) to
   tool calls on the OpenAI-compatible endpoint. Gemini's docs say thought
   signatures must be returned with the following request for the model to keep its
   reasoning thread. Same class of state as quirk 1.
3. **Anthropic emits `thinking` blocks with `signature_delta`** — with extended
   thinking on, tool-use turns must be replayed with their signed thinking blocks
   intact.

Three providers, three different names for the same requirement: **the neutral
conversation model needs a per-message, per-provider opaque "extras" bag that is
persisted and replayed verbatim.** This single fact dominates the framework
comparison below, because generic frameworks handle it unevenly to not at all — and
it is precisely what FR-006 (resume a task on another provider) has to get right:
strip one provider's extras, keep the neutral content, continue elsewhere.

## What a loop actually is

Small. The cycle — send conversation + tool specs, accumulate streamed deltas,
detect stop-on-tool-use, execute tools, append results, repeat until a text-only
finish — is the part every harness shares and none is differentiated by
([codex-harness-tools.md](codex-harness-tools.md): the loop core is dwarfed by its
tools; [agent-harness-builtin-tools.md](agent-harness-builtin-tools.md): same).
Concretely, on top of what increment 2 already shipped, a native loop needs:

- Tool-spec serialization per adapter (both formats verified above) and delta
  accumulation into complete tool calls (index-keyed for OpenAI-compat, block-keyed
  for Anthropic) — the shapes are captured in this doc's probes.
- The extras bag (quirks 1–3) on the neutral message type.
- A turn state machine: streaming → executing tools (parallel calls allowed) →
  next request; cancellation via structured concurrency; retry/backoff on 429/5xx.
- A max-turns guard and the token budgeting already designed in
  [../plans/tool-architecture.md](../plans/tool-architecture.md) (`ToolRunner`).

Order-of-magnitude: a few hundred lines of loop plus comparable adapter extensions —
in the same codebase style as the ~1,500 lines increment 2 produced. A solo
open-source developer maintains a complete Swift equivalent (below), which bounds
the effort from above.

## The options

**1. Custom Swift loop on the ADR-0007 adapters.** Everything above. Full control of
the extras bag (FR-006, FR-060), no new dependency, no process boundary, continuous
with shipped code. Cost: we own retries, delta parsing, and provider drift — which
ADR-0007 already accepted for chat, and the probes show the increment is modest.

**2. Embedded TS/Python framework as a subprocess** (Pydantic AI, LangGraph, Mastra,
Vercel AI SDK). Mature orchestration for free, at the cost of: bundling a Node or
Python runtime into a signed, notarized, hardened-runtime app (real size and
signing surface — every nested Mach-O needs signing, and large bundles notarize
slowly); a JSON-RPC bridge between the loop and every tool (our tools are Swift, so
each tool call crosses the boundary twice); discarding the shipped adapters; and
trusting the framework to round-trip quirks 1–3 (Pydantic AI tracks DeepSeek
reasoning and Gemini thought signatures as evolving issues — it's a moving target
even for them). Contradicts the native-Swift preference structurally.

**3. LiteLLM (or any normalization proxy).** One wire format, ~100 providers. Same
bundled-Python cost as option 2, plus it *flattens* provider-specific fields — the
exact opposite of FR-060 and of what quirks 1–3 need. ADR-0007 already rejected this
shape for chat; the reasons strengthen for the loop.

**4. `open-agent-sdk-swift`** ([terryso/open-agent-sdk-swift](https://github.com/terryso/open-agent-sdk-swift),
MIT) — the one genuinely Swift-native agent SDK found: in-process loop, Swift
concurrency, MCP, session persistence, Anthropic + OpenAI-compatible clients.
Checked 2026-07-18: v0.10.0, 26 stars, essentially one maintainer, Claude-first in
design. As a *dependency* it fails the bus-factor and neutrality-priority tests; as
a *reference implementation* it's valuable — it demonstrates the whole job is
solo-sized in Swift, and it's MIT if we want to compare notes on delta accumulation.

**5. Apple Foundation Models provider protocol** (WWDC26: `LanguageModel` /
`LanguageModelExecutor`, `Transcript` with typed `.toolCalls`/`.toolOutput`/
`.reasoning` entries, streaming channel with `toolCallDelta`). Apple's own neutral
abstraction — architecturally the closest thing to what we're building, and
"Anthropic and Google will soon extend the Foundation Models framework with Swift
packages of their own." The later POC proved Work Agent can adopt it without waiting
for those packages by implementing executors over the two existing transports. It
requires macOS 27, now accepted in NFR-009, and provider packages still cannot be the
coverage plan for all eleven curated providers.

## Conclusion

The original evidence correctly favored native Swift and the two shipped wire formats,
but its custom-loop conclusion was superseded by the later Foundation Models POC.
ADR-0006 now keeps the native and neutrality conclusions while using Apple for the
intelligence session and a Swift SPM package for durable Work Agent semantics. The
opaque provider-state findings remain essential and are represented through Apple
transcript metadata/signatures with ownership-aware failover.
