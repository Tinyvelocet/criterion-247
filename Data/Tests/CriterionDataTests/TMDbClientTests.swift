import XCTest
@testable import CriterionData

/// A stub URLProtocol that serves canned responses based on the path.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TMDbClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func json(_ obj: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    func testEnrichAddsRuntimeAndWriter() async throws {
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if path.contains("/search/movie") {
                let body: [String: Any] = [
                    "results": [["id": 1901, "title": "The Housemaid", "release_date": "1960-01-01"]],
                ]
                return (resp, self.json(body))
            } else if path.contains("/credits") {
                let body: [String: Any] = ["crew": [
                    ["name": "Kim Ki-young", "job": "Director", "department": "Writing"],
                    ["name": "Jane Scripter", "job": "Writer", "department": "Writing"],
                ]]
                return (resp, self.json(body))
            } else {  // /movie/{id}
                let body: [String: Any] = ["runtime": 111]
                return (resp, self.json(body))
            }
        }

        let client = TMDbClient(apiKey: "test", session: makeSession())
        var film = FilmInfo(title: "The Housemaid", year: 1960, country: "South Korea")
        try await client.enrich(film: &film, year: 1960)

        XCTAssertEqual(film.runtimeSeconds, 111 * 60)
        XCTAssertEqual(film.screenwriter, "Jane Scripter")
    }

    func testEnrichFallsBackWhenNoResults() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.json(["results": []]))
        }
        let client = TMDbClient(apiKey: "test", session: makeSession())
        var film = FilmInfo(title: "Obscure Film", year: 1920)
        try await client.enrich(film: &film, year: 1920)
        XCTAssertNil(film.runtimeSeconds)
        XCTAssertNil(film.screenwriter)
    }

    func testEnrichPrefersExplicitWriterJob() async throws {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if req.url!.path.contains("/search/movie") {
                return (resp, self.json(["results": [["id": 5, "title": "X", "release_date": "1950"]]]))
            } else if req.url!.path.contains("/credits") {
                return (resp, self.json(["crew": [
                    ["name": "Dept Writer", "job": "Editor", "department": "Writing"],
                ]]))
            }
            return (resp, self.json(["runtime": 90]))
        }
        let client = TMDbClient(apiKey: "test", session: makeSession())
        var film = FilmInfo(title: "X", year: 1950)
        try await client.enrich(film: &film, year: 1950)
        XCTAssertEqual(film.screenwriter, "Dept Writer")
    }
}