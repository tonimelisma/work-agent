//
//  Work_AgentApp.swift
//  Work Agent
//
//  Created by Toni Melisma on 7/15/26.
//

import SwiftUI

@main
struct Work_AgentApp: App {
    // Owned here so the Settings scene and the main window observe the same state.
    @State private var providerStore = ProviderStore()
    @State private var registryLoader = RegistryLoader()

    var body: some Scene {
        // REQ: FR-068 — the main window is the chat.
        WindowGroup {
            ChatView()
                .environment(providerStore)
                .environment(registryLoader)
        }
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
