# Foundation Models adaptation POC

An isolated, macOS 27 experiment. Run its reproducible offline gate from the repository root:

```sh
swift test --package-path Experiments/FoundationModelsPOC
```

`swift run --package-path Experiments/FoundationModelsPOC foundation-models-probe --help`
lists the intended DeepSeek, Google, and Anthropic live cases. The package links the
macOS 27 Foundation Models provider surface. The live provider cycles were verified on
2026-07-18; executor/session conformance and scrubbed fixtures remain the pending gates.
No credentials are read or logged by the offline suite.

## Live credentials

For a local live run, source the repository-root `.env` **in the invoking shell**. It is
the established repository credential convention and is ignored by Git. Required names
are `DEEPSEEK_API_KEY`, `GOOGLE_API_KEY`, and `ANTHROPIC_API_KEY`. The probe must never
print these values or record them in its fixtures.
