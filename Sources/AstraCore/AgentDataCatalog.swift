import Foundation
import SQLite3

public struct AgentSession: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let updated: Date
    public let bytes: Int64
}

public enum AgentDataCatalog {
    public static let versionsCategory = "Claude Code 安装版本"
    public static let cursorHistory = "Cursor 本地文件历史"
    public static let caches: [(String, String, String)] = [
        ("Claude 缓存", "Library/Application Support/Claude/Cache", "com.anthropic.claudefordesktop"),
        ("Claude 代码缓存", "Library/Application Support/Claude/Code Cache", "com.anthropic.claudefordesktop"),
        ("Cursor 缓存", "Library/Application Support/Cursor/Cache", "com.todesktop.230313mzl4w4u92"),
        ("Cursor 代码缓存", "Library/Application Support/Cursor/Code Cache", "com.todesktop.230313mzl4w4u92"),
        ("Claude Code 缓存", ".claude/cache", "com.anthropic.claudefordesktop"),
        ("OpenCode 缓存", ".cache/opencode", "opencode")
    ]
    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        (caches.map { $0.1 } + [".local/share/claude/versions", "Library/Application Support/Cursor/User/History"]).map { home.appendingPathComponent($0) }
    }
    public static func versionIsProtected(_ entry: FileEntry, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard entry.category == versionsCategory else { return false }
        let executable = home.appendingPathComponent(".local/bin/claude")
        let current = executable.resolvingSymlinksInPath()
        let root = home.appendingPathComponent(".local/share/claude/versions")
        return !FileManager.default.fileExists(atPath: executable.path) || !RemovalService.isWithin(current, parent: root) || current.path == entry.url.resolvingSymlinksInPath().path
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) -> ScanReport {
        var report = ScanReport()
        let sources = caches + [(versionsCategory, ".local/share/claude/versions", "com.anthropic.claudefordesktop"),
                                (cursorHistory, "Library/Application Support/Cursor/User/History", "com.todesktop.230313mzl4w4u92")]
        for (title, path, owner) in sources {
            if token.isCancelled { report.cancelled = true; break }
            var part = Catalog.scanCleanup(roots: [CleanupRoot(title: title, url: home.appendingPathComponent(path), installersOnly: false)], token: token)
            part.entries = part.entries.map { item in
                var item = item; item.ownerBundleIdentifier = owner; item.requiresReview = true
                if title == cursorHistory {
                    // 整个历史分组一起移入废纸篓，索引与版本文件保持在一起。
                    // 取所有子项最新时间，不能仅根据目录创建时间判断历史是否过期。
                    var latest = Date.distantPast
                    var readable = true
                    if let walker = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: [.contentModificationDateKey], errorHandler: { _, _ in readable = false; return true }) {
                        for case let child as URL in walker {
                            if token.isCancelled { readable = false; break }
                            if let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { latest = max(latest, date) }
                            else { readable = false }
                        }
                    } else { readable = false }
                    item.historyDate = readable && latest != .distantPast ? latest : .distantFuture
                }
                return item
            }
            report.entries += part.entries; report.issues += part.issues; report.visited += part.visited
            report.cancelled = report.cancelled || part.cancelled
        }
        return report
    }
    /// 只读事务返回一致的会话摘要；容量为关联消息正文长度，不是数据库可释放空间。
    public static func openCodeSessions(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) throws -> [AgentSession] {
        let url = home.appendingPathComponent(".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard url == url.resolvingSymlinksInPath() else { throw AstraError.message("OpenCode 数据库路径包含符号链接，已跳过。") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw AstraError.message("无法只读打开 OpenCode 数据库。")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        let sql = """
        SELECT s.id,s.title,s.time_updated,
        COALESCE(m.n,0)+COALESCE(p.n,0) FROM session s
        LEFT JOIN (SELECT session_id,SUM(length(CAST(data AS BLOB))) n FROM message GROUP BY session_id) m ON m.session_id=s.id
        LEFT JOIN (SELECT session_id,SUM(length(CAST(data AS BLOB))) n FROM part GROUP BY session_id) p ON p.session_id=s.id
        ORDER BY s.time_updated DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AstraError.message("OpenCode 数据库结构不受支持，未读取会话。") }
        defer { sqlite3_finalize(statement) }
        var result: [AgentSession] = []
        while !token.isCancelled {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw AstraError.message("OpenCode 会话读取未完成，请重试。") }
            func string(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
            result.append(AgentSession(id: string(0), title: string(1), updated: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1000), bytes: sqlite3_column_int64(statement, 3)))
        }
        return []
    }
}
