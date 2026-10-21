import Foundation
import AppKit

public struct RemovalOutcome: Identifiable, Sendable {
    public let id = UUID()
    public let original: URL
    public let destination: URL?
    public let error: String?
}

public enum RemovalService {
    public static func isWithin(_ url: URL, parent: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let root = parent.standardizedFileURL.path
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
    public static func deduplicated(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if !result.contains(where: { $0.url == entry.url || isWithin(entry.url, parent: $0.url) }) { result.append(entry) }
        }
        return result
    }
    public static func validate(_ entry: FileEntry, allowedRoots: [URL], protected: [URL] = []) throws {
        let url = entry.url.standardizedFileURL
        guard entry.complete else { throw AstraError.message("项目未完整扫描，不能移除。") }
        guard url.resolvingSymlinksInPath().path == url.path else { throw AstraError.message("路径包含符号链接或已被替换，请重新扫描。") }
        guard allowedRoots.contains(where: { isWithin(url, parent: $0.resolvingSymlinksInPath()) }) else {
            throw AstraError.message("目标不在本次允许处理的目录内，不能移除扫描根目录。")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let forbidden = [URL(fileURLWithPath: "/System"), URL(fileURLWithPath: "/usr"), URL(fileURLWithPath: "/bin"), URL(fileURLWithPath: "/sbin"), URL(fileURLWithPath: "/Library"), Bundle.main.bundleURL] + protected
        guard url.path != home.path, !forbidden.contains(where: { url == $0 || isWithin(url, parent: $0) || isWithin($0, parent: url) }) else {
            throw AstraError.message("这是受保护的路径。")
        }
        if entry.category == IdleToolCatalog.category && IdleToolCatalog.isCurrent(entry) {
            throw AstraError.message("这是命令入口正在指向的当前版本，不能作为旧版本清理。")
        }
        if AgentDataCatalog.versionIsProtected(entry) {
            throw AstraError.message("当前 Claude 版本或命令入口未确认，不能移除。")
        }
        let runningApps = NSWorkspace.shared.runningApplications
        if let identifier = entry.ownerBundleIdentifier,
           CleanupPresentation.isRunning(owner: identifier, runningIDs: Set(runningApps.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap { $0 } })) {
            throw AstraError.message("所属应用正在运行，不能移除其缓存或日志。请退出应用后重新扫描。")
        }
        let running = runningApps.compactMap(\.bundleURL)
        if let owner = entry.ownerApplicationURL,
           running.contains(where: { $0.resolvingSymlinksInPath() == owner.resolvingSymlinksInPath() }) {
            throw AstraError.message("所属应用正在运行，其关联数据也不能移除。请退出应用后重新扫描。")
        }
        guard !running.contains(where: { url == $0 || isWithin($0, parent: url) || isWithin(url, parent: $0) }) else {
            throw AstraError.message("应用正在运行，请退出后重新扫描。")
        }
        let current = try FileScanner.measure(url: url)
        guard current.fingerprint == entry.fingerprint else { throw AstraError.message("文件在扫描后发生变化，请重新扫描后再操作。") }
    }
    public static func trash(_ entries: [FileEntry], allowedRoots: [URL]) -> [RemovalOutcome] {
        deduplicated(entries).map { entry in
            do {
                try validate(entry, allowedRoots: allowedRoots)
                var destination: NSURL?
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &destination)
                return RemovalOutcome(original: entry.url, destination: destination as URL?, error: nil)
            } catch { return RemovalOutcome(original: entry.url, destination: nil, error: error.localizedDescription) }
        }
    }
}
