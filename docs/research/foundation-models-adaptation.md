# Adapting Work Agent to the Foundation Models 27 APIs

**Last verified: 2026-07-18.** Research into whether the macOS 27 Foundation Models
APIs should replace or reshape the proposed Work Agent loop. Evidence comes from
Apple's WWDC26 material and the public Swift interface shipped in Xcode 27.0 beta
(`27A5194q`, macOS 27.0 SDK), inspected locally on 2026-07-18.

This is decision input, not an accepted change to ADR-0006. It does challenge one of
that ADR's premises: Work Agent no longer needs to wait for Anthropic or Google to ship
packages to use Apple's abstraction. The app can make its existing HTTP adapters
conform to Apple's public `LanguageModel`/`LanguageModelExecutor` protocols itself.

---

## Recommendation

**Adapt, but do not hand the whole runtime to Apple.** The best target is a hybrid:

- Foundation Models supplies the in-memory model/session vocabulary and model/tool
  execution substrate on macOS 27: `LanguageModel`, `LanguageModelExecutor`,
  `LanguageModelSession`, `Transcript`, `Tool`, generation schemas, token counts,
  dynamic profiles, and response usage.
- Work Agent owns the durable task runtime around it: canonical Codable state,
  checkpoints, interrupts/approvals, retry and idempotency policy, effect-aware tool
  execution, trace storage, provider failover policy, error presentation, and evals.
- Work Agent's two existing wire adapters become `LanguageModelExecutor`
  implementations rather than parallel provider APIs. The existing parsing work is
  retained; the bespoke neutral session and basic tool loop are candidates for
  deletion.
- Work Agent tools keep their richer host contract and are bridged to Apple's `Tool`.
  Apple's tool protocol is the model-facing callable shape, not the policy boundary.

Do not commit to that architecture solely from API inspection. Run one bounded POC
before increment 4: one OpenAI-compatible provider and Anthropic, each completing a
streamed two-request tool cycle through `LanguageModelSession`, including signed
reasoning/metadata round-trip and a model switch. If the POC passes the gates below,
update ADR-0006 before building the production loop.

---

## Why this is now a real option

Apple's original macOS 26 Foundation Models API was primarily an on-device model
session with tools and guided generation. The macOS 27 surface is materially different:

- `LanguageModel` lets any local or server model declare capabilities and provide an
  executor configuration.
- `LanguageModelExecutor` receives a complete neutral generation request and streams
  response, reasoning, tool-call, metadata, signature, and usage events back through a
  typed channel.
- `LanguageModelSession` accepts any conforming model and automatically manages the
  transcript and tool-call cycle.
- Dynamic profiles can change instructions, tools, model, reasoning level, tool-call
  mode, and history transform while preserving one session history.
- `Transcript` has first-class instructions, prompt, reasoning, tool calls, tool
  output, response, structured content, image attachments, custom segments, and
  per-entry metadata.
- Apple's framework can count tokens for prompts, instructions, tools, schemas, and
  transcript entries.

Apple describes the provider contract in
[“Bring an LLM provider to the Foundation Models framework”](https://developer.apple.com/videos/play/wwdc2026/339/)
and the session/orchestration features in
[“What's new in the Foundation Models framework”](https://developer.apple.com/videos/play/wwdc2026/241/)
and [“Build agentic app experiences with the Foundation Models framework”](https://developer.apple.com/videos/play/wwdc2026/242/).
The API summary is also in the official
[Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels).

The current project already has `MACOSX_DEPLOYMENT_TARGET = 27.0`, so the prototype
has no immediate deployment-target obstacle. PRODUCT.md still lists minimum macOS as
an open product decision; making Foundation Models foundational would turn macOS 27
from an incidental project setting into an architectural requirement.

---

## Direct type mapping

| Work Agent proposal | Foundation Models 27 | What to do |
|---|---|---|
| `AgentMessage` / content blocks | `Transcript.Entry` and `Transcript.Segment` | Prefer Apple's in-memory representation if the POC preserves every provider round-trip. |
| `.text` | `.response`/`.prompt` with text segments | Direct mapping. |
| `.reasoning` | `Transcript.Reasoning` | Direct mapping; Apple includes segments, signature, and metadata. |
| `ProviderExtras` | entry metadata, reasoning signature, tool-call metadata, or a custom segment | Replace the one catch-all bag with typed Apple locations plus a provider-namespaced metadata convention. Keep an app-owned Codable equivalent for persistence. |
| `ToolSpec` | `Transcript.ToolDefinition` + `GenerationSchema` | Bridge the canonical supported subset; contract-test conversions. |
| `Tool` | `FoundationModels.Tool<Arguments, Output>` | Wrap Work Agent tools. Do not discard host context, effects, budgets, or tracing. |
| `ToolCapableProvider` | `LanguageModel` + `LanguageModelExecutor` | Make the existing OpenAI-compatible and Anthropic transports conform. |
| `AgentStreamEvent` | executor generation-channel events; session response snapshots; transcript hooks | Use session snapshots/hooks for app observation and executor channel events inside adapters. |
| `AgentLoop` | `LanguageModelSession` | Let Apple own the basic model → tool → model cycle if its error/cancellation semantics pass the POC. Keep Work Agent's durable task coordinator outside it. |
| `ToolRegistry.tools(for:)` | dynamic instructions/profile branches | Use dynamic profiles to assemble tools and instructions per phase/turn. |
| `ModelCapabilities` | `LanguageModelCapabilities` | Map the curated registry into Apple's declared vision/reasoning/tool/guided-generation capabilities; retain richer Work Agent capability data alongside it. |
| reasoning effort | `ContextOptions.ReasoningLevel` | Map provider-specific effort values in each executor; use `.custom` where the common levels are insufficient. |
| tool choice | `GenerationOptions.ToolCallingMode` | Direct mapping for allowed/required/disallowed. Provider-specific forced-tool choice may still require request metadata. |
| context filtering | dynamic profile `historyTransform` | Good fit for per-request compaction, privacy filtering, and provider-switch cleanup without mutating canonical history. |
| token estimation | exact session token-count APIs | Prefer exact counts from the active executor; retain a fallback estimate only for providers that cannot count. |
| trace lifecycle | `onPrompt`, `onResponse`, `onToolCall`, `onToolOutput`, transcript and usage | Feed these into Work Agent's structured trace. They do not replace its durable trace store. |
| structured final output | `Generable`, `GenerationSchema`, response format | Adopt as the Swift-native typed-output seam. |

The strongest alignment is the provider state that originally drove ADR-0006. In the
local macOS 27 interface:

- `Transcript.Reasoning` carries `signature: Data?` and arbitrary Codable/Sendable/
  Equatable metadata;
- tool calls and responses also carry arbitrary metadata;
- the provider executor can stream a reasoning-signature update separately from text;
- tool-call arguments stream as ID/name-correlated fragments; and
- custom transcript segments can carry a provider-defined Codable payload.

DeepSeek `reasoning_content`, Google thought signatures, and Anthropic signed thinking
blocks therefore have a natural home without inventing an entirely separate neutral
message system. The POC must still prove replay behavior against the real endpoints.

---

## What Foundation Models should own

### The neutral in-memory transcript

Apple's transcript is richer than the proposal and is likely to become the native
ecosystem's interoperability type. Aligning means future Apple, Anthropic, Google, Core
AI, MLX, PCC, and community model packages can participate without bespoke Work Agent
session plumbing.

### Model capability and generation options

Use Apple's standard capability declarations and generation options where their
semantics fit. Keep a namespaced metadata escape hatch and Work Agent registry fields
for capabilities Apple does not model, such as provider-hosted search details, cache
controls, or special reasoning modes.

### The basic tool-call loop

`LanguageModelSession` already takes tools, streams results, appends tool calls and
outputs to the transcript, and continues generation. Reimplementing that exact loop
creates maintenance without product differentiation. Work Agent should replace it only
if the POC finds a hard requirement Apple cannot express.

### Dynamic context and model composition

Dynamic profiles are a close match for per-turn tool assembly and provider selection.
They can vary instructions, tools, model, reasoning level, and history transforms while
preserving shared history. That is more capable than the current proposed registry
alone and may cover deliberate model routing or manual failover cleanly.

### Schema derivation and typed output

`@Generable`, `GenerationSchema`, and `GeneratedContent` provide Swift-native tool
arguments and structured outputs. Use them at the app/framework boundary instead of
building macros or another reflection system prematurely.

---

## What Work Agent must continue to own

### Durable canonical state

The inspected macOS 27 `Transcript` conforms to `Sendable`, `Equatable`, and
`RandomAccessCollection`, but **not `Codable`**. Its existential metadata, custom
segments, and native image attachments make generic persistence non-trivial.

Work Agent therefore still needs a versioned, Codable task/checkpoint representation.
It can map that representation to an Apple transcript for each live session. This is
not needless duplication: one is the durable product record; the other is the active
model-session view. The mapping and losslessness must be fixture-tested.

### Crash consistency and exact resume semantics

`LanguageModelSession` is an in-process conversation/session, not a durable workflow
engine. It does not define what happens when the app dies after a consequential tool
succeeds but before state is saved. Work Agent still needs invocation IDs, checkpoint
boundaries, idempotency classification, indeterminate-outcome recovery, and task-state
migration.

### Tool policy, budgeting, and host context

Apple's `Tool` has name, description, parameter schema, and `call(arguments:)`. It has
no effect annotations, workspace/context injection, output budget, trace recorder,
read ledger, approval policy, idempotency, resource key, or model-visible error class.
The Work Agent tool protocol remains valuable. An adapter should expose each Work
Agent tool as an Apple tool and route invocation back through `ToolRunner`.

### Interrupts and approvals that survive restart

An Apple tool or profile hook can suspend asynchronously, which is enough for a live
approval sheet. It is not enough for a question or approval that survives app exit.
Work Agent needs a serializable `AgentInterrupt` and a coordinator that ends the live
session cleanly, persists the interrupt, and rebuilds/resumes after user input.

### Full-fidelity traces and user legibility

The transcript and profile hooks are excellent trace inputs, but the product requires
the full record independent of what remains in model context. Work Agent owns raw tool
output before truncation, retries/attempts, policy decisions, checkpoints, errors,
friendly projections, and local retention. Apple Instruments is a development tool,
not the user's task history.

### Cross-provider behavior and failover policy

Apple makes models swappable but does not decide when Work Agent retries, pauses,
switches provider, strips incompatible metadata, explains cost/privacy changes, or
reconciles provider-exclusive tools. That is product/runtime policy and remains local.

---

## The four architecture options

| Option | What it means | Upside | Cost / failure mode | Verdict |
|---|---|---|---|---|
| **A. Ignore Foundation Models** | Build ADR-0006 exactly as proposed | Maximum control; can target older macOS | Duplicates Apple's transcript, schema, session loop, token counting, typed output, dynamic context; isolates future model packages | **Not recommended** unless the POC exposes a blocker or minimum macOS drops below 27. |
| **B. Add Apple as one provider** | Keep custom loop; wrap SystemLanguageModel/PCC behind `ChatProvider` | Lowest migration risk; adds Apple models | Gains almost none of the new neutral ecosystem; two transcript/tool systems remain | **Useful fallback**, not the best architecture. |
| **C. Use Apple as session/model substrate** | Existing transports conform to `LanguageModelExecutor`; Apple transcript/session inside Work Agent's durable coordinator | Reuses native standards while retaining product control; future provider packages plug in | Requires a durable transcript bridge and proof that session error/tool semantics are sufficient | **Recommended POC and likely target.** |
| **D. Make Foundation Models the whole runtime** | App stores Apple transcript and relies on session/profile for orchestration | Least custom code | No generic Codable state, durable checkpoints, restart-safe interrupts, effect policy, or Work Agent trace guarantees | **Reject.** It is an intelligence session, not the product's task runtime. |

---

## Proposed hybrid boundaries

```text
Work Agent app
  TaskCoordinator actor
    RunPolicy / checkpoint / interrupt / failover / trace
    DurableAgentState (Codable, versioned, canonical)
      ↕ lossless mapper
    Foundation Models Transcript + LanguageModelSession
      DynamicProfile: active model + tools + instructions + history transform
      WorkAgentToolBridge → ToolRunner → native/MCP tools
      OpenAICompatibleLanguageModel.Executor → existing HTTP/SSE parser
      AnthropicLanguageModel.Executor → existing HTTP/SSE parser
```

This boundary changes the future AgentKit thesis. A package extracted later should not
compete with Foundation Models' `LanguageModelSession`. It should be a **durable agent
runtime for Foundation Models sessions** plus bridges for richer tools, persistence,
policy, traces, and evaluation.

That is sharper than “Pydantic AI for Swift”: Apple supplies the language-model SDK;
AgentKit supplies the long-running work semantics native apps need.

---

## POC gates before changing ADR-0006

One short spike should answer these with code and recorded fixtures. A failed gate is
evidence to retain or narrow the custom layer, not something to hand-wave.

### Provider executor gates

- OpenAI-compatible SSE maps into response/reasoning/tool-call channel events without
  losing partial JSON, finish semantics, usage, or metadata.
- Anthropic SSE maps the same way, including signed thinking blocks.
- A two-request tool cycle succeeds against DeepSeek and Anthropic.
- DeepSeek reasoning content, Google's thought signature, and Anthropic thinking
  signature each survive transcript replay in their required wire location.
- Provider-exclusive server-side tools can be represented through metadata/custom
  segments without showing them as client-executed tools.

### Session gates

- Multiple tool calls preserve source order and can route through Work Agent's
  concurrency policy.
- A recoverable tool validation error can be returned to the model rather than always
  terminating the session with `ToolCallError`.
- Cancelling a response cancels the executor request and in-flight Work Agent tools.
- A partially failed stream does not commit duplicate transcript entries on retry.
- The app can observe reasoning, tool call, tool output, response, and usage early
  enough for live UI and trace recording.

### Persistence and failover gates

- Every transcript entry required by the funded providers round-trips losslessly
  through `DurableAgentState`.
- Rebuilding a session from a persisted transcript produces the same next wire request.
- Switching from provider A to B through a dynamic profile or reconstructed session
  preserves neutral content and safely ignores/strips A-only metadata.
- Tool definitions can be reconstructed with the same stable names, schema, and
  versions after restart.

### Tool/schema gates

- The six planned file-tool schemas and `ask_user`/`update_plan` convert to
  `GenerationSchema` without semantic loss.
- An arbitrary MCP JSON Schema either converts faithfully or fails with a precise
  unsupported-keyword diagnostic and a documented fallback path.
- Full tool output still reaches the Work Agent trace before the Apple-facing result is
  budgeted.

---

## Specific plan changes if the POC passes

These would require Toni's explicit decision and an ADR-0006 update in the same doc
increment; they are not applied by this research.

1. Replace `AgentMessage` as the live session type with `Transcript`; retain a
   `DurableAgentState` persistence model and explicit mapper.
2. Replace `ToolCapableProvider.stream(...)` with two `LanguageModel`/
   `LanguageModelExecutor` implementations built from the existing adapters.
3. Remove the bespoke basic `AgentLoop`; introduce `TaskCoordinator`, which owns
   policy and drives/rebuilds a `LanguageModelSession`.
4. Keep `Tool`, `ToolContext`, `ToolRunner`, registry, trace, and output budgets, but
   add `WorkAgentToolBridge: FoundationModels.Tool`.
5. Express per-turn tools/instructions/model through a dynamic profile. Use
   `historyTransform` as the model-facing context assembler, fed by Work Agent's
   canonical state and token budget.
6. Map Apple transcript/profile hooks into `AgentEvent` and the trace instead of
   creating a parallel streaming event taxonomy where Apple already has the event.
7. Use Apple token counts and usage as authoritative when the executor supplies them;
   retain estimates only as an explicit fallback.
8. Adopt `Generable`/`GenerationSchema` for typed outputs and built-in tool arguments,
   with a dynamic-schema bridge for MCP.

---

## Risks and watch items

- **Beta stability.** The local SDK is Xcode 27 beta and Apple's documentation warns
  that APIs can change before the final OS. Keep the adapter boundary narrow.
- **Minimum OS coupling.** The new provider protocol, reasoning entries, dynamic
  profiles, metadata, and tool-call mode are macOS 27-only. Adopting them settles the
  product's minimum-OS decision unless the app maintains a second runtime.
- **Open-source timing.** Apple announced the framework is going open source, but the
  OS-shipped API remains the dependable artifact inspected here. Do not plan around
  unreleased package internals.
- **Provider package coverage.** Anthropic and Google packages may reduce adapter work,
  but Work Agent's eleven-provider promise cannot depend on their schedule. Our two
  executor conformances remain necessary initially.
- **Schema mismatch.** `GenerationSchema` is not arbitrary JSON Schema. MCP is the
  highest-risk bridge and needs a real corpus test.
- **Apple-controlled loop semantics.** If there is no supported way to intercept and
  resume recoverable tool failures, approvals, or partial streams safely, the hybrid
  should use Apple's transcript/executor types but retain Work Agent's own loop.
- **Two state models.** A live Apple transcript and durable Work Agent state can drift.
  Make conversion centralized, versioned, and round-trip tested; never update them
  independently ad hoc.

---

## Bottom line

The new APIs are not merely another provider integration. They now cover the neutral
Swift language-model and tool-session layer Work Agent planned to create. Ignoring them
would spend product engineering on an increasingly standard platform concern.

They do **not** cover the hard Work Agent concern: a trustworthy, durable task that can
act on a person's Mac, stop for them, survive failure, switch providers, preserve every
trace, and recover without duplicating consequences.

So the architectural center should move one layer up:

> Use Foundation Models for intelligence sessions. Build Work Agent for durable work.

Prove the seam with the two-provider POC, then either update ADR-0006 to the hybrid or
record the exact failed gates that justify retaining the custom loop.
