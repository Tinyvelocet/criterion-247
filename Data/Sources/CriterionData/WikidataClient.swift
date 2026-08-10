import Foundation

/// A protocol both enrich-int sources conform to, so the app can prefer
/// Wikidata (keyless) and optionally overlay TMDb for obscure-film coverage.
public protocol FilmEnricher: Sendable {
    /// Fills missing runtimeSeconds / screenwriter on `film`. Must not throw
    /// on "not found" — it should return without modifying those fields.
    func enrich(film: inout FilmInfo, year: Int?) async
}

/// Keyless enrichment from Wikidata (public SPARQL endpoint — no API key).
///
/// Strategy:
///  1. `wbsearchentities` fuzzy-search for the title → candidate item QIDs.
///  2. One SPARQL `VALUES` query fetches runtime (P2047), screenwriter (P58),
///     instance-of, and year for all candidates.
///  3. Pick the candidate that is a *film* (Q11424) and (when the year is known)
///     whose publication year matches.
public struct WikidataClient: FilmEnricher, Sendable {
    public var session: URLSession
    private let searchAPI = URL(string: "https://www.wikidata.org/w/api.php")!
    private let sparql = URL(string: "https://query.wikidata.org/sparql")!
    private let filmTypeID = "Q11424"
    private let userAgent = "Criterion247-dev/1.0 (open-source; contact via project issues)"

    public init(session: URLSession = .init(configuration: .ephemeral)) {
        self.session = session
    }

    public func enrich(film: inout FilmInfo, year: Int?) async {
        // 1. Find candidate QIDs.
        let qids = await searchQIDs(title: film.title)
        guard !qids.isEmpty else { return }

        // 2. Fetch metadata for all candidates in one query.
        let rows = await fetchMetadata(qids: qids)
        guard let best = chooseBest(rows: rows, title: film.title, year: year) else { return }

        if film.runtimeSeconds == nil, let r = best.runtime { film.runtimeSeconds = r }
        if film.screenwriter == nil, let w = best.writer, !w.isEmpty { film.screenwriter = w }
    }

    // MARK: - steps

    struct CandidateRow {
        let id: String
        let isFilm: Bool
        let runtime: Int?
        let writer: String?
        let year: Int?
    }

    private func searchQIDs(title: String) async -> [String] {
        var comps = URLComponents(url: searchAPI, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: title),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "uselang", value: "en"),
            URLQueryItem(name: "type", value: "item"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "format", value: "json"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        struct Resp: Decodable { let search: [Hit]? }
        struct Hit: Decodable { let id: String }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        return r.search?.map(\.id) ?? []
    }

    private func fetchMetadata(qids: [String]) async -> [CandidateRow] {
        let values = qids.map { "wd:\($0)" }.joined(separator: " ")
        let query = """
        PREFIX wd: <http://www.wikidata.org/entity/>
        PREFIX wdt: <http://www.wikidata.org/prop/direct/>
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT ?film ?filmType ?runtime ?writerLabel ?date WHERE {
          VALUES ?film { \(values) }
          ?film rdfs:label ?filmLabel .
          FILTER(LANG(?filmLabel) = "en")
          OPTIONAL { ?film wdt:P31 ?type . BIND(STRAFTER(STR(?type), STR(wd:)) AS ?filmType) }
          OPTIONAL { ?film wdt:P2047 ?runtime . }
          OPTIONAL { ?film wdt:P58 ?writer . }
          OPTIONAL { ?film wdt:P577 ?date . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 50
        """
        var comps = URLComponents(url: sparql, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: query),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request) else { return [] }

        struct Resp: Decodable {
            let results: Bindings
            struct Bindings: Decodable { let bindings: [Binding]? }
            struct Binding: Decodable {
                let film: Value?
                let filmType: Value?
                let runtime: Value?
                let writerLabel: Value?
                let date: Value?
                struct Value: Decodable { let value: String }
            }
        }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        return (r.results.bindings ?? []).map { b in
            CandidateRow(
                id: (b.film?.value).map { $0.split(separator: "/").last.map(String.init) ?? $0 } ?? "",
                isFilm: b.filmType?.value == filmTypeID,
                runtime: b.runtime.flatMap { Int($0.value) }.map { $0 * 60 },
                writer: b.writerLabel?.value,
                year: b.date.flatMap { d in Int(d.value.prefix(4)) }
            )
        }
    }

    private func chooseBest(rows: [CandidateRow], title: String, year: Int?) -> CandidateRow? {
        // Prefer films (P31 = Q11424) whose year matches; then any film; then any row.
        let films = rows.filter { $0.isFilm }
        if let year {
            if let hit = films.first(where: { $0.year == year }), hasData(hit) { return hit }
            if let hit = films.first, hasData(hit) { return hit }
        } else if let hit = films.first, hasData(hit) {
            return hit
        }
        // Fallback: a non-film row carrying runtime is better than nothing.
        return rows.first(where: { hasData($0) })
    }

    private func hasData(_ row: CandidateRow) -> Bool {
        row.runtime != nil || (row.writer != nil && !row.writer!.isEmpty)
    }
}