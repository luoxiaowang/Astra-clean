import Foundation
import AppKit
import AstraCore
import SQLite3

final class FileSafetyTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("astra-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ name: String, _ count: Int) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: count).write(to: url)
        return url
    }
    func testOtherAgentSourcesAndProtection() throws {
        try file("Library/Application Support/Claude/Cache/data", 10)
        try file("Library/Application Support/Cursor/User/History/group/entries.json", 2)
        let current = try file(".local/share/claude/versions/new", 9)
        try file(".local/share/claude/versions/old", 8)
        try file(".claude/transcripts/record.jsonl", 7)
        let report = AgentDataCatalog.scan(home: root, token: ScanCancellation())
        XCTAssertEqual(report.entries.count, 4)
        let versions = report.entries.filter { $0.category == AgentDataCatalog.versionsCategory }
        XCTAssertTrue(versions.allSatisfy { AgentDataCatalog.versionIsProtected($0, home: root) })
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".local/bin/claude"), withDestinationURL: current)
        XCTAssertEqual(versions.filter { AgentDataCatalog.versionIsProtected($0, home: root) }.map(\.name), ["new"])
        XCTAssertTrue(report.entries.allSatisfy { $0.requiresReview })
        let history = report.entries.first { $0.category == AgentDataCatalog.cursorHistory }!
        XCTAssertFalse(AICleanupCatalog.olderThan(15, entry: history))
        XCTAssertEqual(AICleanupCatalog.scan(home: root, token: ScanCancellation()).entries.count, 1)
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(AgentDataCatalog.scan(home: root, token: token).cancelled)
    }
    func testOpenCodeReadOnlySessionSummary() throws {
        let url = try file(".local/share/opencode/opencode.db", 0)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE session(id TEXT,title TEXT,time_updated INTEGER);
        CREATE TABLE message(session_id TEXT,data TEXT);
        CREATE TABLE part(session_id TEXT,data TEXT);
        INSERT INTO session VALUES('s1','测试对话',1000),('s2','空对话',2000);
        INSERT INTO message VALUES('s1','abc');
        INSERT INTO part VALUES('s1','12345'),('s1','xy');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let before = try Data(contentsOf: url)
        let sessions = try AgentDataCatalog.openCodeSessions(home: root, token: ScanCancellation())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.id, "s2")
        XCTAssertEqual(sessions.last?.bytes, 10)
        XCTAssertEqual(sessions.last?.updated, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(try Data(contentsOf: url), before)
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(try AgentDataCatalog.openCodeSessions(home: root, token: token).isEmpty)
    }
    func testDeveloperCachesAndBuildDiscovery() throws {
        try file(".npm/_cacache/content-v2/data", 19)
        try file("Desktop/code/sample/Cargo.toml", 2)
        try file("Desktop/code/sample/target/output", 31)
        try file("Desktop/code/unrelated/target/keep", 23)
        try file("Desktop/code/sample/node_modules/hidden/Cargo.toml", 2)
        try file("Desktop/code/sample/node_modules/hidden/target/keep", 13)
        let (report, roots) = DeveloperCleanup.scan(home: root, token: ScanCancellation())
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.totalBytes, 50)
        XCTAssertTrue(report.entries.allSatisfy { $0.requiresReview && $0.category == "开发工具" })
        XCTAssertEqual(roots.count, 2)
        XCTAssertTrue(report.entries.contains { $0.name == "_cacache" })
        XCTAssertTrue(report.entries.contains { $0.name == "target" })
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(DeveloperCleanup.scan(home: root, token: token).0.cancelled)
    }
    func testCursorAgentVersionsProtectCurrent() throws {
        let current = try file(".local/share/cursor-agent/versions/new/cursor-agent", 25)
        try file(".local/share/cursor-agent/versions/old/cursor-agent", 15)
        let bin = root.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("cursor-agent"), withDestinationURL: current)
        try file(".cursor/projects/keep.json", 7)
        let report = IdleToolCatalog.scan(home: root, token: ScanCancellation())
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.totalBytes, 40)
        XCTAssertEqual(report.entries.filter { IdleToolCatalog.isCurrent($0, home: root) }.map(\.name), ["new"])
        XCTAssertTrue(report.entries.allSatisfy { $0.category == IdleToolCatalog.category })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor/projects/keep.json").path))
    }
    func testAIHistoryScopeAndAge() throws {
        let old = try file(".codex/sessions/2025/old.jsonl", 32)
        let recent = try file(".claude/projects/example/new.jsonl", 17)
        let compressed = try file(".codex/sessions/2025/older.jsonl.zst", 23)
        let archived = try file(".codex/archived_sessions/archive.jsonl.zst", 11)
        try file(".codex/sessions/unrelated.zst", 8)
        try FileManager.default.createSymbolicLink(at: old.deletingLastPathComponent().appendingPathComponent("link.jsonl.zst"), withDestinationURL: compressed)
        try file(".codex/sessions/settings.json", 7)
        let outside = try file("outside.jsonl", 9)
        try FileManager.default.createSymbolicLink(at: old.deletingLastPathComponent().appendingPathComponent("link.jsonl"), withDestinationURL: outside)
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86400)], ofItemAtPath: old.path)
        let report = AICleanupCatalog.scan(home: root, token: ScanCancellation())
        XCTAssertEqual(Set(report.entries.map(\.url)), Set([old, recent, compressed, archived]))
        let oldEntry = try FileScanner.measure(url: old)
        XCTAssertTrue(AICleanupCatalog.olderThan(30, entry: oldEntry, now: now))
        XCTAssertFalse(AICleanupCatalog.olderThan(60, entry: oldEntry, now: now))
        XCTAssertFalse(AICleanupCatalog.olderThan(0, entry: oldEntry, now: now))
        XCTAssertFalse(AICleanupCatalog.olderThan(30, entry: try FileScanner.measure(url: recent), now: now))
        XCTAssertEqual(try Data(contentsOf: old).count, 32)
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(AICleanupCatalog.scan(home: root, token: token).entries.isEmpty)
    }
    func testMaintenanceReportsInvalidAndMissingConfiguration() throws {
        let invalid = try file("agents/broken.plist", 19)
        let before = try Data(contentsOf: invalid)
        let report = MaintenanceService.inspectPlists(at: invalid.deletingLastPathComponent(), title: "测试配置")
        XCTAssertEqual(report.status, .attention)
        XCTAssertEqual(try Data(contentsOf: invalid), before)
        let missing = MaintenanceService.inspectPlists(at: root.appendingPathComponent("missing"), title: "不存在的配置")
        XCTAssertEqual(missing.status, .unavailable)
        XCTAssertFalse(missing.succeeded)
    }
    func testNestedSizesAndLargestFiles() throws {
        try file("folder/a", 7); try file("folder/b", 13)
        let report = FileScanner.scan(root: root)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries.first?.bytes, 20)
        XCTAssertEqual(report.largestFiles.first?.bytes, 13)
        XCTAssertTrue(report.issues.isEmpty)
    }
    func testDoesNotFollowSymbolicLinks() throws {
        let outside = try file("outside/data", 19)
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertEqual(FileScanner.scan(root: folder).entries.count, 0)
    }
    func testHardLinkedFilesAreCountedOnceWithinTree() throws {
        let a = try file("folder/a", 11)
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("folder/b"))
        XCTAssertEqual(FileScanner.scan(root: root).entries.first?.bytes, 11)
    }
    func testCancelledScanIsExplicit() throws {
        try file("a", 10)
        let token = ScanCancellation(); token.cancel()
        let report = FileScanner.scan(root: root, token: token)
        XCTAssertTrue(report.cancelled)
        XCTAssertTrue(report.entries.isEmpty)
    }
    func testMissingRootIsReportedAsError() {
        XCTAssertFalse(FileScanner.scan(root: root.appendingPathComponent("missing")).issues.isEmpty)
    }
    func testRemovalRejectsModifiedDescendant() throws {
        try file("folder/a", 10)
        let entry = try FileScanner.measure(url: root.appendingPathComponent("folder"))
        try file("folder/a", 30)
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [root]))
    }
    func testRemovalRejectsRootItselfAndOutsideSibling() throws {
        let entry = try FileScanner.measure(url: root)
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [root]))
        let a = try file("allowed/a", 2)
        let other = try file("allowed-other/b", 2)
        XCTAssertNoThrow(try RemovalService.validate(FileScanner.measure(url: a), allowedRoots: [a.deletingLastPathComponent()]))
        XCTAssertThrowsError(try RemovalService.validate(FileScanner.measure(url: other), allowedRoots: [a.deletingLastPathComponent()]))
    }
    func testRemovalRejectsReplacedParentSymlink() throws {
        let a = try file("parent/a", 10)
        let entry = try FileScanner.measure(url: a)
        try FileManager.default.moveItem(at: a.deletingLastPathComponent(), to: root.appendingPathComponent("moved"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("parent"), withDestinationURL: root.appendingPathComponent("moved"))
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [root]))
    }
    func testRemovalDeduplicatesNestedSelections() throws {
        let a = try file("folder/a", 10)
        let parent = try FileScanner.measure(url: a.deletingLastPathComponent())
        let child = try FileScanner.measure(url: a)
        XCTAssertEqual(RemovalService.deduplicated([child, parent, parent]).map(\.url), [parent.url])
    }
    func testUnreadableDirectoryIsNotSuccessfulZero() throws {
        let path = root.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path) }
        let report = FileScanner.scan(root: root)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertThrowsError(try FileScanner.measure(url: path))
    }
    func testCancellationDuringTraversalStopsEarly() throws {
        for index in 0..<200 { try file("folder/\(index)", 3) }
        let token = ScanCancellation()
        let report = FileScanner.scan(root: root, token: token, progress: { _, _ in token.cancel() })
        XCTAssertTrue(report.cancelled)
        XCTAssertTrue(report.visited < 200)
        XCTAssertFalse(report.entries.first?.complete ?? true)
    }
    func testRemovalRejectsDeletedTarget() throws {
        let url = try file("a", 5); let entry = try FileScanner.measure(url: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [root]))
    }
    func testProtectedDescendantPreventsRemovingItsParent() throws {
        let url = try file("folder/important", 8)
        let parent = try FileScanner.measure(url: url.deletingLastPathComponent())
        XCTAssertThrowsError(try RemovalService.validate(parent, allowedRoots: [root], protected: [url]))
    }
    func testTrashAndRestoreDisposableFixture() throws {
        let url = try file("astra-disposable-\(UUID()).txt", 17)
        let entry = try FileScanner.measure(url: url)
        let outcomes = RemovalService.trash([entry, entry], allowedRoots: [root])
        XCTAssertEqual(outcomes.count, 1)
        guard let outcome = outcomes.first else { throw AstraError.message("未返回执行结果") }
        XCTAssertNil(outcome.error)
        guard let destination = outcome.destination else { throw AstraError.message("未返回废纸篓路径") }
        // Always restore the test fixture, even when an assertion below fails.
        defer { try? FileManager.default.moveItem(at: destination, to: url) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: destination).count, 17)
    }
    func testCleanupRejectsSymbolicRoot() throws {
        let data = try file("real-data/document.txt", 25)
        let link = root.appendingPathComponent("pretend-cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: data.deletingLastPathComponent())
        let report = Catalog.scanCleanup(roots: [CleanupRoot(title: "缓存", url: link, installersOnly: false)])
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path))
    }
    func testInstallerScanDoesNotTraverseUnrelatedFolders() throws {
        try file("a-project/node_modules/a.js", 13)
        try file("z-installer.dmg", 21)
        let report = Catalog.scanCleanup(roots: [CleanupRoot(title: "安装包", url: root, installersOnly: true)])
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.visited, 1)
        XCTAssertEqual(report.totalBytes, 21)
    }
    func testRunningAppProtectsItsRelatedData() throws {
        guard let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL).first else {
            throw AstraError.message("测试环境没有可用的运行中应用")
        }
        let url = try file("related-preferences.plist", 9)
        var entry = try FileScanner.measure(url: url)
        entry.ownerApplicationURL = running
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [root]))
    }
    func testCleanupProtectsKnownRunningAppCache() throws {
        guard let id = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).first else {
            throw AstraError.message("没有运行中应用标识")
        }
        let cache = root.appendingPathComponent("Caches/\(id)")
        try file("Caches/\(id)/Cache.db", 10)
        let report = Catalog.scanCleanup(roots: [CleanupRoot(title: "AI 缓存", url: cache, installersOnly: false)])
        guard let entry = report.entries.first else { throw AstraError.message("缓存夹具未扫描到") }
        XCTAssertThrowsError(try RemovalService.validate(entry, allowedRoots: [cache]))
    }
}
