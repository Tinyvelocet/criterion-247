import AppKit
import SwiftUI

/// App delegate — used to enforce the single-instance rule at launch, before
/// the menu bar item is shown, so a duplicate never flashes up.
final class CriterionAppDelegate: NSObject, NSApplicationDelegate {
    /// Acquires the single-instance lock. Must be nonisolated-safe for the
    /// @MainActor launch path.
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstanceGuard.shared.acquire() else {
            // Another instance is already running. Bring it forward and quit.
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
    }

    /// Tries to bring the existing menu-bar app to the foreground.
    /// Menu-bar LSUIElement apps have no Dock icon/visible window, so the most
    /// useful habit is to summon their menu by activating the app.
    @MainActor
    private func activateExistingInstance() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}