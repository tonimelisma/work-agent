# ADR-0006 — Foundation Models under a native Swift durable agent runtime

- **Status:** Accepted
- **Date:** 2026-07-18
- **Deciders:** Toni

## Context

Increments 4–6 need more than a model/tool/model loop. Work Agent must preserve task
state across restarts, switch providers without replaying foreign opaque state, control
side effects, expose legible traces and eventually pause for durable user input. The
constraints are model neutrality (FR-001, NFR-001), full provider capability exposure
(FR-060), failover (FR-006), complete traces (FR-063), and a native implementation.

The first version of this ADR chose a custom Swift loop over the two ADR-0007 HTTP/SSE
adapters. Apple's macOS 27 Foundation Models APIs changed the available boundary:
`LanguageModel`, `LanguageModelExecutor`, `LanguageModelSession`, `Transcript`, `Tool`
and `GenerationSchema` now supply a provider-extensible native intelligence session.

The POC tested that combined path rather than trusting the API shape. Twenty offline
tests, a scripted Apple session, live Apple-session tool cycles for DeepSeek, Google and
Anthropic, and a live DeepSeek-to-Anthropic reconstructed-session switch all pass. The
POC also established which semantics remain host responsibilities: retry policy,
attempt atomicity, corrective tool failures, resource-aware tool concurrency, durable
interrupts, execution truth and lossless traces.

Toni then confirmed the product and packaging decision: "we'll have three layers: the
Work Agent app, the Swift agentic framework which will be an SPM, and Apple's new macOS
27 APIs." This also resolves the minimum OS at macOS 27 (NFR-009).

## Decision

Use three layers with one-way dependencies:

1. **Work Agent app.** SwiftUI/Observation presentation, curated models, Keychain and
   credentials, app task storage, user-facing error/approval policy, built-in Mac tool
   implementations and product-specific integrations.
2. **Native Swift agent-runtime SPM package.** Durable task coordination around Apple
   sessions: run journal and checkpoints, serializable interrupts, retry/failover/run
   policy, provider executors, richer host tool contracts, effect and idempotency
   metadata, resource scheduling, context assembly, trace events, replay and eval
   support. The package imports Foundation Models but never the app target or SwiftUI.
3. **macOS 27 Foundation Models.** The model/executor/session vocabulary, canonical
   `Transcript`, model/tool/model cycle, typed tools and generation schemas, dynamic
   profiles, token/usage facilities and platform evaluation/instrumentation hooks.

The two shipped provider transports become `LanguageModelExecutor` implementations for
the OpenAI-compatible and Anthropic wire formats. They remain usable for the eleven
curated providers without waiting for vendor-supplied Swift packages.

The package preserves Foundation Models types at its public intelligence-session seams.
It does **not** introduce shadow `AgentMessage`, `AgentTranscript`, `AgentSchema` or a
second basic tool loop. It adds the durable execution facts Apple does not model: an
append-only run journal, attempt and tool-invocation identity, checkpoints, interrupts,
side-effect outcomes, policy and host-facing events. The archived Apple `Transcript`
is the model-context projection; the run journal is execution truth.

The package's final name is deliberately not decided by this ADR. `AgentKit` in older
research and plans is a working label, not a product requirement or accepted name.

## Considered options

**Three-layer Foundation Models hybrid** *(chosen)* — Reuses Apple's native standard
where the POC proves it works and concentrates Work Agent engineering on durable work.
It preserves provider neutrality because the app owns two executor conformances and
provider switching. Cost: macOS 27 becomes the minimum and beta API changes remain a
near-term maintenance risk.

**Custom Swift conversation model and basic loop** *(superseded)* — Maximum control and
an older deployment target, but duplicates `Transcript`, schemas, session execution,
typed output, usage and future provider packages. The POC removed the technical reason
to pay that cost.

**Foundation Models as the whole runtime** — Least custom code. Rejected because an
in-memory/Codable intelligence session is not crash-safe task execution. It does not
answer whether a consequential tool ran before a crash, persist an approval interrupt,
or provide Work Agent's retry, idempotency and recovery semantics.

**Embedded TS/Python framework** — Mature orchestration, but bundles another runtime in
a notarized app, puts IPC around Swift tools, and gives up the native Foundation Models
ecosystem. Rejected.

**LiteLLM or another normalization proxy** — One wire format, but adds a process or
service and risks flattening provider-exclusive state, contrary to FR-060. Rejected as
the architectural center; a remote adapter can still be added later if a real provider
requires one.

## Consequences

**Good.** Developers get native Swift types and concurrency, future Apple/provider
packages can plug into the same substrate, and Work Agent's code focuses on durable,
observable, side-effect-safe work. The SPM boundary enforces that the reusable runtime
cannot import app UI, credentials or product storage.

**Bad.** Work Agent requires macOS 27. The package must track beta changes, maintain the
two wire executors until provider packages cover the curated set, and make durable
semantics precise enough to deserve a public framework boundary in increment 4.

**Bounded.** Foundation Models response snapshots are presentation conveniences, not a
lossless trace source; executor and host boundaries remain trace truth. Unsupported JSON
Schema features fail precisely rather than being flattened. Provider-native signatures
are retained only for their owner and removed on failover. Apple tool failures are
terminal unless the host deliberately turns a recoverable failure into model-visible
tool output.

## Validation

The decision is backed by the reproducible package in
[`Experiments/FoundationModelsPOC/`](../../Experiments/FoundationModelsPOC/):

- 20 deterministic tests after the PR-review error-event regression;
- strict schema conversion and transcript archival/provider-state filtering;
- measured cancellation, retry, tool-error, concurrency and snapshot behavior;
- three live provider/session tool cycles across both wire formats; and
- one live cross-provider reconstructed-session switch.

The POC remains a conformance harness until increment 4 migrates its proven pieces into
the production SPM package. Exact evidence and remaining non-blocking API coverage are
in [foundation-models-adaptation.md](../research/foundation-models-adaptation.md).
