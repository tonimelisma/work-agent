# WorkKit — Roadmap

**Future only.** What exists is in [PRODUCT.md](PRODUCT.md) and
[ENGINEERING.md](../engineering/ENGINEERING.md); a shipped item is deleted from this
list. Items are in priority order. A planning agent takes items from the top and
produces [plans/](../plans/); nothing is picked from anywhere else.

**This repo is SPM-root: a standalone Swift package, no reference app in-tree**
(Toni, 2026-07-20: "instead of carving the app out, I'll create it anew... just
delete it from this repo, and move the current repo to be an SPM repo for
WorkKit"). The Work Agent app that used to live here and drove this package's
priorities is gone from this repo entirely — not carried over, not carved out.
A future native app is a separate, later effort in its own repo, consuming this
package as a dependency; it is not this roadmap's concern until it exists.

**The vision:** Apple gave every Swift app a language-model session with three
sockets — model, tools, profile — and left the sockets empty. This package fills
them with ready parts: executors for the clouds that ship no FM provider, native
tools a work assistant actually needs, a recorder that remembers what a session
forgets, MCP for the rest of the world, test doubles that make agent code testable.
**Attach, don't adopt** — nothing wraps or replaces Apple's API. Apple's own
on-device models are supported too — "Apple Foundation Models support is cheap
since it's built-in" — but no third-party local models, ever. Model-neutral,
local-first, standalone.

**The completeness rule:** every capability the README promises is either in
PRODUCT.md (built) or on this list (the roadmap items or the riffraff). A promise
in neither place is a bug.

---

## 1. Email: Gmail and Outlook via MCP

"Gmail and Outlook via MCP. No one uses the local mail app. Put them ASAP." The
assistant's killer capability, and it carries the MCP foundation with it: the
client behind a package trait, the schema degradation ladder (`GenerationSchema`
accepts a strict JSON Schema subset; unsupported keywords reported with path and
fallback, never silently flattened), Gmail and Outlook servers as the proving
integrations — real-world schema corpora, OAuth handled by the servers, not by us.
The Recorder's journal-before-execute guard starts earning rent here: "may have sent" is asked about, never silently repeated.

## 2. Document creation: PDF, docx, xlsx, pptx — and Google via MCP

"Yes all office doc creation too ASAP. Google via MCP if available. Docx xlsx pptx
locally." `ToolKitDocuments`: PDF via PDFKit; docx/xlsx/pptx created natively (all
three are OOXML zips — the ZIPFoundation path that reads docx writes them); no
code-execution sandbox in the loop, unlike every competitor. Google
Docs/Sheets/Slides only through existing MCP servers riding item 1 — we never
build our own Google OAuth. Waved for value (2026-07-19 re-analysis): **wave 1 = PDF + docx** — the daily
asks — **wave 2 = xlsx + pptx**, the fattest parsers for the rarest requests.
Per-format specs (templates, styling scope, append-vs-create) researched at
planning; xlsx/pptx *reading* settled with wave 2.

## 3. ToolKitPIM: Contacts, Calendar, Reminders

"What's on my calendar" — the local-first answer to Cowork's OAuth connectors:
EventKit/Contacts frameworks, no sign-in, works offline. Cross-platform domain
target owning the schemas; TCC usage-description obligations documented per tool;
per-tool specs researched at planning.

---

## Riffraff — parked, each with its revival trigger

Not scheduled, not deleted. Nothing here gets built until its trigger fires.

| Parked | Revival trigger |
|---|---|
| **Recorder completion**: output budgets + spill-to-store, the `read_tool_output` history tool, compaction-made-safe-by-recall | Real agent use hitting the context window (per-tool paging in `read_file`/`fetch_url` carries the package until then) |
| **Replay + evals**: recordings replayed against other models/prompts, trajectory diffing, recorded-case CI suites | We need regression coverage when swapping models — or a developer asks |
| **Provider fidelity tiers**: neutral prompt-caching API first, then hosted-search/thinking-budget neutral APIs, direct batch/file-store clients | Real usage data shows caching pays; a real feature needs the rest |
| **Unbuffered assistant text on tool-enabled turns**: FR-084 must withhold text until the stream proves no tool call is coming, because Apple's channel has no entry-removal action | Apple adds a way to remove or convert an entry mid-generation, or a consumer reports the latency as a real problem |
| **moonshotai's intermittent tool calling**: `kimi-k3` sometimes fabricates a tool result instead of calling the tool; nothing in our request body differs from a working hand-built probe | It stops being intermittent and starts being systematic, or Moonshot ships a fix worth re-measuring |
| **Cross-provider eval matrix** (generated conformance table) | SPM-as-product marketing matters; the per-provider live tests (`ExecutorsLiveTests`) carry the package until then |
| **API hardening**: DocC, `Examples/`, public conformance kit | A developer other than us asks how to use or certify against the package |
| **Publication**: name decision confirmed, README re-audit, first public tag | OS 27 GA **and** demand signals |
| **iOS**: `ToolKitForiOS`, security-scoped file bodies, suspension validation | A real iOS consumer exists; the suspension-safe checkpoint design is already done and costs nothing to keep |
| **The studio** (local trace/replay/eval app) | PM-grade inspection demand in real use; needs Recorder completion |
| **Composable run limits, restart-surviving interrupts, side-effect enforcement machinery** | Real use proves them ("the functionality and plans here got ahead of where I wanted to go") |
| **Public attachment-API polish**: `recorder.instrument` as public API, profile-hook capture surface, corrective tool errors, `TranscriptUtilities` as polished public functions | The first external consumer of the package |
| **Shell / code execution tool** | An isolation design exists; native document creation removed its main justification |
| **Graph DSL, multi-agent, RAG/memory stack** | Non-goals until a real consumer proves need |
| **Package/repo split** | Release cadences demonstrably diverge |
| **Third-party local models** | Never ("we will not build third party local models"). Apple's built-in models are supported; that is the line. |
| **Cost display** (usage → $ surfaced to a user) | A consuming app exists to render it; the package's read API (`RecorderStore`) is already built |
