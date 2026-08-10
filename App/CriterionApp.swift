import SwiftUI
import AppKit
import CriterionData

@main
struct CriterionApp: App {
    @NSApplicationDelegateAdaptor(CriterionAppDelegate.self) private var appDelegate
    @StateObject private var engine = TrackerEngine()

    init() {
        // Enforce single-instance BEFORE the body/@StateObject is first touched,
        // so a duplicate never starts the engine, never polls, and never shows a
        // second menu-bar item. The lock is held for this process's lifetime.
        guard SingleInstanceGuard.shared.acquire() else {
            // Let the delegate attempt to surface the existing instance, then quit.
            NSLog("Criterion24/7: another instance is already running — launching this one.")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }
}