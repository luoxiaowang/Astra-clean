import Foundation
import AstraCore

if CommandLine.arguments.contains("--agent-audit") {
    let report = AgentDataCatalog.scan(token: ScanCancellation())
    for (name, entries) in Dictionary(grouping: report.entries, by: \.category).sorted(by: { $0.key < $1.key }) {
        print("\(name): \(entries.count) 项，\(entries.reduce(Int64(0)) { $0 + $1.bytes }) 字节")
    }
    print("扫描问题：\(report.issues.count)")
    do { print("OpenCode 会话：\(try AgentDataCatalog.openCodeSessions(token: ScanCancellation()).count)") }
    catch { print(error.localizedDescription); exit(1) }
    exit(0)
}


// Command Line Tools has no XCTest. This small executable runs real fixture tests.
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
var failures = 0
func fail(_ message: String, _ file: StaticString, _ line: UInt) {
    failures += 1; print("失败 \(file):\(line) \(message)")
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { fail("预期为 true", file, line) }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(!value, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    if a != b { fail("\(a) != \(b)", file, line) }
}
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    if a == b { fail("不应相等", file, line) }
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    if abs(a - b) > accuracy { fail("\(a) 与 \(b) 超出误差", file, line) }
}
func XCTAssertNil<T>(_ a: T?, file: StaticString = #file, line: UInt = #line) {
    if a != nil { fail("预期 nil", file, line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression(); fail("操作应被拒绝", file, line) } catch {}
}
func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { fail("意外失败：\(error)", file, line) }
}
let safety = FileSafetyTests()
let service = ServiceTests()
let presentation = PresentationDataTests()
let tests: [(String, XCTestCase, () throws -> Void)] = [
    ("其他 Agent 扫描范围及当前版本保护", safety, safety.testOtherAgentSourcesAndProtection),
    ("OpenCode 只读会话关联汇总", safety, safety.testOpenCodeReadOnlySessionSummary),
    ("区分权限不足与非权限扫描错误", presentation, presentation.testPermissionIssueClassification),
    ("清理分类及更新缓存运行保护", presentation, presentation.testCleanupGroupsAndRunningUpdates),
    ("主进程不按最小 PID 推断", presentation, presentation.testMainPIDDoesNotAssumeLowestPID),
    ("传感器解码与无效值", presentation, presentation.testSensorDecodingRejectsInvalidValues),
    ("树图面积与无重叠", presentation, presentation.testTreemapCoversBoundsWithoutOverlap),
    ("进程解析和子进程归属", presentation, presentation.testProcessParsingAndGrouping),
    ("专用缓存与项目构建目录范围", safety, safety.testDeveloperCachesAndBuildDiscovery),
    ("Cursor Agent 版本扫描与当前版本保护", safety, safety.testCursorAgentVersionsProtectCurrent),
    ("AI 会话扫描范围、符号链接和保留天数", safety, safety.testAIHistoryScopeAndAge),
    ("维护检查不修改损坏配置且不误报不可读路径", safety, safety.testMaintenanceReportsInvalidAndMissingConfiguration),
    ("递归统计和最大文件", safety, safety.testNestedSizesAndLargestFiles),
    ("不跟随符号链接", safety, safety.testDoesNotFollowSymbolicLinks),
    ("硬链接不重复计数", safety, safety.testHardLinkedFilesAreCountedOnceWithinTree),
    ("取消明确返回", safety, safety.testCancelledScanIsExplicit),
    ("路径不存在有错误", safety, safety.testMissingRootIsReportedAsError),
    ("拒绝变化的子文件", safety, safety.testRemovalRejectsModifiedDescendant),
    ("范围边界检查", safety, safety.testRemovalRejectsRootItselfAndOutsideSibling),
    ("拒绝祖先符号链接替换", safety, safety.testRemovalRejectsReplacedParentSymlink),
    ("嵌套选择去重", safety, safety.testRemovalDeduplicatesNestedSelections),
    ("读取应用元数据", service, service.testReadsApplicationMetadataWithoutExecutingApplication),
    ("进程失败保留退出码", service, service.testProcessFailureDoesNotBecomeSuccess),
    ("参数不经 shell", service, service.testProcessArgumentsAreNotShellInterpolated),
    ("CPU 采样差值", service, service.testCPUUsesTickDifferenceAndWaitsForSecondSample),
    ("不可读目录明确报错", safety, safety.testUnreadableDirectoryIsNotSuccessfulZero),
    ("遍历中取消及时停止", safety, safety.testCancellationDuringTraversalStopsEarly),
    ("拒绝消失目标", safety, safety.testRemovalRejectsDeletedTarget),
    ("保护路径阻止父目录移除", safety, safety.testProtectedDescendantPreventsRemovingItsParent),
    ("测试文件移入废纸篓并恢复", safety, safety.testTrashAndRestoreDisposableFixture),
    ("拒绝符号链接缓存根", safety, safety.testCleanupRejectsSymbolicRoot),
    ("下载扫描只遍历安装包", safety, safety.testInstallerScanDoesNotTraverseUnrelatedFolders),
    ("运行中应用关联数据保护", safety, safety.testRunningAppProtectsItsRelatedData),
    ("运行中应用缓存保护", safety, safety.testCleanupProtectsKnownRunningAppCache)
]
for (name, instance, run) in tests {
    let before = failures
    do { try instance.setUpWithError(); try run() } catch { fail("\(error)", #file, #line) }
    do { try instance.tearDownWithError() } catch { fail("夹具清理：\(error)", #file, #line) }
    print("\(failures == before ? "通过" : "失败") · \(name)")
}
print("\(tests.count) 项测试，\(failures) 个失败")
exit(failures == 0 ? 0 : 1)
