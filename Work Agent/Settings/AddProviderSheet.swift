//
//  AddProviderSheet.swift
//  Work Agent
//
//  Add a provider by pasting its API key.
//

import SwiftUI

struct AddProviderSheet: View {
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedProviderID: String?
    @State private var apiKey = ""
    @State private var state: State = .editing

    private enum State: Equatable { case editing, verifying, failed(String) }

    /// Curated providers present in the registry and not already configured.
    private var available: [RegistryProvider] {
        guard let registry = registryLoader.registry else { return [] }
        return registry.curatedProviders().filter { !store.isConfigured($0.id) }
    }

    private var selectedProvider: RegistryProvider? {
        available.first { $0.id == selectedProviderID }
    }

    private var canSubmit: Bool {
        selectedProvider != nil
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && state != .verifying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Provider")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20).padding(.bottom, 12)

            Form {
                Picker("Provider", selection: $selectedProviderID) {
                    Text("Choose…").tag(String?.none)
                    ForEach(available) { provider in
                        Text(provider.name).tag(String?.some(provider.id))
                    }
                }
                .onChange(of: selectedProviderID) { _, _ in state = .editing }

                Section {
                    SecureField("API key", text: $apiKey)
                        .textContentType(.password)
                        .disabled(selectedProvider == nil)
                        .onChange(of: apiKey) { _, _ in state = .editing }
                    if let doc = selectedProvider?.doc {
                        Button("Where do I find this?") { openURL(doc) }
                            .buttonStyle(.link).font(.caption)
                    }
                } footer: {
                    // REQ: FR-052 — tell the user plainly where the key goes.
                    Text("Stored in your Mac's keychain, and only ever sent to \(selectedProvider?.name ?? "the provider").")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if state == .verifying {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
            .padding(12)
        }
        .frame(width: 460)
        .animation(.default, value: state)
        .task { if registryLoader.registry == nil { await registryLoader.loadLocal() } }
    }

    // REQ: FR-056 — verify the key against the provider before reporting it usable.
    // Block only on an explicit auth rejection; a verification endpoint that's simply
    // unreachable or shaped differently shouldn't reject a good key.
    private func submit() {
        guard let provider = selectedProvider else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .verifying

        Task {
            let result = await ProviderVerifier().verify(provider: provider, key: key)
            switch result {
            case .verified:
                store(provider, key)
            case .failed(.rejected), .failed(.forbidden):
                state = .failed(VerificationFailure.rejected.errorDescription ?? "That key was rejected.")
            case .failed:
                // Reachability/endpoint issue, not a bad key — save it; chat will surface
                // any real problem with a clear message.
                store(provider, key)
            }
        }
    }

    private func store(_ provider: RegistryProvider, _ key: String) {
        do {
            try store.add(providerID: provider.id, displayName: provider.name, key: key)
            dismiss()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
