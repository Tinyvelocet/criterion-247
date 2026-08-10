import SwiftUI
import CriterionData

/// The menu-bar icon + compact status line (visible without opening the menu).
struct MenuBarLabel: View {
    @ObservedObject var engine: TrackerEngine

    var body: some View {
        HStack(spacing: 4) {
            // Custom clapperboard template icon (tints for light/dark menu bar).
            Image("MenubarIcon")
                .renderingMode(.template)
                .foregroundStyle(engine.isFinale ? .orange : .primary)
            if let snap = engine.snapshot {
                Text(snap.now.title)
                    .lineLimit(1)
                Text(TimeFormat.minutes(engine.liveRemaining))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if engine.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Text("—")
            }
        }
        .font(.callout)
    }
}

/// The popover shown when the user clicks the menu-bar item.
struct MenuBarView: View {
    @ObservedObject var engine: TrackerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snap = engine.snapshot {
                // Poster header.
                if let poster = snap.film?.posterURL, let url = URL(string: poster) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.black
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        LiveBadge(isFinale: engine.isFinale)
                            .padding(8)
                    }
                } else {
                    Color.black.frame(height: 110)
                        .overlay(alignment: .topLeading) {
                            LiveBadge(isFinale: engine.isFinale).padding(8)
                        }
                }

                // Readout.
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.now.title)
                        .font(.title3).fontWeight(.bold)
                    if let film = snap.film {
                        Text(directorLine(film))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(film.cast.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.primary)
                        if let writer = film.screenwriter, !writer.isEmpty {
                            Text("Written by \(writer)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    // Progress.
                    HStack(spacing: 8) {
                        ProgressView(value: engine.progressFraction)
                            .tint(engine.isFinale ? .orange : .accentColor)
                        Text(TimeFormat.clock(engine.liveElapsed) + " / " + TimeFormat.clock(snap.film?.runtimeSeconds ?? 0))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("\(TimeFormat.minutes(engine.liveRemaining)) remaining")
                        .font(.caption).foregroundStyle(engine.isFinale ? .orange : .secondary)
                }
                .padding(12)
            } else {
                if let err = engine.lastError {
                    OfflineCard(message: err)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Contacting Criterion…")
                    }
                    .padding(16)
                }
            }

            Divider()
            // Footer
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    engine.openCriterionChannel()
                } label: {
                    Label("Watch Criterion 24/7", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.plain)

                HStack {
                    if let snap = engine.snapshot {
                        Text("Updated \(RelativeDateTimeFormatter().localizedString(for: snap.lastUpdated, relativeTo: Date()))")
                    }
                    Spacer()
                    Button("Refresh Now") { Task { await engine.refresh() } }
                        .buttonStyle(.link)
                }
                .font(.caption).foregroundStyle(.secondary)

                if let err = engine.lastError, engine.snapshot == nil {
                    Text("⚠️ \(err)")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(12)
        }
        .frame(width: 380)
    }

    private func directorLine(_ film: FilmInfo) -> String {
        var parts: [String] = []
        if let d = film.director { parts.append("Directed by \(d)") }
        var meta: [String] = []
        if let y = film.year { meta.append("\(y)") }
        if let c = film.country { meta.append(c) }
        if !meta.isEmpty { parts.append(meta.joined(separator: " · ")) }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }
}

struct LiveBadge: View {
    let isFinale: Bool
    var body: some View {
        Text(isFinale ? "● ENDING" : "● LIVE")
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(isFinale ? Color.black : .white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isFinale ? Color.orange : Color.green, in: Capsule())
    }
}

struct OfflineCard: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach the Criterion feed right now.").font(.caption).fontWeight(.semibold)
                Text(message).font(.caption2).foregroundStyle(.secondary)
                Text("Will retry in 10 min.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}