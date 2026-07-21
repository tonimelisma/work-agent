# AgentKit — Roadmap

**Future only.** What exists is in [PRODUCT.md](PRODUCT.md) and
[ENGINEERING.md](../engineering/ENGINEERING.md); a shipped item is deleted from this
list. Items are in priority order, laser-focused on the MVP: **everything is judged
by how the Work Agent app uses it** (Toni, 2026-07-19: "a sprawling SPM is unwieldy
and will never be adopted, we need laser focus and ruthless prioritization for the
MVP"). A planning agent takes items from the top and produces [plans/](../plans/);
nothing is picked from anywhere else. App-side backlog:
[../app/APP.md](../app/APP.md).

**The vision:** Apple gave every Swift app a language-model session with three
sockets — model, tools, profile — and left the sockets empty. This package fills
them with ready parts: executors for the clouds that ship no FM provider, native
tools a work assistant actually needs, a recorder that remembers what a session
forgets, MCP for the rest of the world, test doubles that make agent code testable.
**Attach, don't adopt** — nothing wraps or replaces Apple's API. Apple's own
on-device models are supported too — "Apple Foundation Models support is cheap
since it's built-in" — but no third-party local models, ever. Model-neutral,
local-first, with the Work Agent app as the proving ground; SPM-as-product work
waits in the riffraff until the app is polished and demand is real.

**The completeness rule:** every capability the README promises is either in
PRODUCT.md (built) or on this list (the MVP items or the riffraff). A promise in
neither place is a bug.

**Provider status (2026-07-19):** all eleven providers funded and keyed, including
xAI, Meta, and Thinking Machines (previously never exercised), plus the Brave
Search API key. Nothing below is blocked on quota or keys anymore; GLM alone needs
code (JWT auth — item 2; "the second best open source model").

---

## 1. Carve the app out; make this an SPM-root repo

Execute [plans/app-carveout.md](../plans/app-carveout.md): the app moves to its own
repo, `Package.swift` moves to the repo root, CI becomes `swift test` on both
platforms. Blocked only on the destination repo existing.

## 2. Verify the core, close the gaps

Everything here is unblocked now that all keys and quota exist:

- **Live-verify all eleven providers** — first-ever runs for xAI, Meta, and
  Thinking Machines; re-verify OpenAI and MiniMax now funded; one full tool-cycle
  smoke per provider, not just streaming.
- **`web_search` live** with the supplied Brave key (FR-083).
- **Human verification of send → quit → resume** — the app's core loop, never yet
  watched working end to end.
- **Wire `ask_user` and `update_plan`** into the app (question card, plan display) —
  built tools delivering zero value until surfaced.
- **Apple on-device model, verified and in the menu**: a gated
  `SystemLanguageModel` test on an eligible device, and Apple's built-in model
  joins the app's model picker (Toni, 2026-07-19: "Apple's foundation models
  need to also be in the list").
- **GLM JWT auth** — back in scope (Toni: "GLM is the second best open source
  model, put it back"): the `id.secret` JWT signing its endpoints require, so
  the eleventh provider verifies like the other ten.

## 3. Cost display — the Recorder's first user-facing slice

BYO-key users watch their spend. The Recorder's usage/cost accounting surfaced in
the app as "this conversation cost $0.42." Small, genuinely wanted, and the first
thing that *reads* the Recorder's `RecorderStore`.

## 4. Email: Gmail and Outlook via MCP

"Gmail and Outlook via MCP. No one uses the local mail app. Put them ASAP." The
assistant's killer capability, and it carries the MCP foundation with it: the
client behind a package trait, the schema degradation ladder (`GenerationSchema`
accepts a strict JSON Schema subset; unsupported keywords reported with path and
fallback, never silently flattened), Gmail and Outlook servers as the proving
integrations — real-world schema corpora, OAuth handled by the servers, not by us.
The Recorder's journal-before-execute guard starts earning rent here: "may have sent" is asked about, never silently repeated.

## 5. Document creation: PDF, docx, xlsx, pptx — and Google via MCP

"Yes all office doc creation too ASAP. Google via MCP if available. Docx xlsx pptx
locally." `ToolKitDocuments`: PDF via PDFKit; docx/xlsx/pptx created natively (all
three are OOXML zips — the ZIPFoundation path that reads docx writes them); no
code-execution sandbox in the loop, unlike every competitor. Google
Docs/Sheets/Slides only through existing MCP servers riding item 4 — we never
build our own Google OAuth. Waved for value (2026-07-19 re-analysis): **wave 1 = PDF + docx** — the daily
asks — **wave 2 = xlsx + pptx**, the fattest parsers for the rarest requests.
Per-format specs (templates, styling scope, append-vs-create) researched at
planning; xlsx/pptx *reading* settled with wave 2.

## 6. ToolKitPIM: Contacts, Calendar, Reminders

"What's on my calendar" — the local-first answer to Cowork's OAuth connectors:
EventKit/Contacts frameworks, no sign-in, works offline. Cross-platform domain
target owning the schemas; TCC usage-description obligations documented per tool;
per-tool specs researched at planning. (App control stays dead: "There's MCPs for
that.")

---

## Riffraff — parked, each with its revival trigger

Not scheduled, not deleted. Nothing here gets built until its trigger fires.

| Parked | Revival trigger |
|---|---|
| **Recorder completion**: output budgets + spill-to-store, the `read_tool_output` history tool, compaction-made-safe-by-recall | Real chats hitting the context window (per-tool paging in `read_file`/`fetch_url` carries the MVP until then) |
| **Replay + evals**: recordings replayed against other models/prompts, trajectory diffing, recorded-case CI suites | We need regression coverage when swapping models — or a developer asks |
| **Provider fidelity tiers**: neutral prompt-caching API first, then hosted-search/thinking-budget neutral APIs, direct batch/file-store clients | Item 3's cost data shows caching pays; a real feature needs the rest |
| **Cross-provider eval matrix** (generated conformance table) | SPM-as-product marketing matters; item 2's per-provider smokes carry the MVP |
| **API hardening**: DocC, `Examples/`, public conformance kit | A developer other than us asks how to use or certify against the package |
| **Publication**: name decision, README re-audit, first public tag | OS 27 GA **and** the app polished **and** demand signals |
| **iOS**: `ToolKitForiOS`, security-scoped file bodies, suspension validation | The macOS app is polished first; the suspension-safe checkpoint design is already done and costs nothing to keep |
| **The studio** (local trace/replay/eval app) | PM-grade inspection demand in real use; needs Recorder completion |
| **Composable run limits, restart-surviving interrupts, side-effect enforcement machinery** | Real use proves them ("the functionality and plans here got ahead of where I wanted to go") |
| **Public attachment-API polish**: `recorder.instrument` as public API, profile-hook capture surface, corrective tool errors, `TranscriptUtilities` as polished public functions | The first external consumer of the package |
| **Shell / code execution tool** | An isolation design exists; native document creation removed its main justification |
| **Graph DSL, multi-agent, RAG/memory stack** | Non-goals until a real consumer proves need |
| **Package/repo split** | Release cadences demonstrably diverge |
| **Third-party local models** | Never ("we will not build third party local models"). Apple's built-in models are supported; that is the line. |
