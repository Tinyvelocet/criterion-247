import Foundation

/// The "What's On Now" line parsed from the whatsonnow server-rendered page.
public struct NowPlayingLine: Codable, Equatable, Sendable {
    public let title: String
    /// The film page slug, e.g. "the-housemaid". Derives from the Criterion "More" link.
    public let slug: String
    /// Minutes until the next film starts (server-computed, integer-rounded).
    public let minutesUntilNext: Int
    /// Timestamp at which this snapshot was captured from the server.
    public let fetchedAt: Date

    public init(title: String, slug: String, minutesUntilNext: Int, fetchedAt: Date) {
        self.title = title
        self.slug = slug
        self.minutesUntilNext = minutesUntilNext
        self.fetchedAt = fetchedAt
    }
}

/// Metadata for a film, parsed from the Criterion film page + enriched by TMDB.
public struct FilmInfo: Codable, Equatable, Sendable {
    public var title: String
    public var director: String?
    public var year: Int?
    public var country: String?
    public var cast: [String]
    public var slug: String?

    /// Screenwriter / writer — from TMDB only.
    public var screenwriter: String?
    /// Runtime in seconds — from TMDB only.
    public var runtimeSeconds: Int?
    /// Poster / keyframe image URL.
    public var posterURL: String?
    /// Synopsis from the Criterion film page.
    public var synopsis: String?
    /// The slug the description was parsed from (for caching).
    public var sourceFetchURL: String?

    public init(
        title: String, director: String? = nil, year: Int? = nil,
        country: String? = nil, cast: [String] = [], slug: String? = nil,
        screenwriter: String? = nil, runtimeSeconds: Int? = nil,
        posterURL: String? = nil, synopsis: String? = nil, sourceFetchURL: String? = nil
    ) {
        self.title = title
        self.director = director
        self.year = year
        self.country = country
        self.cast = cast
        self.slug = slug
        self.screenwriter = screenwriter
        self.runtimeSeconds = runtimeSeconds
        self.posterURL = posterURL
        self.synopsis = synopsis
        self.sourceFetchURL = sourceFetchURL
    }
}

/// A fully-resolved snapshot of what is playing right now, used for shared
/// state storage (the single source of truth between the menu-bar app and widget).
public struct CriterionSnapshot: Codable, Equatable, Sendable {
    public var now: NowPlayingLine
    public var film: FilmInfo?
    /// Remaining time in the current film, seconds.
    public var remainingSeconds: Int
    /// Elapsed time in the current film, seconds.
    public var elapsedSeconds: Int
    public var phase: TrackerPhase
    public var lastUpdated: Date
    /// True when the last fetch failed; the UI should show an explicit offline state.
    public var isStale: Bool

    public init(
        now: NowPlayingLine, film: FilmInfo?, remainingSeconds: Int,
        elapsedSeconds: Int, phase: TrackerPhase, lastUpdated: Date, isStale: Bool
    ) {
        self.now = now
        self.film = film
        self.remainingSeconds = remainingSeconds
        self.elapsedSeconds = elapsedSeconds
        self.phase = phase
        self.lastUpdated = lastUpdated
        self.isStale = isStale
    }
}

public enum TrackerPhase: String, Codable, Sendable {
    /// More than 5 minutes remain in the current film.
    case normal
    /// Within 5 minutes of the end — UI should emphasize the transition.
    case finale

    public static func phase(remainingSeconds: Int) -> TrackerPhase {
        remainingSeconds <= 300 ? .finale : .normal
    }
}