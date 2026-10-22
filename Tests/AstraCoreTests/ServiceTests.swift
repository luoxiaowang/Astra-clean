import Foundation
import Darwin
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
    func testUninstallFindsOwnedContainersAndExtensions() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("astra-related-\(UUID())").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications")
        let app = applications.appendingPathComponent("Example.app")
        let home = root.appendingPathComponent("home")
        func bundle(_ path: URL, id: String) throws {
            let contents = path.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try bundle(app, id: "test.astra.example")
        try bundle(app.appendingPathComponent("Contents/PlugIns/Widget.appex"), id: "test.astra.example.widget")
        let expected = ["Library/Caches/test.astra.example", "Library/Containers/test.astra.example",
                        "Library/Application Scripts/test.astra.example", "Library/Containers/test.astra.example.widget",
                        "Library/Application Scripts/test.astra.example.widget"]
        for path in expected + ["Library/Containers/test.astra.example.other", "Library/Group Containers/test.astra.example"] {
            try fm.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let info = Catalog.applications(in: [applications])[0]
        let result = Catalog.relatedPaths(for: info, home: home).map { String($0.path.dropFirst(home.path.count + 1)) }
        XCTAssertEqual(Set(result), Set(expected))
        // A symlinked extension must not import an unrelated application's identity.
        let outside = root.appendingPathComponent("Outside.appex")
        try bundle(outside, id: "test.astra.unrelated")
        try fm.createSymbolicLink(at: app.appendingPathComponent("Contents/PlugIns/Outside.appex"), withDestinationURL: outside)
        try fm.createDirectory(at: home.appendingPathComponent("Library/Containers/test.astra.unrelated"), withIntermediateDirectories: true)
        XCTAssertEqual(Set(Catalog.relatedPaths(for: info, home: home).map(\.path)), Set(expected.map { home.appendingPathComponent($0).path }))
    }
    func testAllocatedSizeAndFingerprintRemainIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("astra-allocation-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("sparse-file")
        FileManager.default.createFile(atPath: path.path, contents: Data([1]))
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: 16 * 1024 * 1024)
        try handle.close()
        var st = stat()
        XCTAssertEqual(lstat(path.path, &st), 0)
        let logical = try FileScanner.measure(url: path)
        let allocated = try FileScanner.measure(url: path, metric: .allocated)
        XCTAssertEqual(logical.bytes, 16 * 1024 * 1024)
        XCTAssertEqual(allocated.bytes, Int64(st.st_blocks) * 512)
        XCTAssertNotEqual(allocated.bytes, logical.bytes)
        XCTAssertEqual(allocated.fingerprint, logical.fingerprint)
        XCTAssertNoThrow(try RemovalService.validate(allocated, allowedRoots: [root]))
        try Data([2, 3]).write(to: path)
        XCTAssertThrowsError(try RemovalService.validate(allocated, allowedRoots: [root]))
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
