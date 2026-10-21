import Foundation

public enum IdleToolCatalog {
    public static let category = "Cursor Agent 安装版本"
    public static func root(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/share/cursor-agent/versions")
    }
    public static func currentExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin/cursor-agent").resolvingSymlinksInPath()
    }
    public static func isCurrent(_ entry: FileEntry, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let current = currentExecutable(home: home)
        return current == entry.url || RemovalService.isWithin(current, parent: entry.url)
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) -> ScanReport {
        let folder = root(home: home)
        guard FileManager.default.fileExists(atPath: folder.path) else { return ScanReport() }
        var report = Catalog.scanCleanup(roots: [CleanupRoot(title: category, url: folder, installersOnly: false)], token: token)
        report.entries = report.entries.map { item in
            var item = item; item.ownerBundleIdentifier = nil; return item
        }
        return report
    }
    public static func modificationSummary(_ entries: [FileEntry], now: Date = Date()) -> String {
        let dates = entries.compactMap { (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        guard let latest = dates.max() else { return "无法读取安装更新时间；不能据此判断是否闲置" }
        let days = max(0, Int(now.timeIntervalSince(latest) / 86400))
        return "安装目录 \(days) 天未更新；使用时间未知"
    }
}
