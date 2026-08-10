import Foundation
import AppKit
import CriterionData
import WidgetKit

/// The source of truth. Owns the polling schedule, runs `TrackerService`,
/// and persists the latest snapshot for the widget.
///
/// Refresh cadence (per spec):
///  - 10 minutes normally,
///  - 1 minute when inside the last 5 minutes of the current film (finale phase),
///  - re-arms to 10 minutes once a new film starts.
@MainActor
final class TrackerEngine: ObservableObject {
    @Published var snapshot: CriterionSnapshot?
    @Published var lastError: String?
    @Published var isRefreshing = false

    private let store: SnapshotStore
    private var service: TrackerService?
    private var timer: Timer?
    private var clock: Timer?
    private var currentInterval: TimeInterval = 600

    /// Ticks every second so the menu-bar clock and progress advance live
    /// between server polls (which stay on the defined 10-min/1-min cadence).
    @Published var now = Date()

    init() {
        let appGroup = AppConfig.appGroupID
        self.store = SnapshotStore(appGroupID: appGroup)

        // Recover the last snapshot immediately for fast first render.
        if let snap = store.load() {
            self.snapshot = snap
        }

        rebuildService()
        // Kick off an immediate refresh, then start the adaptive timer.
        Task { await refresh() }
        startTimer(interval: 600)
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    private func rebuildService() {
        // Enrichment chain: Wikidata always runs (keyless). If a TMDb key is
        // configured, it runs after as an optional gap-fill for obscure films.
        var enrichers: [FilmEnricher] = [WikidataClient(session: session)]
        if let key = AppConfig.tmdbAPIKey, !key.isEmpty {
            enrichers.append(TMDbClient(apiKey: key, session: session))
        }
        self.service = TrackerService(
            session: session,
            enrichers: enrichers,
            store: store,
            filmPageURL: { URL(string: "https://www.criterionchannel.com/\($0)")! }
        )
    }

    private var session: URLSession { .init(configuration: .ephemeral) }

    // MARK: - Polling

    func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard let service else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snap = try await service.refresh(now: Date())
            self.snapshot = snap
            self.lastError = nil

            // Adaptive cadence: 1-min in finale, else 10-min.
            let newInterval: TimeInterval = snap.phase == .finale ? 60 : 600
            if newInterval != currentInterval {
                startTimer(interval: newInterval)
            }

            // Nudge the widget to reload now that state changed.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Variety/metadata computed for convenient display across surfaces.
    var progressFraction: Double {
        guard let snap = snapshot,
              let runtime = snap.film?.runtimeSeconds, runtime > 0 else { return 0 }
        return min(1, Double(liveElapsed) / Double(runtime))
    }

    /// Remaining time, advanced live from the last fetch using the ticking clock.
    var liveRemaining: Int {
        guard let snap = snapshot else { return 0 }
        return StatusModel.remainingSeconds(now: now, line: snap.now)
    }

    var liveElapsed: Int {
        guard let snap = snapshot, let runtime = snap.film?.runtimeSeconds else { return 0 }
        return StatusModel.elapsedSeconds(remaining: liveRemaining, runtimeSeconds: runtime) ?? 0
    }

    var isFinale: Bool {
        guard snapshot != nil else { return false }
        return TrackerPhase.phase(remainingSeconds: liveRemaining) == .finale
    }

    func openCriterionChannel() {
        NSWorkspace.shared.open(URL(string: "https://www.criterionchannel.com/events/criterion-24-7")!)
    }
}

// MARK: - Shared formatting (used by menu bar + widget)

enum TimeFormat {
    /// "58:00" or "1:51:00"
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// "12m left" / "3m left"
    static func minutes(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return "\(m)m left"
    }
}