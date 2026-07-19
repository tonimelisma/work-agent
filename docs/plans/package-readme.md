# Plan: the package README — structure for publication

**Status: north star, 2026-07-18.** The README that ships when the package is
published (ROADMAP horizon: extraction and publication). Structure decided by Toni
in the 2026-07-18 discussion: **pyramid principle — the whole menu before any
depth**; no pain-points section ("too sales-y for devs — we just explain the
capabilities in an understated, matter-of-fact way that hits home hard because
it's so factual"); code after breadth, not before ("maybe someone wants it just
for the tools. maybe someone just wants the testability"). **Implemented
2026-07-19**: the repo-root README.md now follows this structure, written
entirely from the SPM's perspective (Toni: "write it completely from the
perspective of the SPM… you can mention that the macOS and iOS apps use this
SPM but that's it"), with the doc index and pre-release status folded into its
tail sections. This plan remains the reference for the structure's rationale;
divergences from it in the live README are bugs.

Craft rules: every H2 answers the question a reader actually has at that scroll
depth; one sentence per idea above the per-product sections; facts without
adjectives — the reader who has hit these problems doesn't need them.

---

## The structure

1. **Title + one-liner naming the whole, not the favorite.** "Swift libraries
   for building language-model apps on Apple's Foundation Models framework:
   cloud provider executors, native tools, durable agent runs, and
   deterministic testing — independently importable from one package." Badges:
   Swift 6, macOS 27 / iOS 27, SPM, license, CI.
2. **First paragraph — the governing thought, three factual sentences.** What FM
   is and where this sits; the layers Apple doesn't supply; every library
   stands alone with Apple-only dependencies.
3. **The menu — a complete product table, before anything else.** One row per
   product, one factual line, import name, dependency column. Order = adoption
   story (model access → capabilities → durability → verification):
   - **Executors** — ten cloud providers as `LanguageModel`s; provider wire
     quirks handled **and provider capabilities beyond the FM API exposed**:
     typed options for provider-native features (cache control, server-side
     tools, thinking budgets), namespaced conversation extensions, direct
     clients for non-conversational APIs. *Depends on: FoundationModels.*
   - **ToolKit** (Files / Web / PIM / Mac) — ready-made native tools; each
     documents its host-app Info.plist keys. *FoundationModels + platform
     framework.*
   - **RuntimeCore** — runs that survive crash, relaunch, and suspension:
     journal, checkpoints, resumable interrupts, composable limits, retry,
     cross-provider failover. *FoundationModels.*
   - **RuntimeTesting** — scripted models, virtual clocks, fixture recorders;
     never links into shipping binaries. *FoundationModels.*
   - **Replay / Evals** — recorded runs replayed against new models, prompts,
     providers. *RuntimeCore + RuntimeTesting.*
   - **MCP** — MCP servers as tools with explicit schema conversion. *The one
     external dependency, opt-in.*
4. **One short section per product, menu order.** Three to five understated
   sentences plus a small code fragment each. Flat facts carry the weight ("a
   thrown tool error returns to the model as corrective output instead of
   terminating the response"; "DeepSeek requires reasoning content echoed on
   the following request; the executor does this"). Pick-and-choose made
   concrete: ToolKit shown with a vendor model package and no runtime;
   RuntimeTesting shown testing non-runtime agent code. RuntimeCore naturally
   runs longest and carries the resume-after-force-quit fragment.
5. **Compatibility.** Xcode 27, macOS 27 / iOS 27, Swift 6, beta-tracking
   notice with pin-your-versions instruction. Works with any `LanguageModel` —
   Apple on-device, PCC, Claude and Gemini packages, our executors — plus the
   provider conformance matrix (provider × verified behavior × date), which is
   the certification hook stated as a table rather than a pitch.
6. **Relationship to Foundation Models** — short, flat: no parallel types;
   `Transcript`/`Tool`/`@Generable` stay Apple's; `respond()` untouched;
   the runtime adds an entry point for durable work, not a second session.
7. **The apps** — two sentences and screenshots: Work Agent for macOS and iOS
   are built entirely on these libraries and exercise every product above.
   Evidence, zero adjectives.
8. **What this package does not do** — not a model SDK, not a second session
   API, no RAG/memory, no graph DSL, no cloud account, no telemetry.
9. **Status, docs, admin** — stability promise, DocC + Examples, contributing
   posture, MIT license, maintainer.

## The app READMEs — different genre

User-first and short: what the app does, screenshot, download, requirements.
One developer section: built on the package, which products, where to look in
the source, build instructions. The app README sells the app and funnels
developers to the package; the package README uses the apps as proof.
Cross-linked, never duplicated.
