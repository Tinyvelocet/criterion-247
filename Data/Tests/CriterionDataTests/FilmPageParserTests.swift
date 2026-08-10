import XCTest
@testable import CriterionData

final class FilmPageParserTests: XCTestCase {
    func fixture(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func testParseRealFixture() throws {
        let html = fixture("film_page_sample.html")
        let info = try FilmPageParser.parse(html, title: "The Housemaid")

        XCTAssertEqual(info.title, "The Housemaid")
        XCTAssertEqual(info.director, "Kim Ki-young")
        XCTAssertEqual(info.year, 1960)
        XCTAssertEqual(info.country, "South Korea")
        XCTAssertEqual(info.cast, ["Kim Jin-kyu", "Ju Jung-nyeo", "Lee Eun-shim"])
        XCTAssertEqual(info.slug, "the-housemaid")
        XCTAssertTrue(info.posterURL?.hasPrefix("https://vhx.imgix.net/") == true)
        XCTAssertTrue(info.synopsis?.contains("HOUSEMAID") == true)
    }

    func testParseHandlesMissingDirectorLine() throws {
        let html = """
        <html><head>
        <meta name="description" content="A standalone film with no director line.">
        <link rel="canonical" href="https://www.criterionchannel.com/xyz-film">
        <meta property="og:image" content="https://vhx.imgix.net/x.jpg">
        </head><body></body></html>
        """
        let info = try FilmPageParser.parse(html, title: "Xyz")
        XCTAssertNil(info.director)
        XCTAssertNil(info.year)
        XCTAssertEqual(info.slug, "xyz-film")
        XCTAssertEqual(info.synopsis, "A standalone film with no director line.")
    }

    func testParseRejectsEmptyPage() {
        XCTAssertThrowsError(try FilmPageParser.parse("<html></html>", title: "X"))
    }

    func testYearCountryParsing() throws {
        let html = """
        <meta name="description" content="Series Intro
        Directed by Akira Kurosawa • 1954 • Japan
        Starring Toshiro Mifune"> <link rel="canonical" href="https://www.criterionchannel.com/seven-samurai">
        """
        let info = try FilmPageParser.parse(html, title: "Seven Samurai")
        XCTAssertEqual(info.director, "Akira Kurosawa")
        XCTAssertEqual(info.year, 1954)
        XCTAssertEqual(info.country, "Japan")
        XCTAssertEqual(info.cast, ["Toshiro Mifune"])
    }
}