# Plan: the three-layer agent runtime

**Status: proposal, revised 2026-07-18.** This is the build plan for ROADMAP increment
4 and the runtime half of increment 5. It implements the accepted three-layer decision
in [ADR-0006](../decisions/0006-native-swift-agent-loop.md) and the single justified
package boundary in [ADR-0002](../decisions/0002-monolith-until-seams-are-known.md).

The older untracked draft proposed a custom `AgentMessage`, provider extras bag,
`ToolCapableProvider` and basic turn loop. The macOS 27 POC proved that Apple now owns
those intelligence-session abstractions. This revision deletes that duplication and
moves Work Agent's design one layer up to durable work.

No new task behavior is invented here. Existing constraints are FR-001, FR-006,
FR-060, FR-063–066, NFR-001, NFR-002, NFR-006, NFR-009 and NFR-010. The increment-4
DOR must create any task-specific requirements from Toni's answers to the open
questions below.

---

## 1. Target outcome

The system has exactly three architectural layers:

```text
Work Agent app
  SwiftUI / Observation
  task presentation and app persistence
  curated model catalog, Keychain and credentials
  built-in Mac tools and product authorization policy
             │ imports and injects dependencies into
             ▼
Native Swift agent-runtime SPM package (iOS 27 + macOS 27)
  TaskCoordinator and RunPolicy
  RunJournal / checkpoints / interrupts
  TranscriptArchive and context assembly
  host Tool contract / ToolRunner / Foundation Models bridge
  OpenAI-compatible and Anthropic executors
  trace events, replay, fixtures and eval support
             │ imports and extends
             ▼
iOS/macOS 27 Foundation Models
  LanguageModel / LanguageModelExecutor
  LanguageModelSession / Transcript
  Tool / Generable / GenerationSchema
  profiles, usage, Evaluations and Instruments hooks
```

Dependencies point downward only. The app can know the package; the package cannot
know the app. The package can know Foundation Models; it does not wrap Apple's public
types in parallel lookalikes.

The package's product name is open. `AgentKit` is a working label used in older docs,
not an accepted name. Choose the package and module name at increment 4's DOR because
that name becomes public API and repository structure.

## 2. Package boundary

Create one local SPM package with iOS 27 and macOS 27 deployment targets. Its public
surface is platform-neutral, UI-independent and strict-concurrency clean. The Work
Agent application remains macOS-only.

The package owns:

- the durable run state machine and immutable `Sendable` state values;
- actor-isolated mutable coordination;
- run, attempt, interrupt, checkpoint and tool-invocation identity;
- storage protocols for journals, checkpoints and transcript archives — designed
  **suspension-safe from the start**: a checkpoint must be durable at the moment the
  OS freezes or kills the process without warning, because the planned iOS
  reference app (RUNTIME.md §5) lives under exactly that regime and retrofitting
  checkpoint atomicity defeats its purpose;
- retry, fallback, circuit-breaker and composable run-limit policy;
- context assembly and model-facing history projection;
- tool instrumentation and annotations — plain `FoundationModels.Tool`s run through
  generic wrappers, with effects/idempotency as `ToolAnnotations` data
  ([runtime-api.md](runtime-api.md) §3; no second tool protocol);
- provider executors, conformance fixtures, scripted models and fault injection;
- structured local runtime events and optional exporter protocols; and
- cross-provider replay/evaluation helpers.

The package accepts any injected `LanguageModel`. Cloud APIs participate through the
OpenAI-compatible and Anthropic executors or another provider package. On-device
`SystemLanguageModel`, Private Cloud Compute, Core AI, MLX and community models
participate through their Foundation Models conformances. Raw model engines require an
adapter; the runtime does not infer how to invoke an arbitrary model binary.

The app owns:

- SwiftUI/Observation views and projections;
- the concrete task database and migration policy;
- Keychain access and provider credentials;
- the curated provider/model catalog and selection UI;
- user-facing approvals, explanations and recovery choices;
- concrete file, web, native-app and connected-service tools; and
- product policy about which capabilities are available in a run.

The package must not import SwiftUI, AppKit, UIKit, the app target, its
Keychain/catalog types, or a concrete app database. Native Mac helpers can become
separate integrations only when a real consumer proves that boundary; ADR-0002 still
rejects speculative package graphs.

## 3. Preserve Apple's intelligence-session types

Use `Transcript` as the canonical model conversation and `LanguageModelSession` for the
basic model/tool/model cycle. Use `FoundationModels.Tool`, `Generable` and
`GenerationSchema` at model-facing seams. Runtime entry points accept a generic or
type-erased `LanguageModel` supplied by the host; model location is not part of the run
algorithm.

Do not introduce:

- `AgentMessage` or another general message hierarchy;
- `AgentTranscript` or a second conversation archive;
- a provider-neutral schema that silently flattens Apple/MCP semantics;
- a second basic loop that competes with `LanguageModelSession`; or
- framework-specific callback/promise abstractions around Swift concurrency.

Add only the state Apple does not model:

```swift
struct RunID: Hashable, Codable, Sendable { /* stable value */ }
struct AttemptID: Hashable, Codable, Sendable { /* stable value */ }
struct ToolInvocationID: Hashable, Codable, Sendable { /* stable value */ }

enum RunEvent: Codable, Sendable {
    case requestPlanned(/* exact context snapshot identity */)
    case attemptStarted(/* attempt and provider */)
    case attemptCommitted(/* usage and transcript archive */)
    case toolRegistered(/* invocation, effect and idempotency */)
    case toolStarted(/* invocation */)
    case toolCompleted(/* invocation and artifact references */)
    case toolOutcomeUnknown(/* invocation and reconciliation evidence */)
    case interruptRaised(/* serializable interrupt */)
    case interruptResumed(/* decision evidence */)
    case checkpointCommitted(/* durable position */)
}
```

The append-only run journal is execution truth. A versioned `TranscriptArchive` stores
Apple's Codable transcript as the model-context projection. Reconstruction derives a
session from committed run state at explicit boundaries; conversation state never
pretends to answer whether an external side effect happened before a crash.

## 4. Provider executors

Refactor—not copy—the shipped OpenAI-compatible and Anthropic request encoders/SSE
parsers into `LanguageModelExecutor` implementations. Configuration supplies model,
endpoint, authentication material and declared capabilities without importing the app
catalog or Keychain.

Required behavior:

- translate Apple transcript entries, tool definitions and generation options to each
  wire format;
- stream response, reasoning, tool calls, usage, finish state and provider metadata
  into Apple's generation channel;
- retain opaque reasoning/signature state only for its owning provider;
- strip foreign provider state when reconstructing a session for failover (FR-006);
- throw typed errors for HTTP failures and HTTP-200 provider SSE error events;
- never print credentials or raw secret-bearing requests; and
- fail precisely on unsupported transcript/schema features rather than losing them.

The conformance corpus covers both wire formats. DeepSeek, Google and Anthropic remain
the live architecture gates because together they exercise reasoning content, thought
signatures, signed thinking blocks, tool calls and cross-provider reconstruction.

## 5. Durable coordinator

`TaskCoordinator` is an actor above `LanguageModelSession`, not a replacement session.
For each attempt it:

1. reads committed run state and assembles the exact model-context snapshot;
2. records `attemptStarted` before external work;
3. constructs a session/profile for the selected executor, tools and instructions;
4. observes executor and host-tool events at the lossless boundary;
5. uses transcript reversion when an attempt must be discarded;
6. records the resulting archive and `attemptCommitted` atomically; and
7. checkpoints before exposing a resumable durable state.

`RunPolicy` composes turn, token, cost, time, tool-call, repeated-call and external stop
conditions. There is no framework-global “50 turns” truth. Product defaults belong in
the app and recoverable limits pause visibly rather than becoming opaque failures.

Retry policy distinguishes:

- a pre-response transient provider failure, safe to retry;
- a partial streamed attempt, discarded and restarted under a new `AttemptID`;
- a recoverable tool validation failure, returned as model-visible tool output;
- a fatal host or policy failure; and
- an indeterminate consequential side effect, which pauses for reconciliation instead
  of automatically calling the tool again.

## 6. Tool host

Tools are plain `FoundationModels.Tool`s — there is no second tool protocol
([runtime-api.md](runtime-api.md) §3, superseding the older host-contract sketch in
tool-architecture.md §2). Effect, idempotency, resources, output budget, artifacts
and trace behavior are runtime policy carried as `ToolAnnotations` data (policy
table → modifier → optional refinement conformance → MCP hints → conservative
default), not fields Apple should enforce and not requirements on the tool author.

The runtime hands the session `InstrumentedTool<Base>` wrappers, which per call:

1. registers the invocation durably before execution;
2. applies resource-aware scheduling rather than assuming Apple's parallel starts are
   safe for every tool;
3. records full output before budgeting model-visible content;
4. classifies thrown errors into corrective output, fatal failure or unknown outcome;
5. commits the outcome under the stable invocation identity; and
6. returns the bridged output to the Apple session.

Apple currently starts independent tool calls concurrently and commits transcript tool
outputs in provider source order. The host must preserve those semantics while
serializing tools that declare conflicting resources.

## 7. App integration

The app creates a durable task, injects package dependencies and projects `RunEvent`
into Observation state. It never reconstructs runtime truth from UI state.

Increment 4 retains the existing chat as the entry surface until Toni answers whether a
conversation is the task or tasks need a separate list. The integration must make one
real provider request through the SPM package and Apple session, persist the resulting
task and transcript archive, terminate the app, relaunch, and display the recovered
task status and result.

Credentials remain in Keychain and cross the package boundary only as an injected
executor configuration at run time. No package-owned global provider registry or
singleton credential store is allowed.

## 8. Testing and developer experience

The package ships its testing surface as part of the framework experience:

- deterministic scripted executors and tools;
- injectable clocks and ID generators;
- virtual backoff and timeout tests;
- recorded SSE fixtures for both wire formats;
- cancellation and partial-stream fault injection;
- crash/restart tests at every journal/checkpoint boundary;
- indeterminate side-effect and reconciliation scenarios;
- cross-provider transcript reconstruction;
- trajectory/effect assertions and replay; and
- gated live provider/session cycles with non-printing environment-key checks;
- iOS and macOS compile/test jobs for the package core; and
- gated `SystemLanguageModel` execution on an eligible iPhone and Mac, with unavailable
  hardware/settings/assets treated as an explicit skip rather than a pass.

Public APIs use immutable `Sendable` values, actors, `async`/`await`, `AsyncSequence`,
`Clock`, `Duration`, typed errors and exhaustive state enums. Result builders are
reserved for static tool composition; dynamic workflows use normal Swift control flow.
The engine is independent of SwiftUI, with a small app-owned Observation projection.

Design usage examples before freezing protocols. The simple path and advanced path use
the same runtime:

```swift
let run = try await runtime.start(agent, input: request, dependencies: services)
for try await event in run.events {
    await presenter.consume(event)
}
let report = try await run.value
```

## 9. Increment-4 expected deliverable

The increment is complete only when the repository contains and runs:

1. one iOS 27/macOS 27 native Swift agent-runtime SPM package with the boundary above;
2. production OpenAI-compatible and Anthropic Foundation Models executors refactored
   from the existing transports;
3. `TaskCoordinator`, run journal, transcript archive, checkpoint and run-policy core;
4. the minimum tool bridge needed for one complete model/tool/model cycle;
5. Work Agent app integration through package APIs, with no package import of app/UI;
6. restart recovery of a real task and a legible live status projection;
7. the deterministic conformance/fault suite on both package platforms, three gated
   live cloud-provider cycles, and gated Apple on-device cycles on an eligible iPhone
   and Mac;
8. requirement IDs in production code/tests and all living docs updated to reality;
9. DocC plus runnable simple/advanced examples; and
10. a clean cold-provider path: adding a provider changes only its executor/configuration
    and registration, or NFR-001 is corrected honestly.

The POC package is then either deleted after its fixtures/tests migrate or retained only
as a clearly named compatibility lab with no duplicate production implementation. The
increment DOR must choose one; two drifting implementations are not acceptable.

## 10. Open questions for increment 4

1. **Public package/module name.** `AgentKit` is only a working label.
2. **What is a task in the UI?** The existing conversation, a task list beside chat, or
   a task-first main window.
3. **Concrete app persistence.** SwiftData, Codable files, or SQLite/GRDB. The package
   exposes protocols and does not decide this app choice.
4. **Failover v1.** Manual user-selected resume or automatic designated fallback.
5. **Background execution.** Whether v1 work survives window closure remains the
   separate product question in PRODUCT.md.
6. **POC disposition.** Delete after migration or retain as a compatibility lab.
