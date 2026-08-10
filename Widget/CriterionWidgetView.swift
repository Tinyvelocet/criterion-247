import WidgetKit
import SwiftUI
import CriterionData

/// Shared rendering for both widget sizes.
struct CriterionWidgetView: View {
    let entry: Provider.Entry
    let size: WidgetSize

    var body: some View {
        if let film = entry.snapshot.film {
            switch size {
            case .medium: MediumLayout(snapshot: entry.snapshot, film: film)
            case .large: LargeLayout(snapshot: entry.snapshot, film: film)
            }
        } else {
            // No metadata yet — show a condensed fallback rather than empty.
            Text(entry.snapshot.now.title)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }
}

private struct PosterHeader: View {
    let film: FilmInfo
    let isFinale: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = film.posterURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            LinearGradient(colors: [.black.opacity(0.6), .black],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    }
                } else {
                    LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.15), .black],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(colors: [.clear, Color(red: 0.06, green: 0.06, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)

            Text(isFinale ? "● ENDING" : "● LIVE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFinale ? .black : .white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isFinale ? .orange : .green, in: Capsule())
                .padding(12)
        }
    }
}

private struct ProgressRow: View {
    let elapsed: Int
    let runtime: Int
    let remaining: Int
    let isFinale: Bool
    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: runtime > 0 ? Double(elapsed) / Double(runtime) : 0)
                .tint(isFinale ? .orange : .white)
            HStack {
                Text(clock(elapsed) + " / " + clock(runtime))
                    .font(.caption2).monospacedDigit()
                Spacer()
                Text("\(max(0, remaining) / 60) min left")
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(isFinale ? .orange : .secondary)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private func clock(_ s: Int) -> String {
    let s = max(0, s)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

private struct MediumLayout: View {
    let snapshot: CriterionSnapshot
    let film: FilmInfo
    private var isFinale: Bool {
        TrackerPhase.phase(remainingSeconds: snapshot.remainingSeconds) == .finale
    }
    var body: some View {
        VStack(spacing: 0) {
            PosterHeader(film: film, isFinale: isFinale)
                .frame(height: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.now.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text("Directed by \(film.director ?? "") · \(film.year.map(String.init) ?? "") · \(film.country ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(film.cast.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 10)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

private struct LargeLayout: View {
    let snapshot: CriterionSnapshot
    let film: FilmInfo
    private var isFinale: Bool {
        TrackerPhase.phase(remainingSeconds: snapshot.remainingSeconds) == .finale
    }
    var body: some View {
        VStack(spacing: 0) {
            PosterHeader(film: film, isFinale: isFinale)
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.now.title).font(.title2).fontWeight(.bold).foregroundStyle(.white).lineLimit(1)
                Text("Directed by \(film.director ?? "") · \(film.year.map(String.init) ?? "") · \(film.country ?? "")")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(film.cast.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                if let writer = film.screenwriter, !writer.isEmpty {
                    Text("Written by \(writer)")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 12)
            Spacer(minLength: 4)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .containerBackground(for: .widget) { Color(red: 0.06, green: 0.06, blue: 0.08) }
    }
}