import Foundation

/// TMDb enrichment client. Provides runtime (details) and screenwriter (crew).
/// API: https://developer.themoviedb.org/reference
///  - GET /3/search/movie?query=…&year=…&api_key=…
///  - GET /3/movie/{id}            -> runtime (minutes)
///  - GET /3/movie/{id}/credits    -> crew (Writer), produced_by
public struct TMDbClient: FilmEnricher, Sendable {
    public var apiKey: String
    public var session: URLSession
    private let base = "https://api.themoviedb.org/3"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public struct Movie: Decodable, Sendable {
        public let id: Int
        public let title: String
        public let release_date: String?
        public var runtime: Int?
        public var writer: String?
    }

    /// Enriches a `FilmInfo` with runtime + screenwriter from TMDb.
    /// Falls back gracefully: does not throw on "not found" or network failure.
    public func enrich(film: inout FilmInfo, year: Int?) async {
        guard let match = try? await search(title: film.title, year: year) else {
            return
        }
        if film.runtimeSeconds == nil {
            if let runtime = match.runtime {
                film.runtimeSeconds = runtime * 60
            }
        }
        if film.screenwriter == nil, let writer = match.writer {
            film.screenwriter = writer
        }
    }

    // MARK: - Internals

    func search(title: String, year: Int?) async throws -> Movie? {
        var comps = URLComponents(string: base + "/search/movie")!
        var items = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        comps.queryItems = items

        guard let url = comps.url else { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            // TMDb unreachable / error (e.g. no API key). Degrade gracefully.
            return nil
        }
        struct Results: Decodable { let results: [MovieRef] }
        struct MovieRef: Decodable { let id: Int; let title: String; let release_date: String? }
        guard let decoded = try? JSONDecoder().decode(Results.self, from: data),
              let top = decoded.results.first else { return nil }

        var movie = Movie(id: top.id, title: top.title, release_date: top.release_date)
        async let details = loadDetails(id: top.id)
        async let credits = loadCredits(id: top.id)
        let (runtime, writer) = await (details, credits)
        movie.runtime = runtime
        movie.writer = writer
        return movie
    }

    private func loadDetails(id: Int) async -> Int? {
        var comps = URLComponents(string: base + "/movie/\(id)")!
        comps.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let (data, _) = try? await session.data(from: comps.url!) else { return nil }
        struct D: Decodable { let runtime: Int? }
        return (try? JSONDecoder().decode(D.self, from: data))?.runtime
    }

    private func loadCredits(id: Int) async -> String? {
        var comps = URLComponents(string: base + "/movie/\(id)/credits")!
        comps.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let (data, _) = try? await session.data(from: comps.url!) else { return nil }
        struct C: Decodable { let crew: [CrewMember] }
        struct CrewMember: Decodable { let name: String; let job: String?; let department: String? }
        guard let c = try? JSONDecoder().decode(C.self, from: data) else { return nil }
        // Prefer the "Writer"/"Screenplay" job in the Writing department.
        return c.crew.first(where: {
            $0.job?.lowercased() == "writer" || $0.job?.lowercased() == "screenplay"
        })?.name
        ?? c.crew.first(where: { $0.department == "Writing" && $0.job != nil })?.name
    }
}