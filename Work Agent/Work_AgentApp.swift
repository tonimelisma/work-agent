//
//  Work_AgentApp.swift
//  Work Agent
//
//  Created by Toni Melisma on 7/15/26.
//

import SwiftUI
import SwiftData

@main
struct Work_AgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Owned here so the Settings scene and the main window observe the same state.
    @State private var providerStore: ProviderStore
    @State private var registryLoader: RegistryLoader
    @State private var runtime: RuntimeEnvironment
    @State private var conversationsStore = ConversationsStore()

    init() {
        let providerStore = ProviderStore()
        let registryLoader = RegistryLoader()
        _providerStore = State(initialValue: providerStore)
        _registryLoader = State(initialValue: registryLoader)
        _runtime = State(initialValue: RuntimeEnvironment(store: providerStore, registryLoader: registryLoader))
    }

    var body: some Scene {
        // REQ: FR-068, FR-071 — the main window is a chat with a conversation sidebar.
        WindowGroup {
            ChatView()
                .environment(providerStore)
                .environment(registryLoader)
                .environment(runtime)
                .environment(conversationsStore)
                .onAppear { appDelegate.runtime = runtime }
        }
        .modelContainer(for: ConversationRecord.self)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // REQ: FR-050 — the idiomatic macOS home for this: ⌘, and the app menu.
        Settings {
            ProviderSettingsView()
                .environment(providerStore)
                .environment(registryLoader)
        }
    }
}
