# Adapting Work Agent to the Foundation Models 27 APIs

**Last verified: 2026-07-18.** Research into whether the macOS 27 Foundation Models
APIs should replace or reshape the proposed Work Agent loop. Evidence comes from
Apple's WWDC26 material and the public Swift interfaces shipped in Xcode 27 beta 1
(`27A5194q`) and beta 3 (`27A5218g`, macOS 27.0 SDK), inspected locally on 2026-07-18.

This research and its POC supplied the evidence for the accepted ADR-0006 revision.
Work Agent does not need to wait for Anthropic or Google to ship packages to use
Apple's abstraction: its existing HTTP adapters can conform to Apple's public
`LanguageModel`/`LanguageModelExecutor` protocols directly.

---

## Recommendation

**Accepted: the hybrid. Every bounded architecture gate in this POC passes.**
The matching beta-3 SDK/runtime passes the real two-request Apple session/tool cycle;
deterministic probes establish cancellation, retry, tool-error, concurrency,
stream-observation and reconstructed model-switch behavior; and the two real executor
conformances pass against all three live providers. The best target is:

- Foundation Models supplies the in-memory model/session vocabulary and model/tool
  execution substrate on macOS 27: `LanguageModel`, `LanguageModelExecutor`,
  `LanguageModelSession`, `Transcript`, `Tool`, generation schemas, token counts,
  dynamic profiles, and response usage.
- Work Agent owns the durable task runtime around it: a versioned archive of Apple's
  Codable transcript plus an execution journal, checkpoints, interrupts/approvals,
  retry and idempotency policy, effect-aware tool
  execution, trace storage, provider failover policy, error presentation, and evals.
- Work Agent's two existing wire adapters become `LanguageModelExecutor`
  implementations rather than parallel provider APIs. The existing parsing work is
  retained; the bespoke neutral session and basic tool loop are candidates for
  deletion.
- Work Agent tools keep their richer host contract and are bridged to Apple's `Tool`.
  Apple's tool protocol is the model-facing callable shape, not the policy boundary.

This conclusion is no longer based solely on API inspection. The bounded POC implements
**two executor conformances** (OpenAI-compatible and Anthropic)
tested against **three live providers** (DeepSeek, Google, and Anthropic). Each executor
completes a streamed two-request tool cycle through `LanguageModelSession`; together
the cases cover signed reasoning/metadata round-trip and a model switch.

Toni accepted macOS 27 as the architectural minimum and the native runtime as an SPM
package above Foundation Models: "we'll have three layers." ADR-0006, ADR-0002 and the
implementation plans now encode that decision; increment 4 must not build the old
custom transcript/basic loop.

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
Apple's [July 2026 release listing](https://developer.apple.com/news/releases/?id=03022026f)
identifies Xcode 27 beta 3 as build `27A5218g` and macOS 27 beta 3 v2 as
`26A5378n`; that is the pairing used for the passing rerun.

The current project already has `MACOSX_DEPLOYMENT_TARGET = 27.0`, so the prototype
has no deployment-target obstacle. NFR-009 makes that existing setting the accepted
architectural minimum rather than an incidental template value.

### Platform and model coverage

The accepted SPM target is broader than the Work Agent product target. Work Agent
remains a macOS app, while the runtime package supports iOS 27 and macOS 27. Apple's
[`LanguageModelExecutor`](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor)
is explicitly the bridge to either a server API or a local inference engine, so the
runtime must accept any injected `LanguageModel` rather than branch on “cloud” versus
“local.” Apple's
[`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
provides the on-device Apple Intelligence model; Apple also identifies Private Cloud
Compute, Core AI, MLX and provider/community packages as participants in the same
protocol family.

This does not make arbitrary model files work automatically. A model needs a
`LanguageModel`/`LanguageModelExecutor` conformance that translates transcript,
generation options and streamed events. Apple's system model also requires an eligible
device, Apple Intelligence enabled and model assets available, so hosts must check
availability and provide a fallback. The current POC has executed on macOS only; iOS
compilation and eligible-iPhone execution belong to the production package conformance
matrix before claiming iPhone support.

---

## Direct type mapping

| Work Agent proposal | Foundation Models 27 | What to do |
|---|---|---|
| `AgentMessage` / content blocks | `Transcript.Entry` and `Transcript.Segment` | Prefer Apple's in-memory representation if the POC preserves every provider round-trip. |
| `.text` | `.response`/`.prompt` with text segments | Direct mapping. |
| `.reasoning` | `Transcript.Reasoning` | Direct mapping; Apple includes segments, signature, and metadata. |
| `ProviderExtras` | entry metadata, reasoning signature, tool-call metadata, or a custom segment | Replace the one catch-all bag with typed Apple locations plus a provider-namespaced metadata convention. Archive Apple's Codable transcript and filter metadata when crossing provider boundaries. |
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

The inspected macOS 27 `Transcript` is Codable as well as `Sendable` and
`RandomAccessCollection`. The POC round-trips it through canonical JSON, including
reasoning signatures and provider metadata. The decoded value re-encodes identically,
although the beta framework's `Equatable` implementation does not consider the
metadata round-trip equal; persistence tests therefore compare canonical encodings and
semantics rather than relying on `==`.

Work Agent should version an archive around Apple's transcript rather than create a
parallel message hierarchy. That archive is the durable model-context projection. A
separate append-only run journal remains necessary for attempt, tool, side-effect,
interrupt and checkpoint truth; those execution facts do not belong in a conversation
transcript.

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

**Read from the beta-3 swiftinterface (2026-07-18):** the protocol is five
requirements with three defaulted — `description` and `call` are the only mandatory
ones (`name` defaults to the type name; `parameters` derives from `@Generable`
arguments; scalar argument types are explicitly `unavailable`), and there is **no
metadata slot of any kind**. Sessions take `[any Tool]`, so the runtime can hand the
session generic delegating wrappers. Consequence, adopted as the north-star design
in [../plans/runtime-api.md](../plans/runtime-api.md) §3: interception (trace,
budget, timeout, corrective error handling) needs no developer-facing API at all,
and effect/idempotency metadata travels as *data* (`ToolAnnotations`, with an MCP
hint mapping) rather than as a second tool protocol. This supersedes the earlier
"richer host tool contract bridged to Apple's Tool" recommendation above.

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
| **C. Use Apple as session/model substrate** | Existing transports conform to `LanguageModelExecutor`; Apple transcript/session inside Work Agent's durable coordinator | Reuses native standards while retaining product control; future provider packages plug in | Requires a versioned transcript archive and real executor conformance proof | **Chosen.** Deterministic semantics, three live provider/session cycles and provider switching pass. |
| **D. Make Foundation Models the whole runtime** | App stores Apple transcript and relies on session/profile for orchestration | Least custom code | A Codable transcript still does not provide durable checkpoints, restart-safe interrupts, effect policy, attempt identity, or Work Agent trace guarantees | **Reject.** It is an intelligence session, not the product's task runtime. |

---

## Accepted three-layer boundary

```text
Work Agent app
  UI / credentials / catalog / app task storage / tool selection & approval policy
  (tool implementations moved into the package's ToolKit products, 2026-07-18 —
  see plans/runtime-api.md §6)
    ↓
Native Swift agent-runtime SPM package (iOS 27 + macOS 27)
  TaskCoordinator / RunPolicy / checkpoint / interrupt / failover / trace
  RunJournal (append-only execution truth)
  TranscriptArchive (versioned wrapper around Codable Apple Transcript)
  tool host and provider executors
    ↓
Foundation Models LanguageModelSession
  DynamicProfile: active model + tools + instructions + history transform
  WorkAgentToolBridge → ToolRunner → native/MCP tools
  OpenAICompatibleLanguageModel.Executor → existing HTTP/SSE parser
  AnthropicLanguageModel.Executor → existing HTTP/SSE parser
```

The middle package does not compete with Foundation Models' `LanguageModelSession`. It
is a **durable agent runtime for Foundation Models sessions** plus bridges for richer
tools, persistence, policy, traces and evaluation.

That is sharper than “Pydantic AI for Swift”: Apple supplies the language-model SDK;
the native runtime package supplies the long-running work semantics native apps need.

---

## POC gates used to change ADR-0006

The spike answered these with code and recorded fixtures. A failed gate would have been
evidence to retain or narrow the custom layer; the bounded gates passed.

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

## POC execution instructions

This is deliberately a decision spike, not an early production implementation. It
contains executable Swift and therefore follows the repo's code-increment workflow:
post a DOR, get Toni's explicit go-ahead, triage/claim the review backlog, create a
worktree and PR, and report the normal DOD. The DOR should quote Toni's request for the
POC and identify ADR-0006 as the decision potentially changing; it should not invent
new product FRs for experimental code.

### 1. Create an isolated experiment target

Add a Swift package at `Experiments/FoundationModelsPOC/`, requiring macOS 27 and
containing no production-app target membership:

```text
Experiments/FoundationModelsPOC/
  Package.swift
  Sources/FoundationModelsPOC/
    DurableTranscript.swift
    FoundationModelsToolBridge.swift
    OpenAICompatibleModel.swift
    AnthropicModel.swift
    ProbeRunner.swift
  Tests/FoundationModelsPOCTests/
    ExecutorFixtureTests.swift
    DurableTranscriptTests.swift
    SchemaBridgeTests.swift
    SessionBehaviorTests.swift
  Tests/Fixtures/
    deepseek/
    google/
    anthropic/
```

The executor types may reuse or extract the existing request/SSE parsing logic for the
experiment, but production files are not refactored during the spike. The purpose is
to prove the Apple seam, not begin the migration before the decision.

### 2. Implement the smallest provider conformances

- `OpenAICompatibleModel: LanguageModel` and its `LanguageModelExecutor` translate
  Apple's request transcript/tool definitions/options into the existing OpenAI-
  compatible wire shape, then translate SSE into response, reasoning, tool-call,
  metadata, signature, and usage channel events.
- `AnthropicModel: LanguageModel` and its executor do the equivalent for Anthropic
  messages/content blocks.
- Provider credentials and base URLs are injected by the probe runner. No secret is
  written to fixtures, logs, command output, metadata, or the trace.
- Unsupported Apple transcript entries or generation options fail explicitly; the POC
  must not silently flatten them.

### 3. Add one safe bridged tool

Implement a POC-only `read_fixture` Work Agent tool that can read only a committed
fixture directory. Wrap it in `FoundationModelsToolBridge` and exercise all of the
path below:

```text
LanguageModelSession
  → FoundationModels.Tool.call
  → Work Agent-style ToolRunner stub
  → complete raw trace capture
  → budgeted Tool output
  → LanguageModelSession continuation
```

Add a second validation case in which the model first supplies invalid arguments, gets
a structured corrective tool result, and succeeds on the next attempt. This determines
whether Apple permits the recoverable tool-error behavior Work Agent needs.

### 4. Capture and replay the two executor shapes

When the Apple executor can run, save a scrubbed fixture containing:

- the provider request body with credentials and user-specific content removed;
- raw SSE `data` payloads in arrival order;
- executor channel events produced from those payloads;
- the resulting Apple transcript entries; and
- the second provider request that replays the reasoning/tool state.

If the Apple runtime fails before a provider request, reconstruct minimal fixtures from
verified provider wire shapes, label them as reconstructed, and do not misrepresent
them as captured traffic. Fixture tests run without network or keys and assert exact
IDs, source ordering, partial-argument accumulation, signatures/metadata, stop
semantics, and usage. Do not record arbitrary response prose as a golden value; assert
the structural trajectory.

### 5. Run three live round trips

Use one deterministic prompt that requires `read_fixture`, then asks the model to
report the fixture's sentinel value. Run it through:

1. DeepSeek via `OpenAICompatibleModel` — proves `reasoning_content` replay;
2. Google via `OpenAICompatibleModel` — proves thought-signature metadata replay; and
3. Anthropic via `AnthropicModel` — proves signed thinking-block replay.

Each case must observe model request → streamed tool call → bridged local execution →
tool output → second model request → final response. A single-request “the model
emitted a tool call” probe does not count.

### 6. Exercise session semantics with deterministic executors

Use scripted in-process `LanguageModelExecutor` fakes, not paid live calls, to test:

- two simultaneous tool calls preserve provider source order while the bridge applies
  a concurrency limit;
- cancellation reaches the executor and tool tasks;
- a stream that fails after partial response/tool arguments can retry without
  committing duplicate transcript entries;
- response/reasoning/tool/usage events are observable in time for a live UI; and
- a session reconstructed from `DurableTranscript` yields the expected next request.

Test model switching both ways: first with scripted executors for exact assertions,
then once live from DeepSeek to Anthropic using a reconstructed session or dynamic
profile. Record which provider metadata is preserved in canonical state and which is
excluded from the new provider's request.

### 7. Test the schema boundary

- Convert the schemas for `ask_user`, `update_plan`, and the six planned file tools to
  `GenerationSchema` and back to the POC's canonical schema representation.
- Test representative MCP schemas: nested objects, arrays, enums, optional fields,
  unions/`anyOf`, numeric constraints, additional properties, and `$ref`.
- Produce a table of supported, transformed, and rejected JSON Schema features. Every
  rejection includes the keyword and path. Do not add a lossy catch-all conversion to
  make the test green.

### 8. Run and report

The offline gate is one command from the repository root:

```bash
swift test --package-path Experiments/FoundationModelsPOC
```

The package also exposes one probe command whose help lists the three provider cases
and whose output is a pass/fail matrix without secrets. The exact invocation is fixed
in the package README once argument parsing is implemented; it must support running
one provider at a time so a failed or unfunded provider does not hide other results.

Run the offline suite first, then the three live cases. Repeat the offline suite using
only the captured fixtures to prove the evidence is reproducible without network.

---

## Expected POC deliverable

The deliverable is a **reproducible architecture decision package**, not a demo and not
production agent code. A critical gate may produce a completed no-adopt decision; the
deliverable must then preserve enough evidence to reproduce the blocker without
pretending downstream gates ran. It contains:

1. **Runnable experiment.** `Experiments/FoundationModelsPOC/` builds on a clean
   checkout and its offline suite passes with the documented command.
2. **Scrubbed evidence.** Credential-free fixtures cover the DeepSeek/Google OpenAI-
   compatible and Anthropic stream structures. Each says whether it was captured or
   reconstructed. No key or personal data is present.
3. **Automated results.** Every executable fixture, transcript, tool and schema boundary
   has a test. Session gates blocked by a loader/runtime failure are listed explicitly,
   not inferred.
4. **Live-results matrix.** Provider/model, tool-call emission, provider-state replay,
   second request and final response are marked pass/fail with the probe date. Apple
   session execution, cancellation and failover are separately marked passed, failed,
   or blocked with the exact structural symptom.
5. **Schema compatibility table.** Supported and unsupported Apple ↔ canonical/MCP
   schema features are recorded with the chosen fallback or blocker.
6. **Measured code delta.** Report the experiment's non-test source lines and identify
   which existing adapter code was reused when the session can execute. A pre-main
   loader failure means this comparison is not yet meaningful and must say so.
7. **Decision update.** Add a results section to this research doc. If every critical
   gate passes, update ADR-0006 in place to the hybrid and revise the agent-loop/tool
   plans in the same doc increment. If a critical gate fails or is blocked, keep
   ADR-0006 and record the precise boundary Apple could not satisfy. No ambiguous
   “promising” conclusion.
8. **Cleanup decision.** State whether the experiment package remains as a conformance
   harness, is folded into production tests during implementation, or is deleted after
   its fixtures/results are preserved. Do not leave an ownerless prototype.

The POC may successfully deliver a **no-adopt** decision. Success means the evidence is
complete and the architectural consequence is explicit; it does not mean forcing the
hybrid to pass.

## POC results — 2026-07-18

**Result: every bounded architecture gate passes. The remaining decision is product
scope—whether Work Agent accepts macOS 27 as its minimum—not technical feasibility.**
This is no longer
an environment-blocked result: the exact SDK/runtime problem is understood and fixed.

The package at `Experiments/FoundationModelsPOC/` now provides five distinct kinds of
evidence:

1. **Offline conformance.** Nineteen Swift Testing cases pass. They cover a canonical
   Codable Apple `Transcript` archive, provider-metadata filtering on model switch,
   partial OpenAI tool arguments and usage, Google thought signatures, Anthropic block
   identity/thinking signatures/usage, precise malformed-stream errors, a real
   Foundation Models `Tool` bridge, raw trace-before-budget behavior, strict schema
   conversion, mixed-enum rejection and symlink-safe fixture access. Reconstructed,
   credential-free SSE fixtures make the three wire shapes reproducible; they are not
   represented as raw captures.
2. **Live provider transport.** The repository-root `.env` contains the expected keys.
   Reproducible, secret-safe direct two-request cycles pass for DeepSeek
   `deepseek-v4-pro`, Google `gemini-3.5-flash`, and Anthropic `claude-sonnet-5`. Each
   returns a tool call, accepts local tool output in a second request, preserves the
   provider state required by its wire protocol, and returns a final response. The
   script prints only HTTP status and structural booleans. Anthropic's current model
   rejected the older `thinking.type: enabled` shape and passed with adaptive thinking
   plus maximum output effort; this is exactly the provider drift the harness should
   expose.
3. **Real Apple session surface.** A scripted `LanguageModel`,
   `LanguageModelExecutor`, `LanguageModelSession` and bridged Foundation Models `Tool`
   two-request cycle passes on macOS 27 beta 3 v2 `26A5378n` with Xcode 27 beta 3
   `27A5218g`. It records two requests, one tool call and output, one reasoning entry,
   reasoning-signature replay, canonical transcript archive replay, and 48 total
   tokens. The original failure paired Xcode beta 1 `27A5194q` with the beta-3 OS:
   beta 1 compiled a call to generic `send<T: Event>(T)`, while the OS exports concrete
   `send(Event)`. These are distinct Swift ABI symbols. Updating Xcode and rebuilding
   fixed it.

   The exact evidence, read from the beta-1 SDK `.tbd` and the system dyld shared
   cache, was:

   - beta-1 SDK: `_$s16FoundationModels38LanguageModelExecutorGenerationChannelV4sendyyxYaAC5EventRzlF`
   - beta-3 runtime: `_$s16FoundationModels38LanguageModelExecutorGenerationChannelV4sendyyAC5EventVYaF`

   Xcode beta 3 exposes the concrete `Event` API and compiles against the runtime
   symbol. The compiler then surfaced the normal source migration from typed event
   structs to `LanguageModelExecutorGenerationChannel.Event`; after that migration,
   the executable passed.

4. **Deterministic session semantics.** Scripted executors and tools establish the
   behavior instead of inferring it from interfaces:

   - cancellation reaches a blocked executor as `CancellationError`;
   - cancellation reaches a blocked tool, while the session surface wraps that
     cancellation in `LanguageModelSession.ToolCallError`;
   - `.revertTranscript` discards a partial failed response, allowing an app-controlled
     retry to commit exactly one recovered response; the session does not supply retry
     policy itself;
   - a thrown tool error terminates the response as `ToolCallError` and does not become
     corrective tool output visible to the model, so Work Agent's tool bridge must
     classify and encode recoverable failures;
   - two tool calls execute concurrently even when the second completes first, while
     transcript outputs commit in provider source order; Work Agent still needs a
     resource-aware concurrency limiter because the session starts both;
   - a reconstructed session receives the filtered transcript on a provider switch,
     with the foreign reasoning signature and metadata absent; and
   - response snapshots include final text and usage but can coalesce individual
     executor events even across a deliberate delay. Lossless live trace/UI events
     must therefore be captured at the executor channel or app-owned hooks, not
     reconstructed from response snapshots.

5. **Live Apple executor/session integration.** The POC's
   `OpenAICompatibleLiveExecutor` and `AnthropicLiveExecutor` translate Apple's
   `LanguageModelExecutorGenerationRequest`, stream provider events into Apple's typed
   generation channel, replay provider-owned reasoning/signatures, and translate the
   second request back to each wire format. Through `LanguageModelSession`, all three
   live cases complete one tool call and output followed by a final response:

   | Provider | Tool cycle | Provider state | Final response | Session tokens in run |
   |---|---|---|---|---:|
   | DeepSeek `deepseek-v4-pro` | Pass | Pass | Pass | 1,285 |
   | Google `gemini-3.5-flash` | Pass | Pass | Pass | 540 |
   | Anthropic `claude-sonnet-5` | Pass | Pass | Pass | 2,130 |

   A separate live DeepSeek-to-Anthropic reconstruction also passes: the source tool
   task completes, `TranscriptArchive.replay(to:)` removes DeepSeek-owned state, and
   Anthropic produces the next response from the reconstructed Apple session.

The direct transport script remains useful because it isolates provider drift from
Apple-session behavior; the live executor probes now prove the combined path. Dynamic
profile switching, image/custom segments, and a larger planned-tool/MCP schema corpus
remain completeness work for implementation, not blockers to the architecture choice.

The experiment currently contains 1,758 lines of non-test Swift and an 83-line direct
live probe script. The live executor implementation is 543 lines of deliberately
explicit POC code. It reuses production providers' verified wire assumptions but no
production source file, so it proves feasibility rather than a final production code
delta. Implementation should refactor the shipped parsers and request encoders into
the executor conformances instead of maintaining the POC copies in parallel.

### Coverage boundary: comprehensive for the decision, not exhaustive for the framework

The POC is comprehensive for the provider-extensible agent-loop decision: it exercises
the exact Apple types Work Agent would put on its critical path, both wire formats,
three live providers, provider-state replay and switching, the model/tool/model cycle,
cancellation, partial failure, tool failure, parallel tools, response observation,
usage, archival and the strict dynamic-schema boundary.

It is **not** an exhaustive test of every Foundation Models API. The following surfaces
remain untested because they are implementation follow-ups or outside this decision:

| Surface | Status | Why it is not an architecture blocker |
|---|---|---|
| Dynamic profiles, `historyTransform`, lifecycle hooks and session properties | API inspected; not executed | Valuable context/trace ergonomics. The app can reconstruct sessions and observe executors without them. Test before relying on each hook's ordering. |
| `Generable` structured final outputs beyond tool arguments | Compile-time surface linked; no live output matrix | Add conformance tests when a product feature introduces typed final output. |
| Images, attachments and custom transcript segments | Not executed | Current agent-loop increment is text/tool work. Each new modality needs provider-specific contract tests. |
| Exact token-count APIs, prewarming, on-device and PCC models | Usage events tested; other paths not executed | They optimize or add models; they do not change the executor/session ownership boundary. |
| Feedback and Instruments integration | Not executed; **no evaluations API exists in the macOS 27 SDK** (verified 2026-07-18 — the framework ships only `LanguageModelFeedback`) | The eval gap is entirely Work Agent's to fill: provider-neutral trajectory/effect evals and local trace truth. |
| Refusal, guardrail, context-window and concurrent-session error variants | Interface inspected; no fault matrix | Production adapters need typed error fixtures before shipping, but the coordinator already owns recovery and presentation. |
| Every JSON Schema/MCP dialect feature | Strict representative subset measured | Unsupported keywords fail with path/keyword instead of being lost. Expand against the actual planned-tool and MCP corpus during implementation. |

Calling this “the whole Apple framework is exhaustively tested” would be false. Calling
the hybrid technically feasible and evidence-backed for Work Agent's loop is justified.

### Schema compatibility measured by the POC

| JSON Schema feature | Result | Boundary |
|---|---|---|
| Object properties and required names | Supported | Required names must exist; omitted names become optional Apple properties. |
| String, integer, number and boolean | Supported | Converted to native dynamic generation schemas. |
| Arrays with an item schema | Supported | Recursively converted. |
| Nonempty string enums | Supported | Converted to an Apple `anyOf` value schema. |
| `additionalProperties: false` | Supported | Matches the closed generated object. |
| Mixed/non-string or empty enums | Rejected | Exact enum element path or invalid enum diagnostic. |
| `anyOf`, `oneOf`, `allOf`, `$ref` | Rejected | Exact unsupported keyword and path; never flattened. |
| Numeric constraints and `pattern` | Rejected | Exact unsupported keyword and path. |
| Open/schema-valued `additionalProperties` | Rejected | The bridge cannot preserve arbitrary maps faithfully. |
| Descriptions, defaults, examples and any unknown keyword | Rejected | The strict subset never silently discards model-facing semantics. |

### Reproduction and cleanup decision

The package README contains the exact offline, Apple-session and live-provider
commands. The experiment remains in the repository as a conformance harness for API
and provider drift. If Toni accepts the hybrid, fold its fixtures, scripted semantics
tests and live executor matrix into the production test strategy. Do not leave a second
independent set of provider adapters after implementation.

### Explicitly out of scope

- Production UI, task persistence, or migration of the current chat screen.
- Implementing the planned file tools beyond schema conversion and the safe fixture
  tool.
- MCP transport, provider-hosted web search, approvals UI, graph workflows, subagents,
  or long-term memory.
- Refactoring the production adapters before the ADR decision.
- Performance optimization beyond recording enough timing/token data to identify a
  material regression.

---

## Required plan changes under the accepted hybrid

Toni made the decision; ADR-0006 and the implementation plans apply these changes.

1. Replace `AgentMessage` as the live session type with `Transcript`; persist it in a
   versioned `TranscriptArchive` and keep execution facts in a separate `RunJournal`.
2. Replace `ToolCapableProvider.stream(...)` with two `LanguageModel`/
   `LanguageModelExecutor` implementations built from the existing adapters.
3. Remove the bespoke basic `AgentLoop`; introduce `TaskCoordinator`, which owns
   policy and drives/rebuilds a `LanguageModelSession`.
4. Tools stay plain `FoundationModels.Tool`s; the runtime instruments them via
   generic wrappers and carries effects/idempotency as `ToolAnnotations` data —
   see [../plans/runtime-api.md](../plans/runtime-api.md) §3, which supersedes the
   originally listed `WorkAgentToolBridge` host-contract design. Registry, trace,
   and output budgets survive inside the wrapper pipeline.
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
- **Provider package coverage.** Anthropic's
  [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels)
  and a Google Gemini equivalent shipped (checked 2026-07-18: v0.1, OS-27-beta-only,
  best-effort, closed to contributions; Anthropic's production auth assumes a proxy
  backend rather than BYOK keys). They cover 2 of 11 curated providers and mismatch
  our credential model, so our two executor conformances remain necessary; the vendor
  packages serve as conformance references. See
  [apple-llm-stack-second-opinion.md](apple-llm-stack-second-opinion.md).
- **Schema mismatch.** `GenerationSchema` is not arbitrary JSON Schema. MCP is the
  highest-risk bridge and needs a real corpus test.
- **Apple-controlled loop semantics.** If there is no supported way to intercept and
  resume recoverable tool failures, approvals, or partial streams safely, the hybrid
  should use Apple's transcript/executor types but retain Work Agent's own loop.
- **Conversation versus execution state.** A transcript archive and run journal have
  different responsibilities. Derive model context from committed run state at explicit
  boundaries and test reconstruction; never create a second shadow transcript.

---

## Bottom line

The new APIs are not merely another provider integration. They now cover the neutral
Swift language-model and tool-session layer Work Agent planned to create. Ignoring them
would spend product engineering on an increasingly standard platform concern.

They do **not** cover the hard Work Agent concern: a trustworthy, durable task that can
act on a person's Mac, stop for them, survive failure, switch providers, preserve every
trace, and recover without duplicating consequences.

The retained live-executor gate passes, so the architectural center should move one layer up:

> Use Foundation Models for intelligence sessions. Build Work Agent for durable work.

The matching seed executes the loop, the deterministic semantics are measured, all
three live providers pass through Apple executors, and cross-provider reconstruction
succeeds. Toni resolved the remaining product gate by accepting macOS 27 and the
three-layer app → Swift SPM runtime → Foundation Models architecture.
