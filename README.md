# Work Agent

Two products in one repo, three layers:

1. **A native Swift agent-runtime SPM package** (in design; iOS 27 + macOS 27) that
   builds on Apple's Foundation Models framework — durable agent runs, cloud
   provider executors with full provider fidelity, native tool implementations
   (ToolKit), and deterministic testing, as independently importable products.
2. **Work Agent**, a native macOS app for people who are not developers: an AI
   agent, driven through chat, that does real work on the user's Mac with
   whatever model the user chooses — model-neutral by construction. A sibling
   iOS app is planned. Both are real products and the package's canonical
   reference implementations.

Current state: the app runs and streams chat from real cloud providers
(eleven curated, sixteen models); the runtime architecture is decided and
POC-proven; the agent loop is the next build increment. See
[ENGINEERING.md](docs/engineering/ENGINEERING.md) for what is true right now.

## Documentation

| Doc | What it answers |
|---|---|
| [Working agreement](CLAUDE.md) | How this repo is run: non-negotiables, traceability, increment workflow |
| [PRODUCT.md](docs/product/PRODUCT.md) | The app: what, for whom, why it can exist, what it is not |
| [RUNTIME.md](docs/product/RUNTIME.md) | The runtime package: the layer bet, capabilities, non-goals, evidence and falsifiers |
| [REQUIREMENTS.md](docs/product/REQUIREMENTS.md) | What must be true, testably, with permanent IDs |
| [ROADMAP.md](docs/product/ROADMAP.md) | Increment order, the post-engine horizon, what's deliberately deferred |
| [ENGINEERING.md](docs/engineering/ENGINEERING.md) | How the system is built *right now* — reality, never aspiration |
| [Architecture decisions](docs/decisions/) | Why each choice over its alternatives — living ADRs, kept current |
| [Research](docs/research/README.md) | What we learned outside this repo, with evidence and verification dates |

In-flight design proposals live in [docs/plans/](docs/plans/); they are working
documents, binding only once an increment's definition-of-ready confirms them.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Toni Melisma.
