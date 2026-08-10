import Foundation
import AppKit

/// Ensures only **one** instance of the menu-bar app runs at a time.
///
/// Uses a POSIX advisory file lock (`flock`) on a stable per-user file:
///  - The kernel releases the lock automatically when the owning process exits
///    (or crashes), so there is never a stale lock to clean up.
///  - `LOCK_EX | LOCK_NB` is an atomic test-and-set, so there is no
///    check-then-write race between two instances launching at once.
/// The winner holds the lock for its entire lifetime; any later instance fails
/// to acquire it and quits.
final class SingleInstanceGuard: @unchecked Sendable {
    static let shared = SingleInstanceGuard()

    private var lockFD: Int32 = -1
    private let lockURL: URL

    private init() {
        // Prefer the App Group container (available in both signed build paths);
        // fall back to a per-user Application Support dir.
        let base: URL
        if let groupDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        ) {
            base = groupDir.appendingPathComponent("instance", isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Criterion247",
                                         isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        lockURL = base.appendingPathComponent("single-instance.lock")
    }

    /// Attempts to take the single-instance lock.
    /// - Returns: `true` if THIS process owns it (proceed with launch), and
    ///   `false` if another instance already holds it (should quit now).
    func acquire() -> Bool {
        lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else {
            // Couldn't even open the lock file — fail open (don't block launch).
            return true
        }
        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // Another instance holds the lock. Close ours and signal "quit".
            close(lockFD)
            lockFD = -1
            return false
        }
        return true  // We own the lock for this process's lifetime.
    }

    /// Whether this process is the running instance (useful for an about row).
    var isPrimaryInstance: Bool { lockFD >= 0 }
}