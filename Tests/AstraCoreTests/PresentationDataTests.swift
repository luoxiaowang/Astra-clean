import Foundation
import AstraCore

final class PresentationDataTests: XCTestCase {
    func testPermissionIssueClassification() {
        XCTAssertTrue(ScanIssue(path: "/test", error: NSError(domain: NSPOSIXErrorDomain, code: 13)).permissionDenied)
        XCTAssertTrue(ScanIssue(path: "/test", error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)).permissionDenied)
        XCTAssertFalse(ScanIssue(path: "/test", error: NSError(domain: NSPOSIXErrorDomain, code: 2)).permissionDenied)
        XCTAssertFalse(ScanIssue(path: "/test", message: "达到扫描上限").permissionDenied)
    }
    func testCleanupGroupsAndRunningUpdates() {
        XCTAssertEqual(CleanupPresentation.category(for: "com.openai.codex", original: "应用缓存"), "AI 工具")
        XCTAssertEqual(CleanupPresentation.category(for: "com.todesktop.230313mzl4w4u92.ShipIt", original: "应用缓存"), "App 缓存与日志")
        XCTAssertEqual(CleanupPresentation.category(for: "ms-playwright", original: "应用缓存"), "App 缓存与日志")
        XCTAssertEqual(CleanupPresentation.category(for: "com.tencent.xinWeChat", original: "应用缓存"), "App 缓存与日志")
        XCTAssertEqual(CleanupPresentation.category(for: "com.figma.Desktop", original: "应用缓存"), "设计缓存")
        XCTAssertEqual(CleanupPresentation.category(for: "com.apple.helpd", original: "应用缓存"), "App 缓存与日志")
        XCTAssertEqual(CleanupPresentation.category(for: "unknown", original: "应用日志"), "App 缓存与日志")
        XCTAssertEqual(CleanupPresentation.category(for: "Claude.dmg", original: "下载的安装包"), "下载的安装包")
        XCTAssertTrue(CleanupPresentation.isRunning(owner: "com.example.app.ShipIt", runningIDs: ["com.example.app"]))
        XCTAssertTrue(CleanupPresentation.isRunning(owner: "codex", runningIDs: ["Codex"]))
        XCTAssertFalse(CleanupPresentation.isRunning(owner: "com.example.application", runningIDs: ["com.example.app"]))
    }
    func testMainPIDDoesNotAssumeLowestPID() {
        let rows = ProcessSampler.parse("200 1 1.0 1024 501 /Applications/A Test.app/Contents/MacOS/A Test\n100 200 2.0 2048 501 /usr/local/bin/node")
        let group = ProcessSampler.group(rows)[0]
        XCTAssertEqual(group.pid, 200)
        XCTAssertTrue(group.matches("100"))
        XCTAssertTrue(group.matches("node"))
        XCTAssertFalse(group.matches("not-a-real-process"))
    }
    func testSensorDecodingRejectsInvalidValues() {
        XCTAssertEqual(SMCReader.decode(type: 0x66706532, bytes: [0x12, 0xc0, 0, 0]), 1200)
        XCTAssertEqual(SMCReader.decode(type: 0x73703738, bytes: [0x3f, 0x80, 0, 0]), 63.5)
        XCTAssertNil(SMCReader.decode(type: 0x666c7420, bytes: [0, 0, 0xc0, 0x7f]))
        XCTAssertNil(SMCReader.decode(type: 0, bytes: [0, 0, 0, 0]))
        XCTAssertNil(SMCReader.decode(type: 0x66706532, bytes: []))
    }
    func testTreemapCoversBoundsWithoutOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let tiles = TreemapLayout.rectangles(weights: [60, 25, 10, 5, 0], in: bounds)
        XCTAssertEqual(tiles.count, 5)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.width * $1.height }, 480000, accuracy: 0.1)
        XCTAssertEqual(tiles[0].width * tiles[0].height, 288000, accuracy: 0.1)
        XCTAssertEqual(tiles[4].width * tiles[4].height, 0, accuracy: 0.1)
        for i in tiles.indices { for j in tiles.indices where j > i {
            let intersection = tiles[i].intersection(tiles[j])
            XCTAssertTrue(intersection.isNull || intersection.width * intersection.height == 0)
        } }
    }
    func testProcessParsingAndGrouping() {
        let rows = ProcessSampler.parse(" 10 1 2.5 1024 501 /Applications/A Test.app/Contents/MacOS/A Test\n11 10 4.0 2048 501 /usr/local/bin/node\n12 1 0.0 32 0 /usr/sbin/syslogd\nmalformed")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].residentBytes, 1048576)
        let groups = ProcessSampler.group(rows)
        XCTAssertEqual(groups.count, 2)
        let app = groups.first { $0.id == "/Applications/A Test.app" }!
        XCTAssertEqual(app.members.count, 2)
        XCTAssertEqual(app.cpu, 6.5, accuracy: 0.01)
        XCTAssertEqual(app.residentBytes, 3145728)
    }
}
