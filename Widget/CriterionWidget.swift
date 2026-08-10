@preconcurrency import WidgetKit
import SwiftUI
import CriterionData

@main
struct CriterionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CriterionSmallWidget()
        CriterionMediumWidget()
        CriterionLargeWidget()
    }
}

struct CriterionSmallWidget: Widget {
    let kind = "CriterionSmall"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CriterionWidgetView(entry: entry, size: .small)
                .widgetURL(URL(string: "https://www.criterionchannel.com/events/criterion-24-7"))
        }
        .configurationDisplayName("Criterion 24/7 — Small")
        .description("A compact view of what's playing now.")
        .supportedFamilies([.systemSmall])
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

enum WidgetSize { case small, medium, large }

/// Provides data for the widget.
///
/// Source of truth = the shared App Group snapshot written by the menu-bar app.
/// The widget is a READER: it loads that snapshot and simply advances the
/// countdown from wall-clock using the same `fetchedAt`/`minutesUntilNext`
/// anchor the menu bar uses — so widget and menu bar always agree on the film
/// and the time remaining. It only does its own fetch as a LAST-RESORT fallback
/// when there is no shared snapshot at all (e.g. App Group not provisioned).
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(snapshot: Self.placeholderSnapshot, isLoading: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if let shared = store.load() {
            completion(Entry(snapshot: shared, isLoading: false))
        } else {
            completion(Entry(snapshot: Self.placeholderSnapshot, isLoading: true))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // WidgetKit's completion isn't @Sendable, so we box it to cross the Task.
        let done = SendableBox(completion)

        Task { @MainActor in
            let now = Date()

            // 1. The shared snapshot IS the source of truth (what the menu bar
            //    shows). Use it directly — do not re-fetch, so we stay in sync.
            var snap = store.load()

            // 2. Last-resort: only if there's no shared snapshot (first run, or
            //    no App Group) do a one-shot live fetch so the widget isn't blank.
            if snap == nil {
                snap = await Self.liveSnapshot()
            }

            guard let snap else {
                done.value(Timeline(
                    entries: [Entry(snapshot: Self.placeholderSnapshot, isLoading: true)],
                    policy: .after(now.addingTimeInterval(600))))
                return
            }

            // 3. Advance the SAME snapshot's countdown via wall-clock — this is
            //    exactly how the menu bar computes it, guaranteeing agreement.
            let remaining = StatusModel.remainingSeconds(now: now, line: snap.now)
            let interval = TrackerPhase.phase(remainingSeconds: remaining) == .finale ? 60.0 : 600.0
            let advance: [Double] = [0, interval, interval * 2, interval * 3]
            let entries = advance.map { m in
                let t = now.addingTimeInterval(m)
                let advanced = StatusModel.snapshot(now: t, line: snap.now, film: snap.film)
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