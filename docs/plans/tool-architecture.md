# Plan: the tool layer — remaining unbuilt surface

**Status: increment 5 built 2026-07-19.** This was the plan for the native tool
layer (Toni: "explain what a flexible tool API for the current macOS app could
look like… create a detailed plan to implement all of these"). The six file
tools, `fetch_url`, `web_search`, `ask_user`, and `update_plan` are all built —
see [PRODUCT.md](../product/PRODUCT.md) (FR-074–083, what/why) and
[ENGINEERING.md](../engineering/ENGINEERING.md) (architecture, esp. "Typed
tools, not a shell/patch executor" for the design philosophy this plan
originally argued). Each tool's own implementation rationale now lives as a
`// REQ:` comment at the point of implementation in `Sources/ToolKitFiles/` and
`Sources/ToolKitWeb/` — `rg "FR-07"` / `rg "FR-08"` finds it. The core
abstraction this plan originally sketched (`ToolRunner`, `ToolRegistry`,
provider seam) was superseded by the attachment pivot before being built — see
[runtime-api.md](runtime-api.md) — and is not carried forward here.

This doc's remaining live content: MCP as a tool source (registry-composition
angle only — the connection-level design lives in
[runtime-api.md](runtime-api.md)), and the permanently-deferred non-goals.

---

## MCP as a tool source, not a feature

MCP servers plug in at the per-turn tool assembly point, and the model loop
never knows it's talking to a remote tool vs. a built-in one — each MCP tool is
just another `FoundationModels.Tool` once discovered
(`MCPServerConnection`/`MCPTool`, designed in runtime-api.md). Deferred tool
loading (both harnesses' ToolSearch pattern) becomes worthwhile only past
~30–40 tools. Same for MCP resources/prompts: skip until a concrete need. This
is what ROADMAP item 2 (email via MCP) needs built first.

## Permissions/approvals — deferred wholesale, not tracked anywhere yet

*"We don't have folders. Permissions come later."* There is no folder-grant
model; file tools take ordinary canonicalized paths, and the `effect` field on
`ToolAnnotations` exists precisely so the eventual permissions/approval design
is a policy retrofit, not a refactor. **Gap named honestly:** unlike every other
deferred item in this doc, this one has no ROADMAP entry (not in the numbered
items, not in the riffraff table) — it's deferred but not scheduled. Worth
Toni's call on whether it belongs on the roadmap or in the riffraff table with
a revival trigger.

## Explicitly out of scope, permanent non-goals unless triggered

Shell/exec (needs an isolation design first — Codex's Seatbelt `sandbox-exec`
is the working precedent on macOS; the `Tool` protocol accommodates it later as
just another tool, no rework needed). Subagents (needs multi-loop
infrastructure; the protocol doesn't block it). Computer use/Accessibility
(deferred). Connectors with OAuth (deferred until a real task needs one — MCP
is how they'll arrive, per above).
