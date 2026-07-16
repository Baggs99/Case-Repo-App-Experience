/*
 * Purpose: Tests engine selection (DrillEngineProvider), the on-device template
 *          cache (load/refresh), and the FM dressing validator — the parts of the
 *          on-device path that run without the live model.
 * Inputs: bundled Fixtures/drill_templates.json; scratch temp directories.
 * Outputs: none (temp files cleaned in tearDown).
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

// DrillService whose templatePack() returns configurable bytes (or fails), for
// exercising TemplateCache.refresh. dailyDrill is never called by these tests.
final class PackDrillService: DrillService, @unchecked Sendable {
    var pack: Data
    var shouldFail = false
    init(pack: Data) { self.pack = pack }
    func dailyDrill() async throws -> Drill { throw APIError.server(500) }
    func templatePack() async throws -> Data {
        if shouldFail { throw APIError.server(500) }
        return pack
    }
    func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws {}
}

final class DrillEngineProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drill-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func fixturePack() throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "drill_templates", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private func cacheWithPack() throws -> TemplateCache {
        try fixturePack().write(to: tempDir.appendingPathComponent("drill-templates.json"))
        return TemplateCache(directory: tempDir)
    }

    // MARK: - TemplateCache

    func testCacheLoadNilWhenEmpty() {
        XCTAssertNil(TemplateCache(directory: tempDir).load())
    }

    func testCacheRefreshWritesAndLoads() async throws {
        let pack = try fixturePack()
        let cache = TemplateCache(directory: tempDir)
        await cache.refresh(service: PackDrillService(pack: pack))
        XCTAssertEqual(cache.load(), pack)
    }

    func testCacheRefreshEmptyBodyKeepsExisting() async throws {
        let good = try fixturePack()
        let cache = try cacheWithPack()
        await cache.refresh(service: PackDrillService(pack: Data()))
        XCTAssertEqual(cache.load(), good, "empty refresh must not clobber the cache")
    }

    func testCacheRefreshFailureKeepsExisting() async throws {
        let good = try fixturePack()
        let cache = try cacheWithPack()
        let service = PackDrillService(pack: Data())
        service.shouldFail = true
        await cache.refresh(service: service)
        XCTAssertEqual(cache.load(), good, "failed refresh must not clobber the cache")
    }

    // MARK: - Engine selection

    func testProviderPicksServerWhenProbeFalse() throws {
        let engine = DrillEngineProvider.make(
            service: PackDrillService(pack: Data()), fmAvailable: { false }, cache: try cacheWithPack()
        )
        XCTAssertEqual(engine.sourceLabel, "server")
    }

    func testProviderPicksServerWhenNoPackCached() {
        let engine = DrillEngineProvider.make(
            service: PackDrillService(pack: Data()), fmAvailable: { true },
            cache: TemplateCache(directory: tempDir)
        )
        XCTAssertEqual(engine.sourceLabel, "server")
    }

    func testProviderPicksFMWhenAvailableAndCached() throws {
        let engine = DrillEngineProvider.make(
            service: PackDrillService(pack: Data()), fmAvailable: { true }, userId: 1,
            cache: try cacheWithPack()
        )
        if #available(iOS 26.0, *) {
            XCTAssertEqual(engine.sourceLabel, "on_device")
        } else {
            // On pre-26 runtimes the FM branch is unreachable; server is correct.
            XCTAssertEqual(engine.sourceLabel, "server")
        }
    }

    // MARK: - FM dressing validator

    func testDressingValidator() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("dressingIsValid is on the iOS 26+ engine; not reachable on this runtime")
        }
        // Every number present verbatim.
        XCTAssertTrue(FoundationModelDrillEngine.dressingIsValid(
            "Revenue climbed from 80 to 120 — what's the change?", numbers: ["80", "120"]))
        // A missing number rejects the dressing.
        XCTAssertFalse(FoundationModelDrillEngine.dressingIsValid(
            "Revenue climbed from 80 — what's the change?", numbers: ["80", "120"]))
        // Reformatted "1,200" fails a verbatim "1200" requirement.
        XCTAssertFalse(FoundationModelDrillEngine.dressingIsValid(
            "About 1,200 coffee shops.", numbers: ["1200"]))
        // No numbers → vacuously valid.
        XCTAssertTrue(FoundationModelDrillEngine.dressingIsValid("A prose-only recall prompt.", numbers: []))
    }
}
