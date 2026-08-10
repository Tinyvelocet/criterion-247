import XCTest
@testable import CriterionData

final class SnapshotStoreTests: XCTestCase {
    func testSaveLoadRoundTripWithContainer() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("criterion-snapshot-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var store = SnapshotStore(appGroupID: "group.test")
        store.containerOverride = tempDir

        let line = NowPlayingLine(title: "The Housemaid", slug: "the-housemaid",
                                  minutesUntilNext: 12, fetchedAt: Date(timeIntervalSince1970: 1_100_000_000))
        let film = FilmInfo(title: "The Housemaid", director: "Kim Ki-young", year: 1960,
                            country: "South Korea",
                            cast: ["Kim Jin-kyu", "Ju Jung-nyeo", "Lee Eun-shim"],
                            screenwriter: "Kim Ki-young", runtimeSeconds: 6660)
        let snap = StatusModel.snapshot(now: Date(timeIntervalSince1970: 1_100_000_120),
                                        line: line, film: film)

        try store.save(snap)
        let loaded = store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.now.title, "The Housemaid")
        XCTAssertEqual(loaded?.film?.director, "Kim Ki-young")
        XCTAssertEqual(loaded?.film?.cast.count, 3)
        XCTAssertEqual(loaded?.film?.runtimeSeconds, 6660)
        XCTAssertEqual(loaded?.remainingSeconds, snap.remainingSeconds)
        XCTAssertEqual(loaded?.phase, snap.phase)
    }

    func testLoadMissingFileReturnsNil() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("criterion-snapshot-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var store = SnapshotStore(appGroupID: "group.test")
        store.containerOverride = tempDir
        XCTAssertNil(store.load())
    }
}