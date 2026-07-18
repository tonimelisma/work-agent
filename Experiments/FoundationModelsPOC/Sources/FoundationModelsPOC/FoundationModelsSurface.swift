import FoundationModels

/// Compile-time proof that this isolated target links the macOS 27 provider surface.
/// Production targets do not import FoundationModels during this spike.
@available(macOS 27.0, *)
public enum FoundationModelsSurface {
    public static let requiredCapabilities = LanguageModelCapabilities(
        capabilities: [.reasoning, .toolCalling]
    )
}
