//
//  ProviderCatalog.swift
//  Work Agent
//
//  What models.dev doesn't tell us: base URLs for the majors, and how each
//  provider wants its credential presented.
//

import Foundation

/// How a provider expects the API key to be presented on a request.
///
/// This is the first real appearance of the provider seam (FR-001). It stays small on
/// purpose — it describes authentication, not inference. The inference adapter is
/// ADR-0006's problem and does not exist yet.
nonisolated enum ProviderAuthStyle: Sendable {
    /// `Authorization: Bearer <key>` — OpenAI and nearly every OpenAI-compatible host.
    case bearer
    /// `x-api-key: <key>` plus a required version header — Anthropic.
    case anthropic
    /// `x-goog-api-key: <key>` — Google.
    case google
}

/// Provider facts that models.dev does not carry.
nonisolated enum ProviderCatalog {
    // REQ: FR-051 — models.dev omits `api` for anthropic/openai/google because it targets
    // the Vercel AI SDK, whose per-provider npm package hardcodes these. We have no such
    // package, so the majors' base URLs are ours to maintain. Verified absent from the
    // live registry on 2026-07-16; see docs/research/llm-provider-registries.md.
    static let fallbackBaseURLs: [String: URL] = [
        "anthropic": URL(string: "https://api.anthropic.com")!,
        "openai": URL(string: "https://api.openai.com/v1")!,
        "google": URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
    ]

    private static let authStyles: [String: ProviderAuthStyle] = [
        "anthropic": .anthropic,
        "google": .google,
    ]

    /// The registry's base URL if it has one, else ours. Nil means unusable.
    static func baseURL(for provider: RegistryProvider) -> URL? {
        provider.api ?? fallbackBaseURLs[provider.id]
    }

    // REQ: FR-001 — base URLs for *chat* (streaming inference), which can differ from the
    // registry's `api` (that one is for model listing / verification). Confirmed by live
    // probes on 2026-07-16; see docs/research/provider-chat-endpoints.md.
    //
    // Two overrides earn their place:
    //   • google  — registry `api` is the native Gemini endpoint; its OpenAI-compatible
    //     surface lives under /v1beta/openai, letting Gemini use the OpenAI adapter.
    //   • minimax — registry `api` is Anthropic-shaped (/anthropic/v1); its
    //     OpenAI-compatible endpoint is /v1, so one code path covers it.
    private static let chatBaseURLs: [String: URL] = [
        "openai": URL(string: "https://api.openai.com/v1")!,
        "google": URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
        "minimax": URL(string: "https://api.minimax.io/v1")!,
    ]

    /// Base URL to POST chat completions to.
    static func chatBaseURL(for provider: RegistryProvider) -> URL? {
        chatBaseURLs[provider.id] ?? baseURL(for: provider)
    }

    /// Bearer is the right default: the 142 registry providers that publish a base URL
    /// are overwhelmingly OpenAI-compatible, and the exceptions are named above.
    static func authStyle(for providerID: String) -> ProviderAuthStyle {
        authStyles[providerID] ?? .bearer
    }

    /// Where to GET to check a key is live. Every one of these lists models, which is
    /// the cheapest authenticated read each provider offers.
    static func verificationRequest(for provider: RegistryProvider, key: String) -> URLRequest? {
        guard let base = baseURL(for: provider) else { return nil }

        switch authStyle(for: provider.id) {
        case .anthropic:
            var request = URLRequest(url: base.appendingPathComponent("v1/models"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            // Required by Anthropic; omitting it is a 400, not a 401, which would read
            // to the user as a bad key.
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return request

        case .google:
            var request = URLRequest(url: base.appendingPathComponent("models"))
            // Google documents `?key=` as well, but a credential in a query string ends
            // up in URL logs, crash reports, and proxy access logs. The header does the
            // same job without that exposure.
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            return request

        case .bearer:
            var request = URLRequest(url: base.appendingPathComponent("models"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return request
        }
    }
}
