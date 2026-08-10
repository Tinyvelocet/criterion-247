import Foundation

/// Computes the derived "now" state for a given reference time.
/// Pure logic, no I/O — the single place time-to-elapsed math lives.
public enum StatusModel {
    /// Seconds remaining in the current film at `now`, given the server-provided
    /// countdown captured at `line.fetchedAt`.
    /// The countdown is an integer minute boundary at fetch time; the countdown
    /// decreases as wall-clock time passes.
    public static func remainingSeconds(now: Date, line: NowPlayingLine) -> Int {
        let elapsedSinceFetch = max(0, now.timeIntervalSince(line.fetchedAt))
        let atFetch = Double(line.minutesUntilNext * 60)
        return max(0, Int(atFetch - elapsedSinceFetch))
    }

    /// Elapsed seconds in the film, given an (optional) runtime.
    /// Returns nil when runtime is unknown.
    public static func elapsedSeconds(remaining: Int, runtimeSeconds: Int?) -> Int? {
        guard let runtime = runtimeSeconds else { return nil }
        return max(0, runtime - remaining)
    }

    /// Builds a full snapshot for the current reference time.
    public static func snapshot(
        now: Date, line: NowPlayingLine, film: FilmInfo?
    ) -> CriterionSnapshot {
        let remaining = remainingSeconds(now: now, line: line)
        let runtime = film?.runtimeSeconds
        let elapsed = elapsedSeconds(remaining: remaining, runtimeSeconds: runtime)
        return CriterionSnapshot(
            now: line,
            film: film,
            remainingSeconds: remaining,
            elapsedSeconds: elapsed ?? 0,
            phase: TrackerPhase.phase(remainingSeconds: remaining),
            lastUpdated: now,
            isStale: false
        )
    }
}