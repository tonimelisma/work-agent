# ADR-0005 — Use models.dev as the provider/model registry

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni
- **Supersedes:** —
- **Superseded by:** —

## Context

The settings UI lets the user add one or more LLM providers, which means we need to
know which providers exist, which models each serves, and — critically for the
neutrality thesis — which of those models can call tools.

Maintaining that by hand is a treadmill. Models ship weekly; a stale list is a
user-visible bug in the exact surface where a non-technical user forms their first
impression of whether this app is current.

Evidence and measurements: [docs/research/llm-provider-registries.md](../research/llm-provider-registries.md).

## Decision

Use **[models.dev](https://models.dev)** (`https://models.dev/api.json`) as the source
of provider and model metadata. MIT licensed, maintained by the SST team, the same
registry OpenCode uses.

Consume it as follows:

- **Bundle a snapshot** of `api.json` in the app. It is the source of truth at launch.
- **Treat the network copy as a cache refresh**, never a dependency. The app must be
  fully functional with the network down and must never block launch on a fetch.
- **Decode leniently.** Unknown fields ignored; a model or provider that fails to
  decode is skipped, not fatal. The registry has no versioning guarantee, so its schema
  will change under us at some point without notice.
- **Hardcode base URLs for the majors ourselves.** `anthropic`, `openai`, and `google`
  carry no `.api` field — models.dev assumes the Vercel AI SDK's npm packages supply
  them. We have no such package. The registry is a catalog, not a connection config.

## Considered options

**models.dev** *(chosen)* — Best capability metadata found: `tool_call` is present on all
5,666 models with no gaps, plus reasoning options, modalities, context/output limits,
and pricing on 93%. MIT. Actively maintained with schema-validated PRs. Proven at scale
by OpenCode. Costs: no stability guarantee, 3.18 MB needing a caching story, no base
URLs for the majors, and its priorities follow the Vercel AI SDK — if the AI SDK's needs
diverge from ours, we're not the constituency.

**LiteLLM's `model_prices_and_context_window.json`** — Comparable breadth, MIT, well
known. Rejected: it's a byproduct of LiteLLM's Python proxy rather than a registry, so
its shape serves LiteLLM's internals. Documented staleness (39 dead OpenRouter entries,
models with missing pricing). Capability metadata is weaker than models.dev's, and
capability — specifically `tool_call` — is the field we most need.

**OpenRouter's models API** — Live and authoritative, zero staleness. Rejected as *the*
registry because it only describes OpenRouter's own catalog; adopting it means routing
every request through one vendor. That is precisely the coupling the product exists to
avoid (PRODUCT.md §1), and it would be a product decision smuggled in as a data-source
decision. It remains a good provider to *offer*.

**Hand-maintained list** — No dependency, no schema risk, full control, and honestly
fine for the 3–4 providers we'll support first. Rejected: it's a treadmill that never
ends, and it fails silently — a model released last week is invisible with no error.
Worth noting the win is partial: we hand-maintain base URLs for the majors either way.

**No registry — free-text model IDs** — Trivial. Rejected: our users are explicitly not
developers (PRODUCT.md §2). "Type a model identifier" is exactly the failure this
product exists to avoid.

## Consequences

**Good.** The provider list is current without our effort. `tool_call` lets us filter
the model picker to models that can actually do agentic work, which prevents a whole
class of confusing failure. Pricing and context data are available for free if the UI
ever wants them. MIT, so vendoring a snapshot is unambiguously fine.

**Bad.** A third party we don't control now shapes a user-facing surface. The schema
can break with no warning and no version to pin — the bundled snapshot means a break
degrades us to stale rather than broken, which is the whole reason for that design.
We inherit their judgment about what's true: if `tool_call: true` is wrong for some
model, our users hit it, and we have no way to know without testing. That risk is
tracked in the research doc, not solved.

**Also.** Base URLs for the majors are ours to maintain, forever. Small, but it means
"we use a registry" is not the whole story and shouldn't be believed as such.

## Validation

The registry claim that matters most — `tool_call` — is unverified against real provider
behavior. When tools land, spot-check it. If it's unreliable, this ADR needs a follow-up
on whether we trust registry capability data or probe for it.

**Validated 2026-07-16, and it cost us.** The decision above stands — models.dev is still
the right registry. But one stated consequence was measured and found wrong:

> "**Bundle a snapshot** of `api.json` in the app. It is the source of truth at launch."

The registry gained a provider and three models **within an hour** of a snapshot being
taken. An agent then used that snapshot to tell Toni three of his chosen models didn't
exist. They did.

The bundle is a **stale floor for offline use**, not a source of truth. The network is
the source of truth and refresh must be eager. The decision doesn't change; the framing
of the consequence does. Detail:
[research/llm-provider-registries.md](../research/llm-provider-registries.md) § staleness.

If eager refresh proves to conflict with NFR-008 (don't block launch), that tension needs
a new ADR rather than a quiet compromise.
