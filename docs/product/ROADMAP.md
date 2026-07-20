# AgentKit — Roadmap

**Future only.** What exists is in [PRODUCT.md](PRODUCT.md) and
[ENGINEERING.md](../engineering/ENGINEERING.md); a shipped item is deleted from this
list. Items are in priority order; each has enough words to plan from and traces to
Toni's direction. A planning agent takes items from the top and produces
[plans/](../plans/); nothing is picked from anywhere else. (App-side backlog:
[../app/APP.md](../app/APP.md), leaving with the app.)

**The vision this backlog serves:** Apple gave every Swift app a language-model
session with three sockets — model, tools, profile — and left the sockets empty.
This package fills them with ready parts: executors for the clouds that ship no
FM provider, native tools a work assistant actually needs, a recorder that
remembers everything a session forgets, MCP for the rest of the world, and test
doubles that make agent code testable. **Attach, don't adopt** — nothing wraps
or replaces Apple's API ("bypassing the core FM API… is horrible. no developer
will see the value" — Toni, 2026-07-19, the pivot this list reflects).
Model-neutral, local-first, Apple-frameworks-only, with the Work Agent apps as
reference implementations. Demand is a thesis, not a fact; the proof signals are
developers adopting single libraries and runtime-shaped pain on the vendor
packages' issue trackers.

**The completeness rule:** every capability the README promises is either in
PRODUCT.md (built) or on this list (planned). A promise in neither place is a bug —
audited 2026-07-19, and this list closes every hole that audit found.

---

## 1. Carve the app out; make this an SPM-root repo

Execute [plans/app-carveout.md](../plans/app-carveout.md): the app moves to its own
repo ("I'll move the macOS app out of the repo soon… make this an SPM repo"),
`Package.swift` moves to the repo root, CI becomes `swift test` on both platforms.
Blocked only on the destination repo existing.

## 2. Close the shipped-with-gaps items

Smallest first: wrap app-side tool calls in `InstrumentedTool` (run-id availability
at the integration point); live-verify `web_search` once a Brave key is supplied
(FR-083); **Zhipu/GLM's JWT auth** — the README claims nine OpenAI-compatible
providers and GLM currently can't authenticate (rejects raw bearer; needs JWT
signing from its `id.secret` key); a gated on-device `SystemLanguageModel` test on
an eligible device; human verification of the send → quit → resume path.

**Provider quota/keys Toni needs to supply** (status 2026-07-19; everything else
here is agent work): **fund OpenAI** (key valid, 429 — no quota) and **fund
MiniMax** (key valid, 402 — no credit); **obtain keys for xAI, Meta, and Thinking
Machines** (none held — three of eleven providers have never been exercised);
**a Brave Search API key** for FR-083. GLM needs code (JWT signing), not money.

## 3. The Recorder — total recall, attached in one line

The pivot's centerpiece (2026-07-19; design in plans/runtime-api.md §3). A
passive recorder attached by wrapping tools and installing a profile — never
touching session control flow. Scope, which is exactly what FM doesn't keep:
persistence past the session, timestamps/durations, full untruncated tool
output, retries, tool failures, usage/cost accounting. Plus: output budgets
with spill-to-store; the **history tool** `read_tool_output(invocationID,
offset)` (the Claude Code spill-file pattern, and the side-effect-free version
of Anthropic's re-fetch-after-clearing recovery); compaction-made-safe-by-recall
as one unit; the journal-before-execute guard for consequential tools (earns
rent when email lands); corrective tool errors as a wrapper option; replay of
recordings against other models/prompts with trajectory diffing, and
recorded-case regression suites offline in CI. The former RuntimeCore internals
(journal, checkpoint store, archive) migrate inside; `TaskCoordinator` and
`RunPolicy` leave the public API and become reference-app code.

## 4. Email via MCP: Gmail and Outlook — and the MCP foundation they force

Toni, 2026-07-19: "Gmail and Outlook via MCP. No one uses the local mail app. Put
them ASAP." Email is a headline capability of every general work assistant
(Cowork's Gmail connector is tier one) and was previously absent from this list.
The path is MCP, not Apple Events — so this item *is* the MCP item, pulled up from
the bottom of the backlog: the MCP client behind a package trait, the explicit
schema degradation ladder (`GenerationSchema` accepts a strict JSON Schema subset;
unsupported keywords reported with path and fallback, never silently flattened),
with **Gmail and Outlook MCP servers as the proving integrations** — real-world
schema corpora, OAuth handled by the servers, not by us.

## 5. Document creation: PDF, docx, xlsx, pptx — and Google via MCP

Toni, 2026-07-19: "PDFs too", then "Yes all office doc creation too ASAP. Google
via MCP if available. Docx xlsx pptx locally." A `ToolKitDocuments` product:

- **PDF** — PDFKit, native.
- **docx / xlsx / pptx creation, locally** — all three are OOXML zip containers;
  the same ZIPFoundation path that reads docx writes them. Native Swift, no
  code-execution sandbox (the competitors all route document generation through
  sandboxed code; we don't have to — a differentiator worth stating in the
  README when built).
- **Google Docs/Sheets/Slides via MCP, if available** — rides item 4's MCP
  foundation; use existing Google Workspace MCP servers, OAuth theirs. If no
  usable server exists at planning time, the local formats ship and Google
  waits — we do not build our own Google OAuth integration.

Per-format tool specs (templates, styling scope, append-vs-create semantics) are
researched during planning; xlsx/pptx *reading* is the cheap adjacency to settle
in the same plan.

## 6. The cross-provider eval suite — neutrality proven against every cloud

Toni, 2026-07-19, replacing the earlier single-cold-provider idea ("5 is stupid.
We have so many providers. We'll build an eval suite that runs against each
cloud"): a live eval suite that runs the same scenarios — tool cycles, provider
state round-trips, failover, streaming, every ToolKit tool — **against each
configured cloud provider**, key-gated per provider, producing a pass/fail matrix
(the README's conformance table becomes generated output, not prose). Neutrality
stops being an assertion and becomes a continuously re-runnable measurement across
all eleven providers; a new provider's executor is proven by joining the matrix
(NFR-001 verified as a side effect, per provider, forever).

## 7. Provider fidelity tiers — neutral APIs for shared capabilities

The capabilities the FM API doesn't model, per the three-tier design
(plans/runtime-api.md §4): typed executor options, namespaced ownership-tagged
conversation state (partly shipped), direct clients for non-conversational APIs
(batches, file stores). **The API rule, decided 2026-07-19** (Toni: "Can 7 be
provider neutral API so if several providers have a given feature we support all
of them with the same API"): when a capability exists across several providers —
prompt caching, server-side web search, thinking/reasoning budgets, compaction —
it gets **one provider-neutral API** that each executor maps to its own wire
form; only capabilities genuinely exclusive to one provider get provider-specific
options.
"We implement all capabilities any of the models has, even if provider-exclusive…
we're not trying to neuter them" (FR-060). Includes the compaction strategies:
tool-result clearing, summarize-and-fold, provider-native compaction (OpenAI
`/responses/compact`, Anthropic context editing) behind one neutral compaction
policy — a Recorder-adjacent attachment, not an engine setting.

## 8. ToolKitPIM: Contacts, Calendar, Reminders

The cross-platform PIM domain target (EventKit/Contacts — local frameworks, no
OAuth, schemas owned by the target). Per-tool specs are researched and written as
part of planning this item ("we can research and figure out the specifics of the
tools"); TCC usage-description obligations documented per tool. **Mac app control
is removed, not deferred** — Toni, 2026-07-19: "No mac control. Remove it.
There's MCPs for that." Apps that want app control mount an MCP server for it
through item 4's foundation; we never build `ToolKitMacControl`.

## 9. API hardening

Public-API review against plans/runtime-api.md, DocC, an `Examples/` folder
(durable-run hello world, annotated tool, resume-after-kill), the conformance
suite made public API — the certification hook for third-party model packages.

## 10. Publication

Gated on OS 27 GA (beta ABI has already broken once between seeds — no stable tag
before GA). The package name decision ("AgentKit" is a working label). License is
decided: MIT. The README already follows plans/package-readme.md; at publication
its claims must be re-audited against PRODUCT.md under the completeness rule.

## 11. iOS: ToolKitForiOS and suspension validation

iOS file-access bodies (security-scoped URLs behind the same `read_file` schema),
the `ToolKitForiOS` umbrella over the shared domain targets, and validation that
checkpoints genuinely survive BGTaskScheduler-era suspension — the single most
differentiated iOS claim. Feeds the iOS reference app (app repo's backlog).

## 12. The studio (candidate, unscheduled)

A local-first trace/replay/eval inspection app — LangSmith's job, no cloud —
generalized from the reference app's trace UI. Scheduled only if PM-grade
inspection demand shows up in real use; depends on item 3's replay foundations.

## Parked with reasons

- **A session-owning engine** — `runtime.run()`, public `TaskCoordinator`,
  `RunPolicy`, composable limit machinery, restart-surviving interrupts,
  side-effect *enforcement* — parked until real use proves them. Toni,
  2026-07-19: "bypassing the core FM API so I can get a few convenience
  functions is horrible"; "switching providers is not enough"; "the
  functionality and plans here got ahead of where I wanted to go." The
  provider-state strip survives as a utility; the guard survives inside the
  Recorder's wrapper.
- **Shell / code execution tool** — until an isolation design exists (Codex's
  Seatbelt approach is the precedent).
- **Graph DSL, multi-agent teams, RAG/memory stack** — non-goals until a real
  consumer proves need; the README's "does not do" list is the contract.
- **Second package / repo split** — only when release cadences demonstrably
  diverge or an external consumer needs a piece standalone.
