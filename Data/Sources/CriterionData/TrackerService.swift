import Foundation

/// Orchestrates one full refresh: fetch the feed, parse it, fetch the film page
/// (only when the title changed), enrich via TMDb if needed, and persist.
/// The menu-bar app drives a timer that calls `refresh()` at 10-min / 1-min cadence.
public struct TrackerService: Sendable {
    public let session: URLSession
    public let enrichers: [FilmEnricher]
    public let store: SnapshotStore
    public var filmPageURL: @Sendable (String) -> URL

    public init(
        session: URLSession = .init(configuration: .ephemeral),
        enrichers: [FilmEnricher],
        store: SnapshotStore,
        filmPageURL: @escaping @Sendable (String) -> URL = { slug in
            URL(string: "https://www.criterionchannel.com/\(slug)")!
        }
    ) {
        self.session = session
        self.enrichers = enrichers
        self.store = store
        self.filmPageURL = filmPageURL
    }

    public enum Result {
        case updated(CriterionSnapshot)
        case unchanged(CriterionSnapshot)
    }

    /// Performs one refresh cycle and persists the new snapshot.
    /// Returns the resulting snapshot.
    public func refresh(now: Date = Date()) async throws -> CriterionSnapshot {
        // 1. Fetch + parse the what's-on-now page.
        let (feedData, _) = try await session.data(from: CriterionClient.baseURL)
        let feedHTML = String(decoding: feedData, as: UTF8.self)
        let line = try CriterionClient.parseNowPlaying(feedHTML, fetchedAt: now)

        // 2. Determine the previous film to decide whether to re-fetch the film page.
        let previous = store.load()
        let previousTitle = previous?.now.title
        let filmChanged = previousTitle != nil && previousTitle != line.title

        var film: FilmInfo?
        if filmChanged || previous?.film == nil {
            // Fresh fetch: get the film page + TMDb enrichment.
            film = try await loadFilm(line: line)
        } else {
            // Same film: keep previously-enriched metadata, just re-anchor the countdown.
            film = previous?.film
        }

        // 3. Build the snapshot with elapsed math.
        let snapshot = StatusModel.snapshot(now: now, line: line, film: film)

        // 4. Persist to the shared store (source of truth for the widget).
        try store.save(snapshot)
        return snapshot
    }

    private func loadFilm(line: NowPlayingLine) async throws -> FilmInfo? {
        guard !line.slug.isEmpty else { return nil }
        let url = filmPageURL(line.slug)
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        let html = String(decoding: data, as: UTF8.self)
        var film = try FilmPageParser.parse(html, title: line.title)
        // Run the enrichment chain (Wikidata keyless default; TMDb optional
        // override). Each enricher is graceful and only fills missing fields.
        for enricher in enrichers {
            await enricher.enrich(film: &film, year: film.year)
        }
        return film
    }
}