import Executors
import Foundation
import Testing

// REQ: NFR-001, FR-084, FR-085 — one gated test per curated provider, all built on the
// shared `LiveProviderProbe.assertRoundtrip` harness (LiveTestSupport.swift). Every
// endpoint below is either previously probed live (docs/research/provider-chat-
// endpoints.md, 2026-07-17) or, for xai/meta/thinkingmachines, taken from a fresh
// models.dev `api.json` fetch and confirmed live for the first time here.

@Suite("Provider matrix: live tool-cycle roundtrip")
struct ProviderMatrixTests {
    @Test("deepseek: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("DEEPSEEK_API_KEY") != nil))
    func deepseek() async throws {
        let model = OpenAICompatibleModel(
            providerID: "deepseek", model: "deepseek-v4-pro",
            endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
            apiKey: LiveEnv.key("DEEPSEEK_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    @Test("anthropic: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("ANTHROPIC_API_KEY") != nil))
    func anthropic() async throws {
        let model = AnthropicModel(model: "claude-sonnet-5", apiKey: LiveEnv.key("ANTHROPIC_API_KEY") ?? "")
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    @Test("google: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("GOOGLE_API_KEY") != nil))
    func google() async throws {
        let model = OpenAICompatibleModel(
            providerID: "google", model: "gemini-3.5-flash",
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
            apiKey: LiveEnv.key("GOOGLE_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    @Test("moonshotai: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("MOONSHOT_API_KEY") != nil))
    func moonshotai() async throws {
        let model = OpenAICompatibleModel(
            providerID: "moonshotai", model: "kimi-k3",
            endpoint: URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
            apiKey: LiveEnv.key("MOONSHOT_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    @Test("alibaba: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("DASHSCOPE_API_KEY") != nil))
    func alibaba() async throws {
        let model = OpenAICompatibleModel(
            providerID: "alibaba", model: "qwen3.7-max",
            endpoint: URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            apiKey: LiveEnv.key("DASHSCOPE_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    // REQ: FR-085 — `gpt-5.6` cannot tool-call on `/v1/chat/completions` at all
    // (HTTP 400 pointing at `/v1/responses`), so OpenAI runs on the Responses
    // executor. The chat-completions path stays for providers that only speak it.
    @Test("openai: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("OPENAI_API_KEY") != nil))
    func openai() async throws {
        let model = OpenAIResponsesModel(model: "gpt-5.6", apiKey: LiveEnv.key("OPENAI_API_KEY") ?? "")
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    @Test("minimax: full tool-cycle roundtrip", .enabled(if: LiveEnv.key("MINIMAX_API_KEY") != nil))
    func minimax() async throws {
        let model = OpenAICompatibleModel(
            providerID: "minimax", model: "MiniMax-M3",
            endpoint: URL(string: "https://api.minimax.io/v1/chat/completions")!,
            apiKey: LiveEnv.key("MINIMAX_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    // REQ: GLM/Zhipu — the id.secret key is rejected as a raw bearer token
    // (docs/research/provider-chat-endpoints.md "The Zhipu/GLM wrinkle"); `.zhipuJWT`
    // signs the HS256 JWT it actually requires. `open.bigmodel.cn` tried first per the
    // plan; if both documented hosts still reject a well-formed JWT, this stays failed
    // in the results table rather than growing runtime fallback logic to chase it.
    @Test("zai (GLM): full tool-cycle roundtrip", .enabled(if: LiveEnv.key("ZHIPU_API_KEY") != nil))
    func zai() async throws {
        let model = OpenAICompatibleModel(
            providerID: "zai", model: "glm-5.2",
            endpoint: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
            apiKey: LiveEnv.key("ZHIPU_API_KEY") ?? "",
            authStyle: .zhipuJWT
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    // REQ: never probed before this increment — endpoint taken from a fresh
    // models.dev `api.json` fetch (2026-07-20): xai has no explicit `api` field
    // (its `npm` is the dedicated `@ai-sdk/xai`, not `openai-compatible`), so this
    // uses xAI's documented OpenAI-compatible base per the plan.
    @Test("xai: full tool-cycle roundtrip (first-ever probe)", .enabled(if: LiveEnv.key("XAI_API_KEY") != nil))
    func xai() async throws {
        let model = OpenAICompatibleModel(
            providerID: "xai", model: "grok-4.5",
            endpoint: URL(string: "https://api.x.ai/v1/chat/completions")!,
            apiKey: LiveEnv.key("XAI_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    // REQ: never probed before this increment — endpoint from models.dev `api.json`
    // (2026-07-20): `meta.api == "https://api.meta.ai/v1"`.
    @Test("meta: full tool-cycle roundtrip (first-ever probe)", .enabled(if: LiveEnv.key("META_MODEL_API_KEY") != nil))
    func meta() async throws {
        let model = OpenAICompatibleModel(
            providerID: "meta", model: "muse-spark-1.1",
            endpoint: URL(string: "https://api.meta.ai/v1/chat/completions")!,
            apiKey: LiveEnv.key("META_MODEL_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }

    // REQ: never probed before this increment — endpoint from models.dev `api.json`
    // (2026-07-20): `thinkingmachines.api ==
    // "https://tinker.thinkingmachines.dev/services/tinker-prod/oai/api/v1"`,
    // `npm: "@ai-sdk/openai-compatible"` confirming the common adapter applies.
    @Test(
        "thinkingmachines: full tool-cycle roundtrip (first-ever probe)",
        .enabled(if: LiveEnv.key("TINKER_API_KEY") != nil)
    )
    func thinkingmachines() async throws {
        let model = OpenAICompatibleModel(
            providerID: "thinkingmachines", model: "inkling",
            endpoint: URL(
                string: "https://tinker.thinkingmachines.dev/services/tinker-prod/oai/api/v1/chat/completions"
            )!,
            apiKey: LiveEnv.key("TINKER_API_KEY") ?? ""
        )
        try await LiveProviderProbe.assertRoundtrip(model: model)
    }
}
