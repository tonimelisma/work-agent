# ADR-0003 — Distribute via Developer ID, not the Mac App Store

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni

## Context

Distribution is not a shipping detail on macOS — it decides what the application is
permitted to do, and it decides it early. Mac App Store distribution mandates the App
Sandbox, which forbids most of what an agent that "does real work on your Mac" must do:

- Controlling other applications via the Accessibility API.
- Sending arbitrary AppleScript / Apple events to apps not declared up front.
- Launching arbitrary subprocesses — which likely includes a bundled agent runtime,
  depending on ADR-0005.
- Reaching files outside explicit user selection without repeated prompting.

This can't be deferred. It constrains the runtime decision in increment 2, and it
constrains whether native app control is ever possible. Retrofitting sandbox compliance
means deleting capabilities, not adding entitlements.

Every real Mac automation tool — Raycast, Alfred, Keyboard Maestro, Hazel — ships
Developer ID for exactly this reason. That's not a coincidence, it's the constraint
binding.

## Decision

Developer ID signed and notarized, distributed directly. Not the Mac App Store, and not
"Developer ID now, App Store later."

Requirement: NFR-003.

## Considered options

**Developer ID + notarization** *(chosen)* — Full Accessibility, Apple events, screen
capture, subprocesses, user-selected file access. Hardened Runtime still applies, so
entitlements and TCC still constrain us — this buys capability, not a free pass. Costs
$99/yr, a notarization step in CI, and self-owned update/install UX.

**Mac App Store** — Discovery, trusted install, payments, automatic updates. Real
benefits for the "friends, then public" path in PRODUCT.md. Rejected because the sandbox
forbids the product. Not "makes it harder" — forbids it. Shipping a store build means
shipping a different, worse application.

**Unsigned / local build** — Zero cost, zero ceremony, and the only user today is Toni.
Rejected: TCC treats unsigned and ad-hoc-signed binaries badly, permission grants break
on every rebuild, and Accessibility/Screen Recording approvals are tied to signing
identity. We'd fight this daily and learn nothing real about how the app behaves on
someone else's Mac. The $99 buys accurate feedback.

**Developer ID now, keep a sandbox-compatible core for a later store build** — Keeps the
option. Rejected as the worst of both: it constrains architecture *now* for an option we
almost certainly never exercise, and "sandbox-compatible core" is a claim that rots
silently the moment nobody's testing it. If the store ever matters, it's a different
product and gets its own ADR.

## Consequences

**Good.** Accessibility, Apple events, screen capture, and subprocesses all stay on the
table. ADR-0005 can consider a bundled runtime without a distribution veto. No review
queue, ship when ready.

**Bad.** $99/yr, forever. Notarization in CI, and notarization failures are famously
opaque. We own updates (Sparkle or equivalent), install UX, and the Gatekeeper
first-run experience — which is a genuine trust cost with non-technical users, who are
exactly our audience per PRODUCT.md §2. "Downloaded from the internet" is scarier than
an App Store button, and that lands hardest on the people we're building for.

**Not decided here.** Hardened Runtime entitlements, TCC prompt timing, and the update
mechanism. Later increments, when something needs them.
