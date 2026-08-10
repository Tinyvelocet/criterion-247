import XCTest
@testable import CriterionData

final class CriterionClientTests: XCTestCase {
    func fixture(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // this file
            .appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func testParseNowPlayingFromRealFixture() throws {
        let html = fixture("whatsonnow_sample.html")
        let fixed = Date(timeIntervalSince1970: 1_100_000_000)
        let parsed = try CriterionClient.parseNowPlaying(html, fetchedAt: fixed)

        XCTAssertEqual(parsed.title, "The Housemaid")
        XCTAssertEqual(parsed.slug, "the-housemaid")
        XCTAssertEqual(parsed.minutesUntilNext, 10)  // fixture captured countdown
        XCTAssertEqual(parsed.fetchedAt, fixed)
    }

    func testParseFailsOnGarbage() {
        XCTAssertThrowsError(try CriterionClient.parseNowPlaying("<html><body>nothing</body></html>", fetchedAt: Date()))
    }

    func testParseRejectsEmptyTitle() {
        let html = #"<h2 class="whatson__title"> </h2>"#
        XCTAssertThrowsError(try CriterionClient.parseNowPlaying(html, fetchedAt: Date()))
    }

    func testHTMLDecoding() {
        XCTAssertEqual(htmlDecode("Axel &amp; &#39;the cat&#39;"), "Axel & 'the cat'")
    }

    func testMinutesParsingRobustAcrossWhitespace() throws {
        let html = #"<p class="whatson__eyebrow">Next film starts in: <span class="whatson__eyebrow--bold">7 minutes</span></p>"#
        let fixed = Date()
        let parsed = try CriterionClient.parseNowPlaying("<h2 class=\"whatson__title\">M</h2>" + html, fetchedAt: fixed)
        XCTAssertEqual(parsed.minutesUntilNext, 7)
    }

    func testPhaseCalculation() {
        XCTAssertEqual(TrackerPhase.phase(remainingSeconds: 310), .normal)
        XCTAssertEqual(TrackerPhase.phase(remainingSeconds: 300), .finale)
        XCTAssertEqual(TrackerPhase.phase(remainingSeconds: 0), .finale)
    }
}