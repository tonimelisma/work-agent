# Work Agent — the app (moving out of this repo)

**This file moves, whole, to the app's new repo** per
[../plans/app-carveout.md](../plans/app-carveout.md). It parks everything
app-specific that used to live in this repo's product docs so the SPM docs can stay
about the SPM. Until the carve-out, the app code (`Work Agent/`, `Work AgentTests/`,
the Xcode project) still builds here against the local AgentKit package.

## What the app is

A native macOS app for people who are not developers: an AI agent driven through
**chat** ("the user chats" — like Claude Cowork; no task catalog, no task templates),
doing real work on the user's Mac with whatever model the user chooses. Model-neutral
by construction — the reason it exists is that no vendor's own app will ever offer a
competitor's model. BYO API key, cloud only, "no local models ever." Reference
implementation of AgentKit. Stage: Toni is the only user; onboarding polish and
multi-user are deliberately absent.

## Implemented app features

- **FR-068 / FR-070** — chat main window; messages stream from the selected model.
- **FR-071** — multiple concurrent conversations with a sidebar (Toni: sidebar, not
  one conversation); switching selection never cancels another conversation's run.
- **FR-072 / FR-073** — quit mid-run pauses at a checkpoint and offers resume on
  relaunch (pause-and-offer was Toni's explicit choice over auto-resume);
  conversations survive restart. SwiftData persistence (see rationale below).
- **Settings** (FR-050, FR-069, FR-051, FR-055, FR-056, FR-057, FR-052): add/remove
  providers by API key, verified against the provider before reported usable; keys
  in the macOS Keychain only; model picked in the chat. Registry-driven (models.dev
  bundled snapshot + refresh; FR-054, NFR-007, NFR-008: lenient decoding, never
  block launch on network).
- **FR-061 / FR-062** — the curated set, Toni's list verbatim: eleven first-party
  providers, sixteen models ("start with all of the ones I said"; "no resellers for
  now"): OpenAI GPT-5.6 ×4, Anthropic opus/sonnet/fable, Kimi K3, Grok 4.5,
  GLM-5.2, Muse Spark 1.1, Gemini 3.5 Flash, DeepSeek V4 Pro, MiniMax-M3, Inkling,
  Qwen 3.7 Max. **Live-verification status (2026-07-19):** streaming verified —
  DeepSeek, Anthropic, Google, Moonshot, Alibaba; key valid but unfunded — OpenAI
  (429), MiniMax (402); **Zhipu/GLM needs custom auth** — rejects a raw bearer
  token, appears to require JWT signing from its `id.secret` key; a third auth
  style, flagged and unbuilt. No keys held: xAI, Meta, Thinking Machines — in the
  menu, unverifiable until keyed.
- **Honesty flag carried from the old spec:** FR-052, FR-054, FR-056, FR-057,
  NFR-006, NFR-007, NFR-008 were marked *inferred — standard practice, seen
  without objection but never explicitly confirmed by Toni*. That flag survives
  the restructure; they remain his to veto.
- **FR-063 / FR-065 / FR-066** — full traces persisted regardless of display;
  reasoning and tool calls shown user-friendly; reasoning display toggleable
  ("we store traces of everything… showcase them in the UI in a nice UI too").
- **NFR-002 / NFR-003 / NFR-006** — state stays on the Mac; Developer ID + notarized
  distribution; UI responsive during runs.

## App decisions and rationale (formerly ADR-0003, ADR-0005, ADR-0008)

- **Developer ID, never Mac App Store.** The App Sandbox forbids what the product
  does (arbitrary file access, later app control). The Xcode template had the
  sandbox silently on — it blocked all outbound network; it's off, Hardened Runtime
  stays on for notarization.
- **models.dev as the registry.** A maintained public registry beats hand-curating
  provider metadata; bundled snapshot + lenient decode + background refresh so the
  app works offline and never breaks on registry drift.
- **SwiftData for conversations.** Native, zero dependencies, `@Query` drives the
  sidebar and live message updates with no observation bridge. Messages stored as
  encoded blobs, not message rows — nothing queries inside a conversation yet, and
  a relational schema would be unearned complexity. Revisit if content search
  arrives.

## App backlog (future, in priority order)

1. **Wire the built-but-unsurfaced tools**: `ask_user` needs a question card,
   `update_plan` a plan display; wrap app tool calls in `InstrumentedTool` once the
   run id is available at integration; supply a Brave key to verify `web_search`
   live.
2. **Real use starts steering** — Toni works through the app; observed gaps pick
   what's next ("real tasks as in evals… no, we don't need that").
3. **Permissions and approvals** — deferred wholesale ("We don't have folders.
   Permissions come later"); designed against observed friction.
4. **FR-005 / FR-067** — BYO credentials generally; OpenAI subscription sign-in
   specifically. Standing caveat: OpenAI documents sign-in for its own clients
   only; the claim that third-party subscription OAuth is permitted is unsourced
   (OpenClaw's docs, citing nothing); Anthropic and Google both closed this path
   in 2026 with enforcement. Toni's call to accept the risk before building.
   Related open product problem: how a non-technical user gets an API key at all.
5. **FR-060 surface** — expose provider-exclusive capabilities in the app as
   AgentKit's fidelity tiers land.
6. **Connections** (Gmail/Drive/M365), **native app control**, **background
   execution** (LaunchAgent/XPC), **automations** — each waits for a real task to
   demand it.
7. **iOS sibling app** — the runtime's second reference implementation; scoped
   file access and consent arrive by OS force.
