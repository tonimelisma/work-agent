# Second opinion: Apple's LLM stack, the framework gap, and the SPM bet

**Last verified: 2026-07-18.** Toni asked for an exhaustive second opinion on the
accepted three-layer architecture and its research, explicitly *not* trusting the
existing docs ([foundation-models-adaptation.md](foundation-models-adaptation.md),
[agent-framework-comparison.md](agent-framework-comparison.md), ADR-0006). Method:
primary sources only — the FoundationModels `.swiftinterface` shipped in this
machine's Xcode 27 beta 3 (`27A5218g`), a fresh run of the POC's own test suite,
live checks of the packages and platforms named, and fresh landscape research.
Where this doc disagrees with the earlier docs, it says so explicitly.

---

## 1. Verification: what held, what didn't

**Held (independently confirmed):**

- **Apple's API surface is real and as described.** Read directly from the 3,579-line
  macOS swiftinterface: `LanguageModel`, `LanguageModelExecutor` +
  `GenerationChannel` with typed events (text fragments, reasoning,
  reasoning-signature, tool calls with argument fragments, usage, metadata),
  `LanguageModelSession` with `DynamicProfile` result builders, `historyTransform`,
  `onPrompt`/`onResponse`/`onToolCall` hooks, `SessionProperty`, five `tokenCount`
  APIs (prompt/instructions/tools/schema/transcript entries), `Transcript` with
  reasoning/tool-call/tool-output/structured/attachment/custom segments,
  `Generable`/`GenerationSchema`/`DynamicGenerationSchema`, typed
  `LanguageModelError` cases (context size, rate limit, guardrail, refusal,
  timeout, unsupported-capability), `TranscriptErrorHandlingPolicy`, and
  first-party `SystemLanguageModel` (with LoRA `Adapter` and `Guardrails`) and
  `PrivateCloudComputeLanguageModel` (with quota surface) executors. The new
  surface is `@available(macOS 27)`-gated atop a macOS 26 base.
- **The POC evidence is reproducible.** `swift test --package-path
  Experiments/FoundationModelsPOC` passes 20/20 on this machine, including the
  session-semantics suite (cancellation, revert-and-retry, tool-error
  termination, concurrent tool ordering, snapshot coalescing, cross-provider
  reconstruction). The claims in the adaptation doc are not aspirational.
- **The framework-comparison doc's inventory is sound.** Spot checks of its
  LangGraph/Pydantic/Vercel/OpenAI-SDK characterizations match the projects'
  current documentation; its "durability, interrupts, policy, observability,
  evals are the real product" thesis matches what LangSmith actually sells
  (nested trace replay, datasets/experiments, LLM-as-judge + human annotation
  queues, dashboards/alerts, and in 2026 a deployment layer).

**Did not hold, or needs correction:**

1. **"Anthropic and Google will *soon* ship packages" is stale — they shipped.**
   [`anthropics/ClaudeForFoundationModels`](https://github.com/anthropics/ClaudeForFoundationModels)
   is live: Apache-2.0, v0.1.0, 255 stars, OS 27 betas only, best-effort
   maintenance, *no external contributions*. Its production auth stance matters
   to us: API keys are for development; production is `.proxied` through **your
   own backend** (App Attest planned). Google shipped a Gemini equivalent. This
   *strengthens* the ecosystem bet but *changes* our adapter math — see §4.
2. **"Foundation Models Evaluations" does not exist in the macOS 27 SDK.** The
   framework ships `LanguageModelFeedback` (sentiment + issue on a response) and
   nothing eval-shaped; no evaluations framework is present in the SDK. The
   adaptation and comparison docs cite an Evaluations API as researched; treat
   any such thing as Xcode tooling at best, unverified. The eval gap is *fully*
   ours.
3. **A major landscape omission: Hugging Face
   [`AnyLanguageModel`](https://github.com/huggingface/AnyLanguageModel).**
   907 stars, Apache-2.0, v0.9.0 (July 2026), actively maintained: a **drop-in
   API-compatible reimplementation of the Foundation Models surface on iOS 17+ /
   macOS 14+ / Linux**, with nine backends (Apple FM, Core ML, MLX, llama.cpp,
   Ollama, OpenAI, Anthropic, Gemini, Open Responses) and tool calling on nearly
   all. Two consequences: (a) the FM API shape is becoming the Swift ecosystem's
   lingua franca even off-platform — the strongest possible validation of
   building to it; (b) "adopting FM types forces macOS 27" was never the whole
   truth — an FM-shaped API on macOS 14 existed when we accepted NFR-009. It
   doesn't change my verdict (§4) but it should have been in the decision docs.
   `1amageek/OpenFoundationModels` is a second, smaller reimplementation —
   the shape is being cloned twice over.

## 2. What Apple actually provides (and doesn't)

**Provides, verified:** the neutral model protocol + executor seam; a
session-managed model/tool/model cycle; a rich typed transcript that is the de
facto interchange type; typed tools with schema-derived arguments
(`@Generable`); guided/structured generation; streaming snapshots *and* a
lossless executor channel; reasoning with signatures; token counting; dynamic
per-turn composition (profiles, history transforms, hooks); typed error
taxonomy; guardrails and availability/quota surfaces for its own models;
on-device (`SystemLanguageModel` + LoRA adapters) and PCC models; SwiftUI/AppKit
integration overlays (`_FoundationModels_SwiftUI`/`_AppKit` exist in the SDK).

**Does not provide — the actual gap an app developer hits:**

| Missing | Who fills it today |
|---|---|
| Cloud executors beyond Apple's models | Vendors (Claude/Gemini, v0.1 beta), HF AnyLanguageModel, or hand-rolled — *no OpenAI first-party package found* |
| Durable execution: journal, checkpoints, crash-safe resume, idempotency | Nobody in Swift |
| Restart-surviving interrupts/approvals | Nobody |
| Retry/backoff/failover policy | Nobody (session gives revert-transcript primitives only) |
| Run limits (tokens/cost/time/turns) and cost accounting | Nobody |
| Context compaction/assembly policy | Primitives only (`historyTransform`) |
| MCP client + schema bridging | MCP swift-sdk (client only, 1.4k stars); no FM bridge |
| Tool *library* (files, calendar, mail, web) with budgets/policy | Nobody |
| Observability: persistent traces, replay, LangSmith-class inspection | Instruments (dev-time only) |
| Evals: datasets, trajectory assertions, cross-provider regression | Nobody (no SDK eval API — verified) |
| Credential UX for BYOK apps | Nobody (Anthropic's package actively assumes a proxy backend instead) |

That table **is** the SPM's product definition, and it's the same conclusion the
existing docs reached — now confirmed against a moved ecosystem: the model-access
layer is crowding fast (Apple + two vendors + HF in six weeks), while *nobody* is
building the runtime above it. Racing at the executor layer would be entering the
crowded segment; the durable-runtime layer is empty and structurally hard to
"catch up" into because it's about semantics, not wire formats.

## 3. Where I dissent from the current plans

Four design-level disagreements, none fatal to the accepted architecture:

1. **Loop ownership should be a swappable strategy, not a settled fact.** The
   POC's own semantics tests document four workarounds around
   `LanguageModelSession`'s loop: thrown tool errors terminate the response
   (corrective feedback must be smuggled as successful tool output), snapshots
   coalesce events (lossless observation must tap the executor channel), retry
   is app-assembled from `.revertTranscript`, and the session starts all tool
   calls itself (concurrency limiting happens inside the bridge). Each is
   workable; together they mean the runtime's hardest guarantees sit on Apple
   semantics we don't control, on an API that broke ABI between beta 1 and
   beta 3. The SPM's coordinator should treat "Apple session drives the cycle"
   vs "we drive the cycle over Apple's executor/transcript types" as an internal
   strategy with one public API, and the conformance harness should keep both
   honest. The current plans assume session-driven throughout.
2. **The MCP schema gap deserves a strategy, not a table.** The POC measured
   `GenerationSchema` rejecting `anyOf`/`$ref`/numeric constraints/open maps —
   correct strictness, but real MCP servers use those pervasively, so "reject
   with diagnostics" means much of the MCP ecosystem simply doesn't mount. The
   runtime needs a declared degradation ladder (e.g. validate full JSON Schema
   host-side while presenting the model a widened-but-honest schema; fall back
   to documented free-form JSON arguments for the worst cases) *before* MCP
   support is claimed.
3. **iOS support is currently a compile target, not a capability.** On iOS the
   OS *forces* the durable-runtime problem: apps get suspended mid-task. A
   runtime whose checkpoints/interrupts genuinely survive suspension
   (BGTaskScheduler-aware, push-resumable) would be the single most
   differentiated thing this SPM could offer iPhone developers — and no current
   plan addresses suspension semantics. Either design checkpoints against it
   now or scope the claim to "runs on iOS" honestly.
4. **Beta churn is a process risk, not a footnote.** The symbol-level ABI break
   the POC hit *within one beta cycle* will recur until GA (~September). The
   POC-as-conformance-harness plan is right; it should be pinned to exact
   SDK/OS build pairs and run on every beta, and the SPM should not tag a public
   release before GA.

## 4. The vendor packages change our adapter math, not our need

Anthropic's and Google's packages cover 2 of our 11 curated providers, at v0.1,
OS-27-beta-only, best-effort, closed to contributions — and Anthropic's
production-auth design (proxy backend, not BYOK keys) is philosophically opposed
to our credentials-stay-local product. Our own two executors (OpenAI-compatible
× 9 providers + Anthropic native) remain necessary and justified; the vendor
packages become *conformance references* and, eventually, user-selectable
alternatives where their auth model fits. AnyLanguageModel is the one to watch
as a possible executor-layer dependency — but depending on HF's fidelity
choices for our neutrality promise (FR-060) repeats the LiteLLM mistake at a
higher level. Keep our executors; track both.

## 5. What a great SPM looks like (opinion)

One runtime package, two companions, one reference app — each earning its own
existence:

- **The runtime** (the accepted middle layer): durable `RunJournal` +
  `TranscriptArchive`, checkpoint/interrupt/resume semantics, `RunPolicy`
  (composable stop conditions), tool host with annotations/budgets/idempotency,
  failover, MCP with the §3.2 degradation ladder, executor conformance kit +
  scripted models and virtual clocks as *public* API. Swift-native DX: one
  `Agent`/`run` call for hello-world; every event observable underneath; strict
  Swift 6 concurrency; no SwiftUI import; FM types preserved at the seams.
- **The tool library** (separate package): typed, budgeted, annotated native
  tools — files, EventKit, Contacts, Mail via Apple Events, web fetch — the
  "40 built-in tools" layer nobody ships for Swift. Separate because its release
  cadence and review posture (entitlements, privacy strings) differ from the
  runtime's.
- **The studio** (later, an app): local-first LangSmith — read the journal
  format, render trajectories, replay recorded runs against new models/prompts,
  run eval datasets, diff trajectories across providers. This is also just Work
  Agent's trace UI generalized; build it once, ship it twice.
- **Work Agent** stays the reference implementation and proof that the runtime
  carries a real product (Toni: "Work Agent will be the reference app
  implementation building on top of the SPM which we carve out").

DX principles worth being opinionated about: progressive disclosure with *one*
runtime underneath (no simple-mode/advanced-mode fork); test doubles as
first-class API, not an afterthought (scripted `LanguageModel`s, deterministic
clocks, fixture recorders — this is what makes agent apps *testable*.
**Correction 2026-07-19:** the original claim here — "no framework in any
language does it well" — was too strong: Pydantic AI's `TestModel`/
`FunctionModel` with its `ALLOW_MODEL_REQUESTS` guard is a genuinely good,
documented testing story, and Vercel ships `MockLanguageModelV2`; LangChain has
canned-response fakes. The accurate claim: the *pattern* is table stakes in
mature ecosystems and simply absent on Apple's platform — FM ships no double at
all. What remains uncommon anywhere: semantic-level session recording replayable
across providers, and a conformance kit for third-party model packages);
macros only where they delete real
boilerplate (a `@AgentTool` function-to-tool macro is the one clear win);
errors that carry their recovery action; DocC tutorials that teach durability
patterns (idempotency, interrupts) rather than API syntax — the frameworks that
won in Python/TS won partly by *teaching*.

Other product directions visible from here, unranked: an agent-transcript
SwiftUI component kit (every agent app needs to render reasoning/tool-call
trajectories; nobody ships it); a BYOK credential-onboarding kit (Keychain +
verification + provider registry — increment 2's code, generalized); cross-device
task handoff (Mac runs the agent, iPhone observes/approves via the interrupt
primitive — natural once interrupts are serializable).

## 6. Verdict

The accepted three-layer architecture survives independent verification, and the
six-week ecosystem shift (vendor packages shipped, HF cloning the API surface)
actually sharpens its logic: **the FM API shape is winning; the layer above it
is empty; build there.** The corrections that matter are §1's stale claims
(now fixed in the source docs), and the four dissents in §3 — of which loop
ownership (make it swappable) and MCP degradation (decide the ladder before
claiming MCP) should be settled at the increment-4 DOR, iOS suspension before
any public iOS claim, and beta pinning immediately.
