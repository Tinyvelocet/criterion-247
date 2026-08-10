import XCTest
@testable import CriterionData

final class WikidataClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func json(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

    /// A representative wbsearchentities response: mixed candidates.
    private let searchJSON: [String: Any] = [
        "search": [
            ["id": "Q49729", "label": "The Housemaid", "description": "1960 South Korean film"],
            ["id": "Q485782", "label": "The Housemaid", "description": "2010 film"],
            ["id": "Q19926138", "label": "The Housemaid", "description": "painting"],
        ],
    ]

    /// A SPARQL VALUES response: the 1960 film has runtime + writer in minutes; the 2010 one has different data; the painting has no runtime.
    private func sparqlJSON() -> [String: Any] {
        func binding(_ film: String, _ t: String?, _ runtime: String?, _ writer: String?, _ date: String?) -> [String: Any] {
            func v(_ s: String) -> [String: Any] { ["value": s] }
            var b: [String: Any] = [:]
            b["film"] = v("http://www.wikidata.org/entity/\(film)")
            if let t { b["filmType"] = v(t) }
            if let runtime { b["runtime"] = v(runtime) }
            if let writer { b["writerLabel"] = v(writer) }
            if let date { b["date"] = v(date) }
            return b
        }
        return ["results": ["bindings": [
            binding("Q49729", "Q11424", "111", "Kim Ki-young", "1960-01-01T00:00:00Z"),
            binding("Q485782", "Q11424", "106", "Im Sang-soo", "2010-01-01T00:00:00Z"),
            binding("Q19926138", "Q3305213", nil, nil, nil),
        ]]]
    }

    func testEnrichPicksCorrectFilmByYear() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if req.url!.path.contains("w/api.php") {
                return (resp, self.json(self.searchJSON))
            }
            // SPARQL
            return (resp, self.json(self.sparqlJSON()))
        }
        let client = WikidataClient(session: makeSession())
        var film = FilmInfo(title: "The Housemaid", year: 1960)
        await client.enrich(film: &film, year: 1960)
        XCTAssertEqual(film.runtimeSeconds, 111 * 60)
        XCTAssertEqual(film.screenwriter, "Kim Ki-young")
    }

    func testEnrichMismatchedYearFallsBackToAnyFilm() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if req.url!.path.contains("w/api.php") {
                return (resp, self.json(self.searchJSON))
            }
            return (resp, self.json(self.sparqlJSON()))
        }
        let client = WikidataClient(session: makeSession())
        // No film matches the (wrong) year 1985 → fall back to the first film row.
        var film = FilmInfo(title: "The Housemaid", year: 1985)
        await client.enrich(film: &film, year: 1985)
        XCTAssertEqual(film.runtimeSeconds, 111 * 60)  // first film by year-sort order
        XCTAssertEqual(film.screenwriter, "Kim Ki-young")
    }

    func testEnrichNoSearchResultsLeavesFilmUnchanged() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if req.url!.path.contains("w/api.php") {
                return (resp, self.json(["search": []]))
            }
            return (resp, self.json(["results": ["bindings": []]]))
        }
        let client = WikidataClient(session: makeSession())
        var film = FilmInfo(title: "Obscure Film", year: 1920)
        await client.enrich(film: &film, year: 1920)
        XCTAssertNil(film.runtimeSeconds)
        XCTAssertNil(film.screenwriter)
    }

    func testEnrichBadResponseDegradesGracefully() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("server error".utf8))
        }
        let client = WikidataClient(session: makeSession())
        var film = FilmInfo(title: "Anything", year: 1999)
        await client.enrich(film: &film, year: 1999)
        XCTAssertNil(film.runtimeSeconds)
        XCTAssertNil(film.screenwriter)
    }
}