import Foundation
import AstraCore

final class ServiceTests: XCTestCase {
    func testReadsApplicationMetadataWithoutExecutingApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("astra-app-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("示例.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "示例工具", "CFBundleIdentifier": "test.example", "CFBundleShortVersionString": "2.3"], format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Info.plist"))
        let apps = Catalog.applications(in: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "示例工具")
        XCTAssertEqual(apps.first?.version, "2.3")
        XCTAssertEqual(apps.first?.bundleID, "test.example")
    }
    func testProcessFailureDoesNotBecomeSuccess() throws {
        let result = try CommandService.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        XCTAssertNotEqual(result.exitCode, 0)
    }
    func testProcessArgumentsAreNotShellInterpolated() throws {
        let result = try CommandService.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["$(whoami);中文"])
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "$(whoami);中文")
    }
    func testCPUUsesTickDifferenceAndWaitsForSecondSample() {
        XCTAssertNil(SystemMonitor.cpuUsage(previous: nil, current: [10, 5, 80, 5]))
        XCTAssertEqual(SystemMonitor.cpuUsage(previous: [10, 5, 80, 5], current: [20, 5, 100, 5])!, 100.0 / 3.0, accuracy: 0.01)
    }
}
