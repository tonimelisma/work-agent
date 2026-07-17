# Can a third-party app use someone's LLM subscription?

**Last verified:** 2026-07-16
**Why we looked:** Toni asked for ChatGPT **subscription** auth alongside API keys, and
asked whether the same model works for other providers. PRODUCT.md §1 rests partly on
"users already pay for a subscription and shouldn't pay again per app."

## Finding: Anthropic bans it. Google closed it. OpenAI is genuinely unclear.

**Correction (2026-07-16):** an earlier version of this doc lumped OpenAI in with
Anthropic under a flat "no." That overstated the evidence. Anthropic's is an explicit,
enforced ban. OpenAI's is *absence of documented permission*, which is a weaker and
materially different thing. Toni asked specifically about GPT — the ambiguous case, not
the banned one.

**Short version: Anthropic and Google have closed third-party subscription OAuth, with
Anthropic enforcing via account suspension. OpenAI has neither permitted nor prohibited
it — its docs simply describe the flow for its own clients. The claim that OpenAI
"explicitly supports" it traces to OpenClaw's own docs and cites nothing.**

| Provider | Third-party subscription auth | Evidence |
|---|---|---|
| **Anthropic** | **Explicitly banned. Enforced.** | OAuth "is intended exclusively for Claude Code and Claude.ai." Using Free/Pro/Max OAuth tokens "in any other product, tool, or service constitutes a violation of Anthropic's Consumer Terms." Enforced since early 2026 — accounts suspended, without notice. Equivalent access removed ~April 2026. |
| **Google** | **Closed.** | Made the same change to Gemini CLI. |
| **OpenAI** | **Undocumented. Not banned. Ambiguous.** | Docs describe sign-in for "the ChatGPT desktop app, Codex CLI, and IDE extension" — their own products. No partner program, no allowlist, no third-party path — but also no prohibition. OpenClaw's docs claim OpenAI "explicitly supports" third-party subscription OAuth, citing nothing. See below. |

### OpenClaw's claim, examined

Toni cited [docs.openclaw.ai/providers/openai](https://docs.openclaw.ai/providers/openai):
> "OpenAI explicitly supports subscription OAuth usage in external tools and workflows like OpenClaw."

Fetched and checked on 2026-07-16. The page provides **no link to any OpenAI policy,
announcement, or statement**, no citation beyond the assertion, and **no risk or ToS
caveat of any kind**. It describes the mechanism as Codex subscription OAuth sign-in
routed "through either the native Codex app-server harness or OpenClaw's embedded
runtime."

This is a third party asserting a second party's policy, with a commercial interest in
that assertion, and no source. It is not evidence about OpenAI's position. It is also
not evidence *against* it — OpenAI genuinely hasn't said. The honest state is: unknown.

### How the tools that do it anyway actually work

Third-party tools (e.g. OpenClaw) take the Codex OAuth token, **run a localhost proxy,
and translate requests into the Codex CLI's shape so OpenAI's auth check passes**, with
the user's ChatGPT subscription paying.

That is impersonating a first-party client to defeat an auth check. Not a grey area of
interpretation — the mechanism only works *because* it lies about what it is. It is also
exactly what Anthropic and Google shut down. Treating OpenAI's silence as permission is
betting the product on a door nobody has closed *yet*.

### What this costs us if we do it anyway

- **It's our users who get banned, not us.** Anthropic suspends the *account* — that is
  documented and enforced. For OpenAI no such enforcement is documented, so the risk is
  unquantified rather than known-bad. Either way the exposure lands on non-technical
  people who won't know they took it.
- **Permanent cat-and-mouse.** The mechanism depends on a proxy mimicking a client we
  don't control. Every Codex CLI release can break it.
- **It poisons the legitimate path.** A vendor that sees us impersonating its CLI is not
  a vendor that gives us a partnership later.

### What this means for the thesis

PRODUCT.md §1 plank 3 — *"users already pay for a model subscription and don't want to
pay again per app; a ChatGPT or Claude subscription should just work"* — **is at best
partially available.** The Claude half is banned outright. The ChatGPT half is
undocumented and unsourced. A plank that rests on one vendor's silence is not a plank.

This does not kill the product. Planks 1 and 2 are untouched, and the wedge survives in
its stronger form: **no vendor's own app will ever let you swap to a competitor's
model.** Cowork will never offer GPT. ChatGPT Work will never offer Claude. We can offer
both. That is a real, permanent, structural advantage — it just gets paid for with API
keys rather than a subscription the user already has.

The honest cost: BYO-API-key is a worse onboarding story than BYO-subscription for
exactly the non-technical audience in PRODUCT.md §2. "Paste an API key" is a real wall
for someone who doesn't know what one is. That's a genuine product problem and it should
be solved as a product problem, not by impersonating someone's CLI.

## Open

- **Whether OpenAI would sanction it via partnership.** No public program exists; docs
  say to contact them. Unknown, and worth asking rather than assuming.
- **Enterprise/Team plans.** All findings above concern consumer plans. Not investigated.
- **Whether any provider offers a legitimate BYO-subscription path** for third parties.
  Not found for the majors; smaller providers unexamined.

## Sources

- [Anthropic — Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
- [Anthropic bans Claude subscription OAuth in third-party apps (Feb 2026)](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)
- [A Claude Code subscription is not a developer credential](https://yage.ai/share/claude-code-subscription-not-a-developer-credential-en-20260321.html)
- [OpenAI Codex auth docs](https://learn.chatgpt.com/docs/auth) · [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [OpenAI Services Agreement](https://openai.com/policies/services-agreement/)
