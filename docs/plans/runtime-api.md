# Plan: the package's developer-facing API — remaining unbuilt surface

**Status: mostly shipped.** This was the north-star doc for the attachment pivot
(Toni's verdicts that forced it: "bypassing the core FM API so I can get a few
convenience functions is horrible... no developer will see the value" · "MCP
support should live somewhere else, it shouldn't depend on using our runtime
should it?"). The attach-never-replace design, the canonical usage example, and
the Executors/ToolKit/Recorder/Testing products it specified are all built —
see [PRODUCT.md](../product/PRODUCT.md) (what/why) and
[ENGINEERING.md](../engineering/ENGINEERING.md) (architecture, esp. "Attachments,
not an engine") for the shipped record, and the repo-root [README.md](../../README.md)
for the live canonical example. This doc's remaining content is what's still
unbuilt: the standalone MCP design, and a couple of DX commitments not yet
exercised by any built increment.

---

## MCP — standalone, by decree

Depends on FM + the schema bridge + the swift-sdk (behind a package trait) —
**never on the Recorder or anything else of ours**. Its tools are plain FM tools
usable with a bare session. Schema conversion is explicit: exact-subset
conversion or a precise rejection with keyword and path; the degradation ladder
governs the rest.

```swift
final class MCPServerConnection {           // one per configured server
    // stdio transport: Process + pipes, JSON-RPC 2.0, initialize → tools/list → tools/call
    // http transport: URLSession, Streamable HTTP
    func discoveredTools() async throws -> [MCPTool]   // each wraps one remote tool
}
struct MCPTool: Tool {
    // spec: name namespaced "\(serverLabel).\(toolName)"; parameters passed through
    //       (JSON Schema must survive GenerationSchema conversion — strict subset,
    //        measured; unsupported keywords go through the degradation ladder
    //        rather than being silently flattened)
    // invoke: tools/call; content blocks mapped to ToolOutput; isError passthrough
    // effect: .consequential by default — a remote tool is assumed side-effectful
    //         unless its annotations say readOnlyHint (MCP tool annotations, trust-but-verify)
}
```

Implementation choice: evaluate the **official `modelcontextprotocol/swift-sdk`**
first (it exists and is actively maintained; verify at increment time that it
covers client role + stdio + Streamable HTTP at our minimum macOS). If it fits,
wrap it; if not, the client subset we need (initialize/list/call/notifications)
is small enough to hand-roll against the spec. Either way the seam is
`MCPServerConnection`, so the choice is swappable and needs no ADR until proven
otherwise — the *decision to ship MCP at all* gets the ADR.

Product surface: v1 config is a developer-facing file/hidden pane for
Toni-stage use; end users eventually get curated connectors that are
*implemented as* MCP servers and never described in those words. Deferred tool
loading (both harnesses' ToolSearch pattern) becomes worthwhile only past
~30–40 tools; the registry's assembly step is where it slots when needed. Same
for MCP resources/prompts: skip until a concrete need. This is what ROADMAP
item 2 (email via MCP) needs built first.

## Utilities — demoted, deliberately small

`TranscriptArchive.save/load` and `replay(to:)` are built (see ENGINEERING.md).
Kept small on purpose: retry is documented as a snippet, not shipped as a
policy engine — revisit only if a real increment needs more than that.
