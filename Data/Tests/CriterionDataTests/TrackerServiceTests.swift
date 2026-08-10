import XCTest
@testable import CriterionData

final class TrackerServiceTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func json(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

    /// A feed page with a 12-minute countdown.
    private let feedHTML = """
    <html><body>
    <h2 class="whatson__title">The Housemaid</h2>
    <a href="https://www.criterionchannel.com/the-housemaid" class="whatson__channel-link whatson__channel-link--more">More</a>
    <p class="whatson__eyebrow">Next film starts in: <span class="whatson__eyebrow--bold">12 minutes</span></p>
    </body></html>
    """

    /// A distilled film page.
    private let filmHTML = """
    <head><meta name="description" content="Series
    Directed by Kim Ki-young • 1960 • South Korea
    Starring Kim Jin-kyu, Ju Jung-nyeo, Lee Eun-shim
    A film synopsis.
    "><link rel="canonical" href="https://www.criterionchannel.com/the-housemaid">
    </head>
    """

    func testFullRefreshPipelineProducesEnrichedSnapshot() async throws {
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if path == "/" || path.isEmpty {
                return (resp, Data(self.feedHTML.utf8))
            } else if path == "/the-housemaid" {
                return (resp, Data(self.filmHTML.utf8))
            } else if path.contains("/search/movie") {
                return (resp, self.json(["results": [["id": 1901, "title": "The Housemaid", "release_date": "1960-01-01"]]]))
            } else if path.contains("/credits") {
                return (resp, self.json(["crew": [["name": "Kim Ki-young", "job": "Writer", "department": "Writing"]]]))
            } else {
                return (resp, self.json(["runtime": 111]))
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("criterion-tracker-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var store = SnapshotStore(appGroupID: "group.test")
        store.containerOverride = tempDir

        let tmdb = TMDbClient(apiKey: "test", session: makeSession())
        let service = TrackerService(
            session: makeSession(), enrichers: [tmdb], store: store,
            filmPageURL: { URL(string: "https://www.criterionchannel.com/\($0)")! }
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = try await service.refresh(now: now)

        XCTAssertEqual(snap.now.title, "The Housemaid")
        XCTAssertEqual(snap.now.minutesUntilNext, 12)
        XCTAssertEqual(snap.film?.director, "Kim Ki-young")
        XCTAssertEqual(snap.film?.year, 1960)
        XCTAssertEqual(snap.film?.country, "South Korea")
        XCTAssertEqual(snap.film?.cast.count, 3)
        XCTAssertEqual(snap.film?.screenwriter, "Kim Ki-young")
        XCTAssertEqual(snap.film?.runtimeSeconds, 111 * 60)
        XCTAssertEqual(snap.remainingSeconds, 720)
        XCTAssertEqual(snap.phase, .normal)

        // Persisted to the store too.
        let loaded = store.load()
        XCTAssertEqual(loaded?.now.title, "The Housemaid")
    }

    func testSameFilmDoesNotReFetchFilmPage() async throws {
        // Seed a snapshot so the tracker treats it as "same film".
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("criterion-tracker-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var store = SnapshotStore(appGroupID: "group.test")
        store.containerOverride = tempDir

        let line = NowPlayingLine(title: "The Housemaid", slug: "the-housemaid",
                                  minutesUntilNext: 12, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let film = FilmInfo(title: "The Housemaid", director: "Kim Ki-young", year: 1960,
                            screenwriter: "Kim Ki-young", runtimeSeconds: 6660)
        let prior = StatusModel.snapshot(now: Date(timeIntervalSince1970: 1_700_000_000),
                                         line: line, film: film)
        try store.save(prior)

        // Count film-page hits; should be zero on the same-title refresh.
        nonisolated(unsafe) var filmPageHits = 0
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if path == "/" || path.isEmpty {
                return (resp, Data(self.feedHTML.utf8))
            }
            if path == "/the-housemaid" { filmPageHits += 1 }
            return (resp, self.json(["runtime": 111]))
        }

        let tmdb = TMDbClient(apiKey: "test", session: makeSession())
        let service = TrackerService(
            session: makeSession(), enrichers: [tmdb], store: store,
            filmPageURL: { URL(string: "https://www.criterionchannel.com/\($0)")! }
        )
        _ = try await service.refresh(now: Date(timeIntervalSince1970: 1_700_000_060))
        XCTAssertEqual(filmPageHits, 0)
    }
}