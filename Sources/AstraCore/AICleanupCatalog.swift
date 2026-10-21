import Foundation

/// 仅识别已知的独立会话文件；数据库和工作树不作为普通缓存处理。
public enum AICleanupCatalog {
    public static let histories: [(title: String, path: String, owner: String)] = [
        ("Codex 聊天记录", ".codex/sessions", "com.openai.codex"),
        ("Codex 归档记录", ".codex/archived_sessions", "com.openai.codex"),
        ("Claude transcripts 文件", ".claude/transcripts", "com.anthropic.claudefordesktop"),
        ("Claude Code 聊天记录", ".claude/projects", "com.anthropic.claudefordesktop")
    ]
    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        histories.map { home.appendingPathComponent($0.path) }
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) -> ScanReport {
        var report = ScanReport()
        for source in histories {
            let root = home.appendingPathComponent(source.path)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard root.standardizedFileURL == root.resolvingSymlinksInPath() else {
                report.issues.append(ScanIssue(path: root.path, message: "会话目录包含符号链接，已跳过。")); continue
            }
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], errorHandler: { url, error in
                report.issues.append(ScanIssue(path: url.path, error: error)); return true
            }) else { continue }
            for case let url as URL in walker {
                if token.isCancelled { report.cancelled = true; break }
                do {
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                    if values.isSymbolicLink == true { walker.skipDescendants(); continue }
                    // Codex 历史迁移后使用 .jsonl.zst；直接统计压缩文件的实际大小，
                    // 不解压、不读取对话正文，仍保留逐文件校验和移入废纸篓流程。
                    let isHistory = url.pathExtension == "jsonl" ||
                        (source.owner == "com.openai.codex" && url.lastPathComponent.hasSuffix(".jsonl.zst"))
                    guard values.isRegularFile == true, isHistory else { continue }
                    var entry = try FileScanner.measure(url: url)
                    entry.category = source.title; entry.ownerBundleIdentifier = source.owner
                    report.entries.append(entry); report.visited += 1
                } catch { report.issues.append(ScanIssue(path: url.path, error: error)) }
            }
        }
        return report
    }
    public static func olderThan(_ days: Int, entry: FileEntry, now: Date = Date()) -> Bool {
        if let date = entry.historyDate { return days > 0 && date < now.addingTimeInterval(-Double(days) * 86400) }
        guard days > 0, let values = try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]), let date = values.contentModificationDate else { return false }
        return date < now.addingTimeInterval(-Double(days) * 86400)
    }
}
