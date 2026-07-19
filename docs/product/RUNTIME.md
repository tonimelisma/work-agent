# The agent runtime — product north star

**Status:** Living north star, created 2026-07-18 at Toni's direction ("let's do a
comprehensive doc increment so this discussion will be stored as the north star for
the project"). This is the *second product* in this repo: the native Swift
agent-runtime SPM package that [PRODUCT.md](PRODUCT.md)'s app is built on. Toni:
*"Work Agent will be the reference app implementation building on top of the SPM
which we carve out."*

What it must do for increment 4 specifically is in
[plans/agent-loop-implementation.md](../plans/agent-loop-implementation.md); the
developer-facing API shape is in [plans/runtime-api.md](../plans/runtime-api.md);
the evidence is in the research docs linked throughout. This doc is the durable
*why and what* — the two most load-bearing sources are
[research/agent-framework-comparison.md](../research/agent-framework-comparison.md)
and [research/apple-llm-stack-second-opinion.md](../research/apple-llm-stack-second-opinion.md).

---

## 1. The thesis

The Swift LLM stack split into two layers in mid-2026, and they are filling at
opposite speeds:

- **The model layer is commoditizing in weeks.** Apple shipped a neutral
  provider protocol (`LanguageModel`/`LanguageModelExecutor`) in the OS 27
  Foundation Models framework; Anthropic and Google shipped v0.1 provider
  packages; Hugging Face cloned the entire API surface for older OSes
  (`AnyLanguageModel`, nine backends). The FM API shape is winning as the Swift
  ecosystem's lingua franca.
- **The work layer above it is empty.** Durable execution, restart-surviving
  interrupts and approvals, run policy and limits, retries and provider
  failover, context assembly, MCP, tool instrumentation, traces, replay, and
  evals — the capabilities that make Python/TS developers adopt
  LangGraph/LangSmith, Pydantic AI, and the OpenAI Agents SDK — exist nowhere
  in Swift, and Apple ships none of them (verified against the macOS 27 SDK:
  not even an evaluations API).

The runtime is the bet on that empty layer: **Apple supplies intelligence
sessions; we supply durable work.** It is the same "durable value is at the app
layer" conviction as PRODUCT.md §1, applied one level down — and it inherits the
same neutrality spine: any conforming model, no vendor welding, provider-exclusive
capabilities exposed rather than flattened.

Two capabilities are weak *even in Python/TS* and are therefore the sharpest
claims: **side-effect safety** (idempotency classification, indeterminate-outcome
recovery — every framework hand-waves it) and **cross-provider mid-task
failover** (nobody has it; it falls out of our transcript-archive design).

## 2. Who it's for

Swift developers building Mac and iPhone apps with LLM features — the audience
Apple just handed a model protocol and nothing to run serious work on. They are
*not* Work Agent's end users; this product's "user" writes Swift. Work Agent is
its reference implementation and first proof.

## 3. What it is

A native Swift SPM package (iOS 27 + macOS 27) sitting between an app and
Foundation Models:

- **Durable runs**: append-only run journal, versioned transcript archive,
  checkpoints, crash-safe resume; the run — not the process — is the unit of work.
- **Interrupts that survive restart**: questions, approvals, and pauses as
  serializable state, not live continuations.
- **Run policy**: composable limits (turns, tokens, cost, time, tool calls),
  typed retry/backoff, model fallback, cross-provider failover.
- **Tool instrumentation without a second tool type**: any
  `FoundationModels.Tool` gains tracing, budgets, timeouts, and corrective
  error handling by being run through the runtime; effects/idempotency arrive
  as data (annotations), not as a competing protocol.
- **The ToolKit products — native tool implementations** (Toni, 2026-07-18: "one
  of the most valuable parts of this SPM," and "absolutely not in the app"):
  files, web, PIM (Contacts/EventKit/Reminders), and macOS app control, as
  small platform-conditional products depending only on Apple frameworks and
  the tool vocabulary — usable with any model package, runtime optional. The
  structure and DAG: [plans/runtime-api.md](../plans/runtime-api.md) §6.
- **Provider executors as batteries — and as the fidelity path**:
  OpenAI-compatible and Anthropic executors with full provider state (reasoning
  round-trips, thought signatures) *and* the capabilities the FM API doesn't
  model — typed executor options for provider-native features, namespaced
  conversation extensions, and direct clients for non-conversational APIs
  ([plans/runtime-api.md](../plans/runtime-api.md) §4). Plus acceptance of *any*
  injected `LanguageModel`, vendor packages included.
- **A public conformance suite**: scripted-model semantics tests any provider
  package can be certified against — the ecosystem hook.
- **Local-first observability**: full-fidelity traces, deterministic replay,
  eval helpers; test doubles (scripted models, virtual clocks, fixture
  recorders) as first-class public API.
- **MCP**, behind an explicit schema-degradation ladder rather than silent
  flattening.

## 4. What it is not

- Not a model SDK or a second session API — Apple owns the intelligence nouns
  (`LanguageModel`, `Transcript`, `Tool`, `Generable`); we never ship lookalikes.
- Not "LangChain for Swift" — no feature-checklist chasing, no graph DSL until a
  real need, no RAG/vector/memory stack by default.
- Not a cloud product — no control plane, no required account; LangSmith-class
  *hosted* monitoring is explicitly out (a local-first studio is a possible
  later product, see §7).
- Not multi-agent-first — teams/handoffs wait for evidence a single durable
  agent is insufficient.

## 5. Relationship to the apps — canonical reference implementations

Decided 2026-07-18 (Toni: the apps "would be the canonical reference
implementation. Pleasant, high quality apps on their own, but also the reference
implementation that shows how to use the SDK, utilizes all the latest
capabilities… and we would have tools for iOS too"):

- **Same repo, one Xcode workspace.** The runtime is a local SPM package; the
  macOS app (and later the iOS app) are workspace targets referencing it by
  path. Publication structure — restructure with the package at the repo root
  and apps in subfolders, or split the package's repo — is deferred to the
  release gate below, since SwiftPM only demands a root manifest for *remote*
  consumption.
- **Two apps, both real products and both canonical references.** Work Agent
  macOS (PRODUCT.md) and a future iOS sibling. The iOS app is not a port or a
  companion: iOS's mandatory sandbox means its tool set is scoped-file access,
  EventKit, Contacts, Reminders, App Intents, share extensions — the same
  runtime and annotations over platform-conditional tool modules. iOS also
  forces the permissions/consent design on its own schedule, ending the "no
  folders yet" luxury for that app.
- **Plus a minimal `Examples/` folder in the package** — product apps prove the
  runtime at scale, but developer onboarding needs 50-line copy-paste examples
  (a durable-run hello world, an annotated tool, resume-after-kill). Product
  code never carries tutorial duty alone.
- **Sequencing:** the iOS app enters the roadmap only after the runtime exists
  and the macOS app proves it (see ROADMAP's deferred table). Its one
  now-consequence: checkpoints are designed suspension-safe from the start,
  because retrofitting that defeats their purpose.

Work Agent (PRODUCT.md) stays a macOS product for non-developers; the runtime is
the layer it proves. The dependency is one-way — the package never knows the app
— and the boundary is enforced now inside the monolith and extracted per
ADR-0002/ADR-0006. Work Agent keeps its own executors for all eleven curated
providers (consistency, BYOK credentials, failover fidelity) even where vendor
packages exist; vendor packages are conformance references and user-selectable
alternatives, not foundations. Sometimes provider capabilities exceed the FM
protocol — Toni: "for Claude and Gemini their FM API doesn't cover all their
functionality. so sometimes we'll need to go direct to the API" — so the runtime
keeps two escape hatches: provider-native options on executor configuration, and
a separate direct-API surface for non-conversational endpoints (batches, file
stores) that don't belong in a transcript.

## 6. Evidence and falsifiers

Recorded 2026-07-18 so the bet stays honest:

- **Demand is a thesis, not a fact.** No one has asked for "durable agent runs in
  Swift" in those words — the platform is weeks old. The signals that exist:
  developers on Apple's forums hitting runtime-shaped pain (sessions hanging,
  undocumented background-task rules, unreliability), `AnyLanguageModel` at ~900
  stars in weeks proving appetite at the model layer, and no competitor at the
  runtime layer. Honest proof arrives two ways we control: developers asking
  *how* the reference apps do durable runs, and pain reports on the vendor
  packages' issue trackers. Until then the hedge is structural — the runtime
  serves Work Agent first, so the work is not wasted if the developer market
  never materializes.
- **The FM commitment is strategy-justified, and has a falsifier.** For the app
  alone, Foundation Models' case is modest: good types, token counting, and a
  session loop that needed four documented workarounds — a custom loop on our
  own adapters would also have served. FM wins because the *runtime product's*
  market is FM developers and the ecosystem is standardizing on Apple's
  vocabulary. If the SPM bet dies — no demand, or Apple absorbs the runtime
  layer — the app should revisit dropping FM; the swappable loop strategy and
  our own executors are what keep that revisit cheap.

## 7. Open questions

Decided by Toni when they block something, not before:

- **Name.** "AgentKit" is a working label only; the public name is unchosen.
- ~~License and openness~~ — **decided 2026-07-18: MIT** ("create a MIT license
  too, Toni Melisma (c) 2026"); the repo carries [LICENSE](../../LICENSE). Open
  source, which makes the conformance-suite ecosystem play viable.
- **Publication structure.** Same repo and workspace, decided (§5); root-package
  restructure vs repo split happens at the release gate.
- **iOS depth.** Suspension-safe durable runs are the committed *design* target
  (§5); how far the first iOS release goes into BGTaskScheduler/push-resume
  territory is scoped when the iOS app enters the roadmap.
- **The studio.** A local-first trace/replay/eval app (Work Agent's trace UI,
  generalized) is a candidate third product, unscheduled.
- **Release gate.** No public tag before the OS 27 GA — beta ABI churn is real
  (observed once already).
