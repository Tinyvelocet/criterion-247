import XCTest
@testable import CriterionData

final class StatusModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testRemainingDecreasesWithWallClock() {
        let line = NowPlayingLine(title: "T", slug: "t", minutesUntilNext: 10, fetchedAt: t0)
        // At fetch time: 10 min remaining.
        XCTAssertEqual(StatusModel.remainingSeconds(now: t0, line: line), 600)
        // 2 minutes later: 8 min remaining.
        let later = t0.addingTimeInterval(120)
        XCTAssertEqual(StatusModel.remainingSeconds(now: later, line: line), 480)
        // Clamped at zero.
        let wayLater = t0.addingTimeInterval(3600)
        XCTAssertEqual(StatusModel.remainingSeconds(now: wayLater, line: line), 0)
    }

    func testElapsedUsesRuntime() {
        XCTAssertNil(StatusModel.elapsedSeconds(remaining: 600, runtimeSeconds: nil))
        XCTAssertEqual(StatusModel.elapsedSeconds(remaining: 600, runtimeSeconds: 6660), 6060)
        XCTAssertEqual(StatusModel.elapsedSeconds(remaining: 7000, runtimeSeconds: 6660), 0)
    }

    func testSnapshotFinalePhase() {
        let line = NowPlayingLine(title: "T", slug: "t", minutesUntilNext: 10, fetchedAt: t0)
        let film = FilmInfo(title: "T", runtimeSeconds: 900)
        // 5 min 10 s elapsed after fetch → 4 min 50 s remain → finale.
        let now = t0.addingTimeInterval(310)
        let snap = StatusModel.snapshot(now: now, line: line, film: film)
        XCTAssertEqual(snap.phase, .finale)
        XCTAssertEqual(snap.remainingSeconds, 290)
        XCTAssertEqual(snap.elapsedSeconds, 610)
    }

    func testSnapshotNormalPhaseWithoutRuntime() {
        let line = NowPlayingLine(title: "T", slug: "t", minutesUntilNext: 20, fetchedAt: t0)
        let snap = StatusModel.snapshot(now: t0, line: line, film: nil)
        XCTAssertEqual(snap.phase, .normal)
        XCTAssertEqual(snap.remainingSeconds, 1200)
        XCTAssertEqual(snap.elapsedSeconds, 0)
        XCTAssertNil(snap.film)
    }
}