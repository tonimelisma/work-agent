# AgentKit — Roadmap

**Future only.** What exists is in [PRODUCT.md](PRODUCT.md) and
[ENGINEERING.md](../engineering/ENGINEERING.md); a shipped item is deleted from this
list. Items are in priority order; each has enough words to plan from and traces to
Toni's direction. A planning agent takes items from the top and produces
[plans/](../plans/); nothing is picked from anywhere else. (App-side backlog:
[../app/APP.md](../app/APP.md), leaving with the app.)

**The vision this backlog serves:** the Swift model-access layer is commoditizing —
Apple's protocol, vendor packages, community clones — while the durable work layer
above it (checkpoints, resume, policy, failover, tools, traces, evals) has nobody.
AgentKit is that layer: model-neutral, local-first, Apple-frameworks-only, with the
Work Agent apps as canonical reference implementations. Demand is a thesis, not yet
a fact — the named proof signals are developers asking how the reference apps do
durable runs, and runtime-shaped pain on the vendor packages' issue trackers. The
Foundation Models commitment has a falsifier: it's justified by this package's
market, and if that market never materializes, the loop strategy and our own
executors keep a retreat cheap.

---

## 1. Carve the app out; make this an SPM-root repo

Execute [plans/app-carveout.md](../plans/app-carveout.md): the app moves to its own
repo ("I'll move the macOS app out of the repo soon… make this an SPM repo"),
`Package.swift` moves to the repo root, CI becomes `swift test` on both platforms.
Blocked only on the destination repo existing.

## 2. Close the shipped-with-gaps items

The named gaps from the runtime and tools work, smallest first: wrap app-side tool
calls in `InstrumentedTool` (run-id availability at the integration point);
live-verify `web_search` once a Brave key is supplied; a gated on-device
`SystemLanguageModel` test on an eligible device; human verification of the
send → quit → resume path.

## 3. Cold-provider conformance — the neutrality proof

Add a provider we did not design against and make every tool work through it
unchanged, executor added without touching anything else (**NFR-001**: adding a
provider requires no changes outside its executor and registration). Tool calling is where
neutrality actually bites (wire formats differ; provider state differs); passing
this cold is the package's core claim made falsifiable. Failing it honestly rewrites
the claim.

## 4. Provider fidelity tiers

The capabilities the FM API doesn't model, per the three-tier design
(plans/runtime-api.md §4): typed executor options (prompt caching, server-side
tools, thinking budgets), namespaced ownership-tagged conversation state (partly
shipped), direct clients for non-conversational APIs (batches, file stores).
"We implement all capabilities any of the models has, even if provider-exclusive…
we're not trying to neuter them" (FR-060). Includes the shipped compaction
strategies: tool-result clearing, summarize-and-fold, provider-native compaction
(OpenAI `/responses/compact`, Anthropic context editing) behind one `RunPolicy`.

## 5. MCP

MCP servers as tools, behind the explicit schema degradation ladder
(`GenerationSchema` accepts a strict subset of JSON Schema; unsupported keywords
reported with path and fallback, never silently flattened). The one external
dependency, opt-in via package trait.

## 6. API hardening

Public-API review against plans/runtime-api.md, DocC, an `Examples/` folder
(durable-run hello world, annotated tool, resume-after-kill), the conformance suite
made public API — the certification hook for third-party model packages.

## 7. Publication

Gated on OS 27 GA (beta ABI has already broken once between seeds — no stable tag
before GA). The package name decision ("AgentKit" is a working label). License is
decided: MIT. The README already follows plans/package-readme.md.

## 8. iOS: ToolKitForiOS, ToolKitPIM, suspension validation

Contacts/EventKit/Reminders tools (near-identical cross-platform, schemas owned by
domain targets), iOS file-access bodies (security-scoped), and validation that
checkpoints genuinely survive BGTaskScheduler-era suspension — the single most
differentiated iOS claim. Feeds the iOS reference app (app repo's backlog).

## 9. The studio (candidate, unscheduled)

A local-first trace/replay/eval inspection app — LangSmith's job, no cloud —
generalized from the reference app's trace UI. Scheduled only if PM-grade
inspection demand shows up in real use.

## Parked with reasons

- **Shell / code execution tool** — until an isolation design exists (Codex's
  Seatbelt approach is the precedent).
- **Graph DSL, multi-agent teams, RAG/memory stack** — non-goals until a real
  consumer proves need; the README's "does not do" list is the contract.
- **Second package / repo split** — only when release cadences demonstrably
  diverge or an external consumer needs a piece standalone.
