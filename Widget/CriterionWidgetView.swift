import WidgetKit
import SwiftUI
import CriterionData

/// Shared rendering for both widget sizes. Background applied exactly once here.
struct CriterionWidgetView: View {
    let entry: Provider.Entry
    let size: WidgetSize

    var body: some View {
        Group {
            if entry.isLoading || entry.snapshot.now.title.isEmpty {
                LoadingState(size: size)
            } else if let film = entry.snapshot.film {
                switch size {
                case .small: SmallLayout(snapshot: entry.snapshot, film: film)
                case .medium: MediumLayout(snapshot: entry.snapshot, film: film)
                case .large: LargeLayout(snapshot: entry.snapshot, film: film)
                }
            } else {
                // Film metadata pending, but title is real.
                Text(entry.snapshot.now.title)
                    .font(size == .small ? .headline : .title3)
                    .fontWeight(.bold).foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.05, green: 0.05, blue: 0.07) }
    }
}

/// Shown while the first live fetch is in flight (never an invented film).
private struct LoadingState: View {
    let size: WidgetSize
    @State private var spin = false
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "film")
                .font(size == .small ? .body : .title2)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spin = true } }
            Text("Checking Criterion…")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PosterHeader: View {
    let film: FilmInfo
    let isFinale: Bool
    var body: some View {
        GeometryReader { geo in
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
                .frame(width: geo.size.width, height: geo.size.height)

                LinearGradient(colors: [.clear, Color(red: 0.05, green: 0.05, blue: 0.07)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)

                Text(isFinale ? "● ENDING" : "● LIVE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isFinale ? .black : .white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(isFinale ? .orange : .green, in: Capsule())
                    .padding(10)
            }
        }
    }
}

private struct ProgressRow: View {
    let elapsed: Int
    let runtime: Int
    let remaining: Int
    let isFinale: Bool
    var body: some View {
        VStack(spacing: 5) {
            ProgressView(value: runtime > 0 ? Double(elapsed) / Double(runtime) : 0)
                .tint(isFinale ? .orange : .white)
            HStack(alignment: .firstTextBaseline) {
                Text(clock(elapsed) + " / " + clock(runtime))
                    .font(.caption2).monospacedDigit()
                Spacer(minLength: 4)
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

// MARK: - Layouts

/// Compact, overflow-safe via `ViewThatFits`: if the content won't fit the fixed
/// box it degrades (larger poster → smaller) rather than clamping/spilling.
private struct MediumLayout: View {
    let snapshot: CriterionSnapshot
    let film: FilmInfo
    private var isFinale: Bool {
        TrackerPhase.phase(remainingSeconds: snapshot.remainingSeconds) == .finale
    }
    var body: some View {
        ViewThatFits(in: .vertical) {
            full
            compact
        }
    }
    private var full: some View {
        VStack(spacing: 6) {
            PosterHeader(film: film, isFinale: isFinale).frame(height: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.now.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(crumbLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(film.cast.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
        }
        .padding(12)
    }
    private var compact: some View {
        VStack(spacing: 6) {
            PosterHeader(film: film, isFinale: isFinale).frame(height: 70)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.now.title).font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white).lineLimit(1)
                Text(crumbLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
        }
        .padding(10)
    }
    private var crumbLine: String {
        let d = film.director ?? ""
        let y = film.year.map(String.init) ?? ""
        let c = film.country ?? ""
        return [d, y, c].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct LargeLayout: View {
    let snapshot: CriterionSnapshot
    let film: FilmInfo
    private var isFinale: Bool {
        TrackerPhase.phase(remainingSeconds: snapshot.remainingSeconds) == .finale
    }
    var body: some View {
        ViewThatFits(in: .vertical) {
            full
            compact
        }
    }
    private var full: some View {
        VStack(spacing: 8) {
            PosterHeader(film: film, isFinale: isFinale).frame(height: 130)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.now.title).font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white).lineLimit(1)
                Text(crumbLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(film.cast.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                if let writer = film.screenwriter, !writer.isEmpty {
                    Text("Written by \(writer)")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
        }
        .padding(14)
    }
    private var compact: some View {
        VStack(spacing: 6) {
            PosterHeader(film: film, isFinale: isFinale).frame(height: 90)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.now.title).font(.headline).fontWeight(.bold)
                    .foregroundStyle(.white).lineLimit(1)
                Text(crumbLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
        }
        .padding(10)
    }
    private var crumbLine: String {
        let d = film.director ?? ""
        let y = film.year.map(String.init) ?? ""
        let c = film.country ?? ""
        return [d, y, c].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
/// Compact square layout — small poster + title + tiny details. Fits a standard
/// systemSmall tile without overflowing.
private struct SmallLayout: View {
    let snapshot: CriterionSnapshot
    let film: FilmInfo
    private var isFinale: Bool {
        TrackerPhase.phase(remainingSeconds: snapshot.remainingSeconds) == .finale
    }
    var body: some View {
        VStack(spacing: 6) {
            PosterHeader(film: film, isFinale: isFinale).frame(height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.now.title)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.white).lineLimit(1)
                Text(crumbLine)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressRow(elapsed: snapshot.elapsedSeconds,
                        runtime: film.runtimeSeconds ?? snapshot.elapsedSeconds,
                        remaining: snapshot.remainingSeconds, isFinale: isFinale)
        }
        .padding(8)
    }
    private var crumbLine: String {
        let d = film.director ?? ""
        let y = film.year.map(String.init) ?? ""
        let c = film.country ?? ""
        return [d, y, c].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
