# Agent framework comparison: what the popular runtimes actually provide

**Last verified: 2026-07-18.** This compares Work Agent's proposed native loop and
tool layer with widely adopted agent frameworks from a developer's perspective. It
is design input, not a new product requirement. Recommendations below are explicitly
recommendations until Toni accepts them in an increment DOR.

The local comparison targets are:

- [the tool architecture](../plans/tool-architecture.md);
- [the agent-loop runtime research](agent-loop-runtimes.md);
- [the Foundation Models adaptation research](foundation-models-adaptation.md);
- [ADR-0006](../decisions/0006-native-swift-agent-loop.md); and
- the code that exists today: streaming chat through `ChatProvider`, with no agent
  loop or tool runtime implemented yet.

This document is self-contained. It does not rely on an untracked working draft of an
agent-loop implementation plan. Concrete limits and execution policies below are
research recommendations, not accepted product requirements.

---

## Executive verdict

Work Agent's proposal gets the **small single-agent loop** mostly right. Its neutral
typed transcript, opaque provider-extras bag, adapter-owned wire translation,
structured cancellation, streamed events, dynamic tool registry, trace-before-
truncation rule, and typed tools all match the strongest ideas in current frameworks.
The provider-extras bag is better aligned with Work Agent's neutrality goal than the
common “normalize everything to one lowest-common-denominator message” approach.

The proposal is not yet equivalent to a production agent runtime. The popular
frameworks earn their keep mainly outside the model/tool/model cycle:

1. durable checkpoints and unambiguous resume semantics;
2. first-class interrupts and human approval;
3. composable run limits for tokens, cost, time, turns, and tool calls;
4. model-visible validation and tool-error recovery;
5. whole-context management, not only tool-output truncation;
6. structured observability plus repeatable evaluation;
7. deterministic workflow steps and idempotent side effects; and
8. progressive escape hatches from a simple agent to explicit workflows.

The right move is **not** to clone LangGraph before increment 4. It is to keep the
thin loop, but put in the few seams that are expensive to retrofit: checkpoint
boundaries, a general interrupt type, composable run policy, structured spans and
usage, tool execution policy, and recorded-replay evaluation. Graphs, multi-agent
teams, long-term memory, deployment servers, and RAG can remain absent until an
actual Work Agent task demands them.

---

## What “most popular” means here

There is no neutral framework-usage census. GitHub stars are a noisy measure of
attention, not production adoption or quality, but they are public and comparable.
The table uses a GitHub API snapshot on 2026-07-18 and includes the eleven major
open-source frameworks above roughly 18,000 stars that expose an agent loop or agent workflow.
The repositories are linked so the number can be refreshed rather than treated as
timeless fact.

| Framework | GitHub stars | Center of gravity | Developer-facing strength |
|---|---:|---|---|
| [Microsoft AutoGen](https://github.com/microsoft/autogen) | 59,811 | Event-driven single- and multi-agent systems | Many team patterns, termination conditions, save/load state, distributed runtime |
| [CrewAI](https://github.com/crewAIInc/crewAI) | 55,738 | Role-oriented crews plus deterministic flows | Fast multi-agent composition, batteries-included memory, guardrails, observability |
| [LlamaIndex](https://github.com/run-llama/llama_index) | 50,929 | Agents over data and retrieval | Deep data/RAG ecosystem, tools and tool specs, event-driven workflows |
| [Agno](https://github.com/agno-agi/agno) | 41,226 | Agent-platform SDK and control plane | Agents, teams, workflows, sessions, memory, knowledge, traces, evals and deployment |
| [LangGraph](https://github.com/langchain-ai/langgraph) | 37,567 | Durable stateful orchestration runtime | Checkpointing, interrupts, replay, explicit state/graph control |
| [Hugging Face smolagents](https://github.com/huggingface/smolagents) | 28,425 | Minimal tool-calling and code-agent runtime | Small inspectable loop, code actions, broad tools/models, memory/replay and sandbox choices |
| [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) | 27,994 | Lightweight agent loop with OpenAI-native features | Small API, handoffs, tools, guardrails, sessions, tracing, approvals |
| [Mastra](https://github.com/mastra-ai/mastra) | 26,318 | Full TypeScript agent application stack | Agents, workflows, memory, MCP, storage, evals, observability, deployment |
| [Vercel AI SDK](https://github.com/vercel/ai) | 25,631 | TypeScript model/UI primitives and a thin tool loop | Excellent streaming/UI integration, broad providers, per-step loop control |
| [Google ADK](https://github.com/google/adk-python) | 20,658 | Production agent development across languages | Model adapters, sessions/context, graph workflows, eval and deployment tooling |
| [Pydantic AI](https://github.com/pydantic/pydantic-ai) | 18,636 | Type-safe Python agents and workflows | Typed dependencies/output, validation/retries, broad providers, evals and durable integrations |

Two qualifications matter:

- LlamaIndex's popularity substantially predates its current agent workflow APIs and
  reflects its data/RAG ecosystem too.
- Framework repository stars reward breadth. A small embeddable runtime should not
  use feature count as its success metric.
- Popularity alone misses strategically important platform SDKs. Microsoft Agent
  Framework, Claude Agent SDK and AWS Strands are covered below even though their
  current repositories are under the table's threshold.

This is comprehensive for that declared cohort, not a claim to cover every project
calling itself an agent framework. The cutoff is reproducible; the additional
first-party SDKs cover the major platform direction that stars miss. A lower-adoption
framework should be added only when it contributes a distinct capability or ecosystem
lesson, not to inflate the checklist.

---

## Framework-by-framework comparison

### LangGraph: durability is the product

LangGraph treats an agent as state plus nodes plus edges. Its differentiator is not
tool calling; it is the checkpointer. State is saved at execution boundaries, a run
can interrupt indefinitely, completed parallel writes can survive another node's
failure, and historical checkpoints enable replay and inspection. Its functional API
also makes the hard rule explicit: non-determinism and side effects belong inside
checkpointed tasks, and those tasks should be idempotent because a crash can cause
re-execution. See the official [overview](https://docs.langchain.com/oss/python/langgraph/overview),
[persistence model](https://docs.langchain.com/oss/python/langgraph/persistence), and
[functional API guidance](https://docs.langchain.com/oss/python/langgraph/functional-api).

**Compared with Work Agent:** Work Agent has durable conversation intent but no
specified commit protocol for a run interrupted during a model stream or tool side
effect. A persisted transcript is not yet durable execution. LangGraph's lesson is to
define safe resume boundaries and idempotency now; its graph DSL is not needed now.

### AutoGen: composition and termination are first-class

AutoGen offers a high-level AgentChat API and a lower-level event-driven Core.
AgentChat supports single agents, round-robin and selector teams, swarms/handoffs,
directed graph flows, state save/load, streaming, cancellation, and a broad family of
composable termination conditions. Its own guidance is notably conservative: start
with one agent and add a team only after a well-instructed, well-tooled single agent
proves inadequate. See [AutoGen's architecture](https://microsoft.github.io/autogen/stable/index.html),
[teams guidance](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html),
and [termination conditions](https://microsoft.github.io/autogen/dev/user-guide/agentchat-user-guide/tutorial/termination.html).

**Compared with Work Agent:** the proposed loop has only normal completion,
cancellation, provider failure, and max turns. AutoGen demonstrates why stopping is a
policy surface: token, time, external, handoff, specific-tool, and custom conditions
need not be hard-coded into the state machine. Its multi-agent machinery should stay
deferred for Work Agent.

### CrewAI: approachable opinionated composition

CrewAI makes roles, tasks, crews, and processes easy to name and assemble, while its
Flows API provides deterministic start/listen/router steps, state persistence, resume,
and human triggers. Its adoption advantage is approachability and a coherent vertical
stack: project scaffolding, tools, memory, structured outputs, guardrails, callbacks,
observability, triggers, and managed deployment are presented as one developer journey.
See the [CrewAI documentation overview](https://docs.crewai.com/).

**Compared with Work Agent:** CrewAI's role metaphors and cloud deployment are a poor
fit for a calm single-user Mac app, but the progressive path—one simple abstraction
first, explicit flows when predictability matters—is useful. Work Agent should not make
the model improvise a workflow that the application already knows deterministically.

### LlamaIndex: win a domain, not just a loop

LlamaIndex differentiates through data: retrieval, document processing, indexes,
memory, and a large integration ecosystem. Its agent layer includes native function-
calling agents, ReAct for models without native tool use, structured outputs, agents
as tools, MCP, shared workflow context, and streamed events. See its
[structured-output agent guide](https://docs.llamaindex.ai/en/latest/understanding/agent/structured_output/),
[agents-as-tools example](https://docs.llamaindex.ai/en/latest/examples/agent/agents_as_tools/),
and [MCP integration](https://docs.llamaindex.ai/en/stable/module_guides/mcp/).

**Compared with Work Agent:** it reinforces a strategic point: frameworks become
valuable by owning a developer problem beyond the generic loop. Work Agent's analogous
domain is native, user-controlled work on Apple platforms—not RAG. It should not absorb
LlamaIndex's data stack unless a real product task requires it.

### Agno: the framework is becoming an agent platform

Agno's current proposition is broader than an in-process loop. Its SDK exposes
agents, teams and workflows; sessions, memory, knowledge, human-in-the-loop,
guardrails, tracing and evals feed an AgentOS control plane that can also host agents
built with other frameworks. See the official [SDK introduction](https://docs.agno.com/sdk/introduction)
and [agent overview](https://docs.agno.com/agents/overview).

**Compared with Work Agent:** Agno demonstrates the commercial pull toward one
integrated prototype-to-production platform. That is useful evidence for explicit
storage, inspection and evaluation contracts, but its fleet/server control plane is
the opposite of Work Agent's local native product boundary. Interoperability with an
external runtime is more relevant than copying AgentOS.

### smolagents: simplicity and executable actions are the thesis

Hugging Face smolagents deliberately keeps its core loop small and offers both JSON
tool-calling agents and code agents. Around that core it provides step memory and
replay, planning, managed agents, telemetry, MCP/tool adapters, human interaction and
several code-execution isolation choices. Its security guidance is unusually direct:
local model-written code is inherently risky and only a real isolation boundary can
contain the full class of failures. See the [framework overview](https://huggingface.co/docs/smolagents/main/index),
[agent reference](https://huggingface.co/docs/smolagents/main/reference/agents) and
[secure execution guidance](https://huggingface.co/docs/smolagents/main/tutorials/secure_code_execution).

**Compared with Work Agent:** smolagents validates a small, understandable loop and
shows why a framework needs a sharp execution thesis. Work Agent should preserve
ordinary typed tool calls for safe host integration; if it later supports model-written
Swift or shell code, that must be an explicitly sandboxed tool capability rather than
an alternate invisible loop.

### OpenAI Agents SDK: a small loop surrounded by production hooks

The OpenAI Agents SDK's documented loop is almost identical to Work Agent's proposal:
call the model; finish on final output; otherwise hand off or execute tools and repeat;
stop at a turn limit. The value around it is typed agents and outputs, tools and agents-
as-tools, guardrails, resumable approvals, sessions, lifecycle hooks, usage accounting,
tool-concurrency controls, and built-in traces. Durable execution is delegated to
integrations such as Temporal, Restate, Dapr, and DBOS. See
[running agents](https://openai.github.io/openai-agents-python/running_agents/),
[tools](https://openai.github.io/openai-agents-python/tools/), and
[tracing](https://openai.github.io/openai-agents-python/tracing/).

**Compared with Work Agent:** this validates the proposed loop's size and event shape.
It also shows that malformed arguments, unknown tools, tool timeouts, tool approvals,
and model-visible tool errors need explicit contracts. Work Agent has friendly provider
errors, but the proposal does not yet say which tool failures end a run and which go
back to the model for correction.

### Mastra: the integrated TypeScript production stack

Mastra combines model routing, typed tools, MCP, agents, explicit workflows, suspend/
resume, storage, memory, evals, traces, a local visual studio, and deployment. Workflows
support sequential, parallel, branch, loop, nested steps, persisted state, and error
handling. Its strength is coherence for a TypeScript team that otherwise must assemble
many packages. See [agents and tools](https://mastra.ai/docs/agents/mcp-guide),
[workflow orchestration](https://mastra.ai/ai-workflows), and
[observability/evaluation](https://mastra.ai/ai-agent-observability).

**Compared with Work Agent:** Mastra illustrates what adopting a foreign framework
would buy, and therefore what a custom runtime must deliberately own or decline. The
costs identified in ADR-0006—bundled runtime, signing surface, IPC around Swift tools,
and loss of provider-fidelity control—remain real. Matching Mastra's feature list is
not a sensible objective for the native module.

### Vercel AI SDK: per-step control and UI fit

Vercel's `ToolLoopAgent` is a deliberately thin loop. It defaults to a step limit,
supports composable `stopWhen` conditions, dynamically changes messages/model/tools
with `prepareStep`, restricts each step's active tools, can repair malformed tool calls,
supports approval pauses, and plugs directly into typed streaming UI primitives. See
[`ToolLoopAgent`](https://ai-sdk.dev/docs/reference/ai-sdk-core/tool-loop-agent) and
[loop control](https://ai-sdk.dev/docs/agents/loop-control).

**Compared with Work Agent:** this is the closest philosophical peer. Work Agent's
per-turn registry matches `activeTools`/`prepareStep`, and Swift `AsyncStream` is a
natural equivalent to the UI stream. Vercel's composable stop policy and tool-call
repair are worth copying; its server/web assumptions are not.

### Google ADK: a multi-language production ladder

ADK provides a basic agent/tool API, context and sessions, graph workflows, multi-agent
orchestration, evaluation, a development UI/CLI, model adapters, integrations, and
deployment paths in Python, TypeScript, Go, Java, and Kotlin. Google emphasizes
structured context management: filtering irrelevant events, summarizing old turns,
lazy-loading artifacts, and tracking tokens rather than concatenating indefinitely.
See the [ADK overview](https://adk.dev/).

**Compared with Work Agent:** the missing lesson is whole-context assembly. The tool
plan defends the window against one large tool response, but the loop plan has no
context budget, compaction, artifact reference, or provider cache policy for a long
task.

### Pydantic AI: native language idioms and validation

Pydantic AI's developer proposition is “agents the Pydantic way”: agents are generic
over dependency and output types, Python signatures generate tool schemas, validation
can drive model self-correction, tools compose into toolsets, and developers can use a
simple run or iterate the underlying typed graph node by node. It supports model-
specific settings without contaminating the neutral agent type, broad providers,
usage/concurrency limits, eval datasets, observability, MCP, and external durable-
execution integrations. See [agents](https://pydantic.dev/docs/ai/core-concepts/agent/)
and [function tools](https://pydantic.dev/docs/ai/tools-toolsets/tools/).

**Compared with Work Agent:** this is the best model for Swift ergonomics: lean into
the host language. `Sendable`, actors, enums, generics, result builders where they
clarify composition, macros for schema derivation only if they pay for themselves, and
compiler-enforced isolation should replace Python-style runtime conventions rather
than imitate them.

### Current platform SDKs below the popularity cutoff

Three lower-star projects matter because they are first-party platform direction, not
because their repository counts are large:

- **Microsoft Agent Framework** is the production successor to AutoGen and Semantic
  Kernel. It combines agents, tools, skills, context providers and three middleware
  layers with A2A interoperability, explicit workflows, human input, superstep
  checkpoints and an optional durable-execution extension. Its own journey recommends
  workflows only when a simpler model-directed agent cannot guarantee the required
  order. See [the workflow journey](https://learn.microsoft.com/en-us/agent-framework/journey/workflows),
  [middleware](https://learn.microsoft.com/en-us/agent-framework/agents/middleware/)
  and [checkpoints](https://learn.microsoft.com/en-us/agent-framework/workflows/checkpoints).
- **Claude Agent SDK** packages Anthropic's coding-agent harness: sessions/resume,
  built-in computer tools, MCP, subagents, permissions and lifecycle hooks that can
  allow, deny or rewrite tool activity. See the official [overview](https://code.claude.com/docs/en/agent-sdk/overview)
  and [hooks](https://code.claude.com/docs/en/agent-sdk/hooks). Its lesson is the value
  of a cohesive work harness, but it is intentionally Claude-centered rather than a
  neutral embeddable runtime.
- **AWS Strands Agents** provides a customizable model-driven loop, multiple model
  providers, tools/MCP, multi-agent patterns, hooks and OpenTelemetry-oriented
  observability across Python and TypeScript. See the [SDK repository](https://github.com/strands-agents/harness-sdk)
  and [API documentation](https://strandsagents.com/docs/api/python/). Its strongest
  lesson is pluggable lifecycle interception without forcing a graph abstraction.

Microsoft's consolidation also changes how the historical AutoGen row should be read:
AutoGen remains highly popular and instructive, but new Microsoft framework adoption
should be evaluated against Agent Framework rather than assuming AutoGen is the
long-term standalone API.

---

## Direct assessment of Work Agent's proposed loop

| Concern | Proposal | Framework norm | Assessment / recommendation |
|---|---|---|---|
| Neutral conversation | Typed blocks plus opaque provider extras | Typed messages, usually normalized | **Strong and differentiating.** Preserve native provider state without letting it leak into loop logic. |
| Provider translation | Adapter owns request, stream deltas, tool results | Provider adapters or a normalization gateway | **Strong.** Add adapter conformance fixtures for every block and stop reason. |
| Basic loop | Actor; stream → tools → repeat | Same in every thin SDK | **Sound.** Keep it small and inspectable. |
| Tool execution | Every call in a turn runs in parallel; results “ordered by call id” | Configurable concurrency; stable call-order correlation | **Change before build.** Preserve provider call order, not lexical/arbitrary ID order. Add per-tool concurrency/exclusivity policy; two writes to one file must not race. |
| Cancellation | Structured cancellation of stream and tools | Standard best practice | **Strong.** Define what durable state remains after cancellation and whether partial tool work is recoverable. |
| Retries | Three retries for 429/5xx/timeouts | Error-class-specific backoff plus budgets | **Incomplete.** Never blindly retry uncertain side effects. Buffer each model attempt so retrying a broken stream cannot duplicate committed deltas or calls. Honor provider retry hints. |
| Termination | Text finish, cancellation, max 50, unrecoverable error | Composable turn/token/cost/time/tool/external conditions | **Too narrow.** Introduce `RunPolicy` rather than embedding one max-turn integer. Fifty should be a product-tuned pause threshold, not a framework truth. |
| Persistence | Durable task/conversation/status/trace; mechanism open | Checkpoints at explicit execution boundaries | **Not yet durable execution.** Specify checkpoints before and after model steps, interrupts, and tool batches; record in-flight attempt identity. |
| Human input | `ask_user` suspends through a continuation | Serializable interrupt with arbitrary reason/payload | **Good UX, weak primitive.** Implement a general durable `AgentInterrupt`; make `ask_user` and future approvals projections of it. A continuation alone does not survive process death. |
| Tool schema | Minimal JSON Schema type; MCP schemas passed through | Canonical schema subset plus provider transforms | **Good seam.** Version tools, validate names/schema per adapter, preserve raw MCP schema, and make unsupported keywords visible in contract tests. |
| Tool effects | One enum: read, workspace write, consequential, or network | Several orthogonal annotations/policy dimensions | **Change the shape.** Network, write, destructiveness, idempotency, and approval are not mutually exclusive. Use a `ToolAnnotations` struct/option set plus host policy. |
| Tool failures | `ToolOutput.isError` | Validation errors and recoverable failures returned to model; fatal host failures stop | **Underspecified.** Define invalid arguments, unavailable tool, timeout, cancellation, denied approval, and internal failure separately. Give recoverable errors a corrective message. |
| Output budgeting | Full trace, paged/middle/spill model view | Context processors, truncation, artifacts | **Strong locally, incomplete globally.** Keep it and add a whole-context assembler with a token budget. |
| Dynamic tools | Registry rebuilt per turn; hosted tools stay in adapter | Common high-value pattern | **Strong.** Log the exact tool-spec snapshot used for each model request so replays are meaningful. |
| Tracing | One raw event sink before display/truncation | Structured spans, usage, latency, redaction, export | **Strong foundation.** Add stable run/turn/attempt/tool IDs, token/cost/cache/latency fields, and keep local canonical trace separate from opt-in telemetry. |
| Evaluation | Unit fixtures, fake provider, live smoke | Recorded datasets, trajectory/tool assertions, replay, online scoring | **Good start, missing product evals.** Add deterministic trace replay and cross-provider task cases before extracting a framework. |
| Context management | Not specified beyond tool output | Compaction, summaries, artifacts, relevant-history selection | **Largest long-run gap.** Make context assembly its own injected component rather than logic inside the loop. |
| Structured final output | Not specified | First-class typed output in most frameworks | **Useful framework objective, not necessarily increment 4.** Leave an output-decoder/validator seam. |
| Graphs and multi-agent | Explicitly deferred | Available in broad frameworks | **Correct.** Do not add them until a real task proves a single loop insufficient. |

### Two correctness traps to resolve explicitly

1. **Streaming attempt atomicity.** The UI may show deltas immediately, but the
   conversation state used for the next model request should commit one completed
   model attempt. If a stream fails and retries after text or partial tool JSON has
   arrived, the runtime needs attempt IDs and a discard/restart policy; appending the
   retry to the same assistant message can duplicate content or execute a call twice.
2. **Side-effect ambiguity.** A process can die after a tool changed the world but
   before its result checkpoint commits. “Resume” cannot prove whether it is safe to
   call the tool again. Record an invocation ID before execution, classify idempotency,
   use idempotency keys where a service supports them, and pause for reconciliation
   when the outcome is unknown.

---

## Capability inventory: Apple, popular frameworks, and the native layer

Foundation Models 27 materially changes the boundary. It already supplies a neutral
model/executor protocol, a session-managed model/tool/model cycle, typed tools and
structured output, a rich `Transcript`, provider metadata and reasoning signatures,
usage and token APIs, dynamic model/tool/instruction profiles, history transforms,
lifecycle hooks, Instruments support, and an Evaluations API. Rebuilding those types
under different names would make a Swift framework worse, not more complete.

The additional surface that developers value in established frameworks is mostly the
runtime around that intelligence session:

| Capability | Foundation Models 27 | Common framework layer | Native Work Agent layer |
|---|---|---|---|
| Model/tool/model cycle | `LanguageModelSession` | Agent runner | Use Apple: scripted and three-provider live cycles pass; retain an app-owned coordinator. |
| Provider translation | `LanguageModelExecutor` | Provider adapters and middleware | First-party OpenAI-compatible and Anthropic executors, conformance fixtures, routing and failover. |
| Conversation representation | Codable `Transcript`, metadata, custom segments | Normalized messages plus provider extensions | Archive the Apple transcript; do not create a shadow message hierarchy. |
| Typed tools and output | `Tool`, `Generable`, `GenerationSchema` | Tool decorators, validation, output parsers | Wrap tools with host policy, effects, idempotency, resource locks, artifacts and budgets. |
| Dynamic context | Profiles and `historyTransform` | Context processors, summaries, memory | Injected context assembler with exact request snapshots, privacy filtering and artifact paging. |
| Persistence | Codable session transcript | Sessions, stores, graph checkpoints | Append-only run journal, versioned checkpoints, migration and restart-safe resume. |
| Human control | Live async suspension is possible | Interrupts, approvals and guardrails | Serializable interrupts, preview/diff, approval evidence and rejection/correction paths. |
| Reliability | Cancellation propagation, transcript revert/preserve policy, concurrent tools; tool errors terminate | Retry, correction, fallback, circuit breaker, limits | Use transcript reversion for attempt atomicity; add retry policy, model-visible corrective failures, resource limits, indeterminate side-effect recovery, fallback and run policies. |
| Workflow composition | Dynamic profiles, skills and agent patterns | Graphs, flows, handoffs, teams | Ordinary Swift control flow first; optional typed workflow/handoff layer only after real need. |
| Observability | Transcript hooks, usage, Instruments; response snapshots may coalesce executor events | Spans, studios, telemetry exporters | Capture lossless events at the executor/host boundary, then emit structured local run events and a user-legible trace; keep optional telemetry export separate. |
| Evaluation | Foundation Models Evaluations | Datasets, trajectory assertions, replay | Cross-provider fixtures, scripted executors, fault injection, safety/effect assertions and native performance metrics. |
| Integrations | Apple/system tools and provider packages | MCP, toolkits, plugins, RAG connectors | MCP/toolset/skill adapters and native macOS capabilities, with no required cloud control plane. |
| Security | Framework guardrails and confirmation patterns | Auth scopes, policy middleware, sandboxes | Secret/data-egress policy, provenance, indirect-prompt-injection boundaries, least privilege and host-owned authorization. |

This division is also the feature-completeness strategy: complement Apple at durable
execution, policy, integration, inspection and testing seams; contribute fixes or
utilities at Apple's abstraction level; and avoid a second competing session API.

### Durable execution should have one source of truth

Use an append-only `RunEvent` journal as execution truth and the archived Apple
`Transcript` as the model-context projection. Record boundaries such as request
planned, attempt started/committed, tool invocation registered/started/completed/
failed/unknown, interrupt raised/resumed, and checkpoint committed. That distinction
prevents a conversation transcript from pretending to answer the distributed-systems
question “did this consequential side effect happen before the crash?”

### The developer experience should be recognizably Swift

- Public definitions are immutable `Sendable` values; mutable run coordination is
  actor-isolated. Strict Swift 6 concurrency is the default, and `@unchecked Sendable`
  is quarantined at audited adapter boundaries.
- Use `async`/`await`, cooperative cancellation, `AsyncSequence`, `Clock` and
  `Duration`. Do not expose callbacks, promise wrappers, thread knobs or stringly typed
  timeouts.
- Preserve Foundation Models types in public seams. Add adapters, modifiers and policy
  wrappers instead of `AgentTranscript`, `AgentTool` and `AgentSchema` lookalikes.
- Prefer generic, statically typed APIs at the public boundary and type erasure inside
  storage, registries or heterogeneous UI collections. Outputs and tool arguments stay
  compile-time typed.
- Model lifecycle and failure states with exhaustive enums and typed errors. Separate
  corrective model feedback, a durable interrupt, fatal host failure and an
  indeterminate side-effect outcome. Vendor-facing unknown cases fail safely.
- Dependencies are explicit values passed to a run. Avoid global registries and
  singletons; reserve task-local values for trace correlation rather than business
  state. Inject clocks and ID generators for deterministic tests.
- Use result builders only for static declarative composition such as a tool set.
  Dynamic workflows use normal Swift control flow. Macros may remove schema boilerplate
  but must not hide execution, retries or side effects.
- Keep the engine independent of SwiftUI. A small Observation/SwiftUI projection can
  turn run events into UI state without importing UI frameworks into the runtime.
- Follow the Swift API Design Guidelines: clarity at the call site, fluent names,
  meaningful argument labels, documented public declarations and progressive defaults.
  Design the usage examples before freezing protocols.
- Use native value types (`URL`, `Data`, `UUID`, `Duration`) instead of strings and ship
  DocC, runnable examples, scripted models, virtual clocks and fixture helpers as part
  of the framework experience.

An indicative surface—not an accepted API—would keep setup small while leaving the
runtime visible:

```swift
let agent = Agent(
    model: model,
    instructions: "Prepare the report from the selected files.",
    tools: ToolSet { ReadFile(); WriteReport() },
    output: Report.self
)

let run = try await runtime.start(agent, input: request, dependencies: services)
for try await event in run.events {
    await presenter.consume(event)
}
let report = try await run.value
```

The advanced path should expose the same typed request snapshot, checkpoint,
interrupt, attempt and tool-invocation events that the simple call uses. Progressive
disclosure must not be implemented as a second, less observable runtime.

---

## Best practices that converge across frameworks

### 1. Start with one agent and explicit tools

Multi-agent systems multiply prompts, context, latency, cost, failure paths, and
debugging work. A specialist agent is justified when it needs a genuinely distinct
context, model, security boundary, or reusable capability—not merely a different role
name. AutoGen's own documentation recommends optimizing the single agent first.

### 2. Use deterministic code for known workflows

Let the model decide where judgment is valuable: interpreting intent, choosing among
tools, handling novel content. Use normal Swift control flow for required sequences,
invariants, approval gates, and business rules. If a future task is always “read,
classify, ask approval, then write,” encode those stages rather than hoping the prompt
recreates them.

### 3. Make state and boundaries explicit

Separate the conversation transcript, run state, host dependencies, tool registry,
provider-native extras, and durable checkpoints. Checkpoint at meaningful boundaries.
Version serialized state and tool definitions so an app upgrade can resume or
explicitly decline old work safely.

### 4. Treat every side effect as a distributed-systems problem

Retries, cancellation, crashes, and user interrupts create at-least-once execution
unless proven otherwise. Tools should declare idempotency and resource/exclusivity
keys. The runtime should never claim exactly-once semantics it cannot provide.

### 5. Make failures useful to both developer and model

Distinguish provider failure, invalid model behavior, invalid tool arguments, policy
denial, user rejection, timeout, cancellation, unavailable dependency, and internal
bug. Some stop the run; some pause it; some return structured corrective feedback to
the model. Preserve the raw developer diagnostic while showing users plain language.

### 6. Budget the run, not just each output

Enforce turn, request, token, cost, time, and tool-call limits. Build the next request
through one context-assembly component that can measure, compact, page, or replace
large values with artifact references. Always make truncation and recovery visible to
the model.

### 7. Observe a typed trajectory

A useful trace is not a text log. It relates run → turn → model attempt → content
blocks → tool invocation → result → checkpoint/interrupt, with timings, usage, model,
provider, tool-version, errors, and policy decisions. Sensitive local trace data and
exported telemetry need separate policies.

### 8. Evaluate outcomes and trajectories

Unit-test tools and adapters deterministically. Then keep task cases that assert more
than the final prose: correct tool selection, valid arguments, safe ordering, bounded
steps/cost, expected artifacts, and no forbidden effects. Run the same cases across
providers to measure neutrality rather than assume it.

### 9. Design extension seams, not speculative features

Lifecycle middleware, storage, context assembly, stop policy, trace sink, tool policy,
and provider adapters are high-leverage seams. Graph builders, subagents, long-term
memory, RAG, and deployment control planes are features to add only after concrete
need.

---

## Why the popular frameworks succeed

These are inferences from their convergent design and adoption, not experimentally
proven causes.

1. **They remove the production work around the loop.** Persistence, retries,
   interrupts, state, traces, evals, and deployment save more engineering than the
   loop itself.
2. **They fit their host ecosystem.** Pydantic AI uses Python typing and validation;
   Vercel and Mastra use TypeScript, Zod, web streams, and frontend integration;
   LlamaIndex owns Python data/RAG workflows.
3. **They offer progressive disclosure.** A hello-world agent is tiny, but there is a
   path to custom state machines, graphs, teams, or durable workflows without an
   immediate rewrite.
4. **They have broad integration gravity.** Provider adapters, tool libraries, MCP,
   memory/storage backends, telemetry exporters, and examples reduce adoption risk.
5. **They make opaque behavior inspectable.** Event streams, local studios, traces,
   and eval tools shorten the developer feedback loop.
6. **They provide escape hatches.** Developers can control model settings, messages,
   tools, state, stop conditions, and lifecycle without forking the runtime.
7. **They teach patterns, not only APIs.** Good documentation covers idempotency,
   interruption, context pressure, termination, and when *not* to use multiple agents.
8. **They own a sharp reason to exist.** LangGraph is durable orchestration;
   LlamaIndex is agents over data; Pydantic AI is type-safe Python; Vercel AI SDK is
   provider-neutral streaming AI for TypeScript apps. “It calls tools in a loop” is
   not enough.

---

## What could justify a native Swift agent framework

Apple changed the baseline in 2026. Foundation Models now has a provider-extensible
[`LanguageModel` protocol](https://developer.apple.com/documentation/Updates/FoundationModels),
a typed [`Transcript`](https://developer.apple.com/documentation/foundationmodels/transcript)
with reasoning/tool calls/tool output, and a `LanguageModelExecutor` seam for provider
packages. Apple's provider guidance explicitly describes capability declaration,
native-to-provider transcript translation, streaming, custom segments, and server-side
tools; see [“Bring an LLM provider to the Foundation Models framework”](https://developer.apple.com/videos/play/wwdc2026/339/).

Therefore **native Swift plus a typed transcript plus tool calling is no longer a
sufficient raison d'être**. Apple owns that generic platform story for OS 27 and later.
A separate framework is justified only if it is meaningfully better for the jobs Apple
does not appear to target:

1. **Durable, long-running, user-controlled work.** Crash-safe checkpoints,
   interruptions lasting across app restarts, idempotency, task migration, recovery,
   and legible partial completion.
2. **Full-fidelity provider neutrality on the app's schedule.** First-party HTTP
   adapters, opaque provider state, provider failover, hosted-tool differences, and
   support for deployment targets or vendors not covered by Foundation Models packages.
3. **Native Mac capability integration.** Swift concurrency and cancellation,
   SwiftUI/Observation bridges, Keychain, AppKit, NSFileCoordinator, XPC, Accessibility,
   Apple Events, security-scoped resources when relevant, and hardened-runtime signing
   without embedding Node or Python.
4. **Local-first trust and recovery.** On-device traces and state, host-controlled
   permissions, previews/diffs, undo evidence, approval interrupts, and no required
   cloud control plane.
5. **Swift-native correctness and ergonomics.** `Sendable` protocols, actors,
   `AsyncSequence` event streams, typed errors and outputs, schema derivation, strict
   concurrency checking, and test doubles that feel like Swift rather than a port of a
   Python framework.
6. **Provider-neutral evaluation for native apps.** Recorded stream fixtures, trace
   replay, cross-provider contract suites, scenario datasets, performance/energy
   metrics, and UI-friendly run inspection.

The concrete adaptation options, local Xcode 27 API evidence, and recommended hybrid
are analyzed separately in
[foundation-models-adaptation.md](foundation-models-adaptation.md).

The market is currently thin. On 2026-07-18, the official
[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) had 1,445 stars,
while the specific Swift agent SDK considered in ADR-0006,
[`open-agent-sdk-swift`](https://github.com/terryso/open-agent-sdk-swift), had 26.
That is both an opportunity and a warning: there is room for a good native runtime,
but not yet evidence of a large framework market independent of Apple.

### Recommended objectives for the native Swift runtime package

The accepted middle-layer SPM package should aim to:

- make the simple case one `Agent.run` call while exposing every event and state
  transition for advanced hosts;
- preserve provider-native capability and metadata without exposing vendor types in
  core orchestration;
- define crash-safe run/checkpoint/interrupt semantics before adding graph syntax;
- make tools typed, versioned, dynamically assembled, policy-neutral in the core, and
  richly annotated for the host;
- make concurrency safe by default through declared resource and idempotency policy;
- ship conformance tests and deterministic fake providers as first-class API;
- separate canonical local trace storage from optional OpenTelemetry-style export;
- build on Apple Foundation Models types and session substrate where the conformance
  harness proves them, while keeping the durable runtime independently testable;
- keep UI, provider catalog curation, credentials, built-in tool policy, and app task
  storage outside the package; and
- remain useful without MCP, a cloud account, a deployment server, or a graph DSL.

### Recommended non-objectives

- Do not become “LangChain for Swift” by matching a checklist.
- Do not provide a cloud deployment platform.
- Do not make multi-agent teams the primary abstraction.
- Do not bundle a provider catalog, RAG stack, vector database, or generic memory by
  default.
- Do not flatten provider-exclusive capabilities for the appearance of neutrality.
- Do not split the accepted runtime into additional packages until a measured build,
  testability or reuse problem proves another boundary.

---

## Practical recommendation for Work Agent

Keep ADR-0006's native direction. Before the code increment DOR, revise the proposal
around six implementation-level decisions:

1. `RunPolicy`: composable turn, token, cost, time, tool-call, repeated-call, and
   external stop conditions; limits pause visibly where recovery is possible.
2. `CheckpointStore` and `AgentInterrupt`: explicit pre/post boundaries and serializable
   resume state; `ask_user` becomes one interrupt presentation.
3. `ToolExecutionPolicy`: original-call-order correlation, concurrency caps, resource
   keys, idempotency, and exclusivity; no unconditional parallel writes.
4. `ToolAnnotations` and error taxonomy: replace the mutually exclusive effect enum;
   specify which errors are corrective, interrupting, fatal, or indeterminate.
5. `ContextAssembler`: own the entire next-request budget and record the exact message/
   tool snapshot sent to the provider.
6. Structured trace/eval contracts: stable IDs and attempt atomicity, usage/latency,
   recorded stream replay, tool-trajectory assertions, and cross-provider cases.

Then ship the single-agent loop and two low-risk tools. Do not add graphs, crews,
subagents, or long-term memory. The native module's first success criterion is not
framework breadth; it is that one durable task can be understood, stopped, resumed,
replayed, and run across providers without ambiguous side effects.
