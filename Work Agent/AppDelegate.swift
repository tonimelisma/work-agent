//
//  AppDelegate.swift
//  Work Agent
//
//  REQ: FR-072 — when the app quits with a run in flight, the run pauses at its
//  next safe checkpoint rather than being silently killed mid-stream.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var runtime: RuntimeEnvironment?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime else { return .terminateNow }
        runtime.pauseAllActiveRunsForTermination()
        Task { @MainActor in
            // A brief window for the cancelled runs' checkpoints to reach disk
            // before the process actually exits.
            try? await Task.sleep(for: .milliseconds(500))
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
