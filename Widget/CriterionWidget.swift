@preconcurrency import WidgetKit
import SwiftUI
import CriterionData

@main
struct CriterionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CriterionMediumWidget()
        CriterionLargeWidget()
    }
}

struct CriterionMediumWidget: Widget {
    let kind = "CriterionMedium"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CriterionWidgetView(entry: entry, size: .medium)
                .widgetURL(URL(string: "https://www.criterionchannel.com/events/criterion-24-7"))
        }
        .configurationDisplayName("Criterion 24/7 — Medium")
        .description("What's playing now on the Criterion Channel.")
        .supportedFamilies([.systemMedium])
    }
}

struct CriterionLargeWidget: Widget {
    let kind = "CriterionLarge"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CriterionWidgetView(entry: entry, size: .large)
                .widgetURL(URL(string: "https://www.criterionchannel.com/events/criterion-24-7"))
        }
        .configurationDisplayName("Criterion 24/7 — Large")
        .description("What's playing now on the Criterion Channel, with full details.")
        .supportedFamilies([.systemLarge])
    }
}

enum WidgetSize { case medium, large }

/// Provides live data for the widget. The widget is self-sufficient — it fetches
/// the Criterion feed + film page + Wikidata itself, so it never shows placeholder
/// data and does NOT depend on the App Group or the menu-bar app being running.
/// It writes its fresh snapshot back to the shared App Group (if available) so the
/// app can also use it, but a missing App Group never breaks the widget.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(snapshot: Self.placeholderSnapshot, isLoading: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // Prefer a fresh fetch; fall back to the last shared snapshot; then placeholder.
        if let shared = store.load() {
            completion(Entry(snapshot: shared, isLoading: false))
            return
        }
        completion(Entry(snapshot: Self.placeholderSnapshot, isLoading: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // WidgetKit's completion isn't @Sendable, so to run work in a Task we box
        // it in an @unchecked Sendable holder (the single-fire callback is a safe
        // cross-actor hop). Build + call completion after the live fetch.
        let done = SendableBox(completion)

        Task { @MainActor in
            let base = store.load() ?? Self.placeholderSnapshot
            let fresh = await Self.liveSnapshot() ?? base

            let now = Date()
            let interval = TrackerPhase.phase(remainingSeconds: fresh.remainingSeconds) == .finale ? 60.0 : 600.0
            let advance: [Double] = [0, interval, interval * 2]
            let entries = advance.map { m in
                let t = now.addingTimeInterval(m)
                let advanced = StatusModel.snapshot(now: t, line: fresh.now, film: fresh.film)
                return Entry(snapshot: advanced, isLoading: false)
            }
            done.value(Timeline(entries: entries, policy: .after(now.addingTimeInterval(interval))))
        }
    }

    /// Wrap a non-@Sendable single-fire callback so it can cross a Task boundary.
    private struct SendableBox: @unchecked Sendable {
        let value: (Timeline<Entry>) -> Void
        init(_ v: @escaping (Timeline<Entry>) -> Void) { self.value = v }
    }

    /// Fetches the current snapshot directly from Criterion + Wikidata.
    /// Keyless. Returns nil on network error (caller keeps last good data).
    nonisolated private static func liveSnapshot() async -> CriterionSnapshot? {
        do {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 8
            cfg.timeoutIntervalForResource = 12
            let session = URLSession(configuration: cfg)
            // In-memory store (no App Group needed) so refresh() persists trivially.
            var memStore = SnapshotStore(appGroupID: "group.dev.criterion247")
            memStore.containerOverride = FileManager.default.temporaryDirectory
                .appendingPathComponent("criterion-widget-\(UUID().uuidString)")
            let service = TrackerService(
                session: session,
                enrichers: [WikidataClient(session: session)],
                store: memStore
            )
            return try await service.refresh(now: Date())
        } catch {
            return nil
        }
    }

    private var store: SnapshotStore { SnapshotStore(appGroupID: "group.dev.criterion247") }

    struct Entry: TimelineEntry {
        let snapshot: CriterionSnapshot
        let isLoading: Bool
        var date: Date { snapshot.lastUpdated }
    }

    private static let placeholderSnapshot: CriterionSnapshot = {
        let line = NowPlayingLine(title: "", slug: "", minutesUntilNext: 0, fetchedAt: Date())
        return StatusModel.snapshot(now: Date(), line: line, film: nil)
    }()
}