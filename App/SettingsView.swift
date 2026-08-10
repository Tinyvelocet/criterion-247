import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: TrackerEngine

    var hasKey: Bool { (AppConfig.tmdbAPIKey ?? "").isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Criterion24/7").font(.title2).fontWeight(.bold)
            Text("Tracks what's playing on the Criterion Channel's 24/7 live feed.\nRuntime and screenwriter come from Wikidata automatically — no API key required. A TMDb key is fully optional, and only improves coverage of obscure films.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Group {
                Text("Metadata source").font(.headline)
                Label("Wikidata — automatic, no key", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)

                if hasKey {
                    Label("TMDb override — enabled for obscure-film coverage", systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Label("TMDb override — off", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Optional. To enable, get a free key at themoviedb.org and save it to: \(AppConfig.keyFileURL.path)")
                        .font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            HStack {
                Button("Refresh Now") { Task { await engine.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Spacer()
                if let snap = engine.snapshot {
                    Text("Now: \(snap.now.title) · \(TimeFormat.minutes(engine.liveRemaining))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}