// REQ: the provider-namespaced metadata key
// convention failover stripping keys on. Shared between Executors (which writes
// it) and Recorder's TranscriptArchive (which reads it to decide what survives
// a provider switch), so neither has to depend on the other for one string constant.
public enum TranscriptMetadataKeys {
    public static let signatureProvider = "neutral.signature_provider"
}
