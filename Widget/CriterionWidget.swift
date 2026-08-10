import WidgetKit
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
                .containerBackground(for: .widget) { Color(red: 0.06, green: 0.06, blue: 0.08) }
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
                .containerBackground(for: .widget) { Color(red: 0.06, green: 0.06, blue: 0.08) }
        }
        .configurationDisplayName("Criterion 24/7 — Large")
        .description("What's playing now on the Criterion Channel, with full details.")
        .supportedFamilies([.systemLarge])
    }
}

enum WidgetSize { case medium, large }

/// Single provider serving both widget kinds from the shared snapshot.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        placeholderEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(snapshot: store.load() ?? Self.placeholderSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Read the latest shared snapshot. The menu-bar app is the source of
        // truth and nudges reloads on film change; we also schedule a reload
        // within ~10 minutes so the countdown stays plausible even if the app
        // hasn't pushed a new snapshot.
        let snap = store.load() ?? Self.placeholderSnapshot
        let entries: [Entry]
        if let runtime = snap.film?.runtimeSeconds, runtime > 0, snap.now.minutesUntilNext > 0 {
            // Advance the countdown at a few future timestamps so the progress
            // bar doesn't go stale on the widget's system-controlled refresh.
            let now = Date()
            let minutes: [Int] = [0, 5, 10]
            entries = minutes.map { m in
                let t = now.addingTimeInterval(Double(m * 60))
                let advanced = StatusModel.snapshot(
                    now: t, line: snap.now, film: snap.film
                )
                return Entry(snapshot: advanced)
            }
        } else {
            entries = [Entry(snapshot: snap)]
        }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(600))))
    }

    private var store: SnapshotStore { SnapshotStore(appGroupID: "group.dev.criterion247") }
    private var placeholderEntry: Entry { Entry(snapshot: Self.placeholderSnapshot) }

    struct Entry: TimelineEntry {
        let snapshot: CriterionSnapshot
        var date: Date { snapshot.lastUpdated }
    }

    private static let placeholderSnapshot: CriterionSnapshot = {
        let line = NowPlayingLine(title: "The Housemaid", slug: "the-housemaid",
                                  minutesUntilNext: 12, fetchedAt: Date())
        let film = FilmInfo(title: "The Housemaid", director: "Kim Ki-young", year: 1960,
                            country: "South Korea",
                            cast: ["Kim Jin-kyu", "Ju Jung-nyeo", "Lee Eun-shim"],
                            screenwriter: "Kim Ki-young", runtimeSeconds: 6660)
        return StatusModel.snapshot(now: Date(), line: line, film: film)
    }()
}