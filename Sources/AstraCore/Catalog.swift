import Foundation

public struct ApplicationInfo: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let modified: Date?
    public var installed: Date? = nil
    public var lastUsed: Date? = nil
}
public struct CleanupRoot: Identifiable, Sendable {
    public var id: String { url.path }
    public let title: String
    public let url: URL
    public let installersOnly: Bool
    public init(title: String, url: URL, installersOnly: Bool) {
        self.title = title; self.url = url; self.installersOnly = installersOnly
    }
}
public struct StartupItem: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let label: String
    public let program: String
    public let targetExists: Bool
}
public enum Catalog {
    public static func scanCleanup(roots: [CleanupRoot], token: ScanCancellation = ScanCancellation(),
                                   progress: @escaping (Int, String) -> Void = { _, _ in }) -> ScanReport {
        var combined = ScanReport()
        for root in roots {
            if token.isCancelled { combined.cancelled = true; break }
            if !FileManager.default.fileExists(atPath: root.url.path) { continue }
            guard root.url.standardizedFileURL.path == root.url.resolvingSymlinksInPath().path else {
                combined.issues.append(ScanIssue(path: root.url.path, message: "缓存或安装包根路径包含符号链接，已跳过。"))
                continue
            }
            let part = FileScanner.scan(root: root.url, token: token, include: { url in
                guard root.installersOnly else { return true }
                guard ["dmg", "pkg", "iso"].contains(url.pathExtension.lowercased()) else { return false }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true
            }, progress: progress)
            combined.entries += part.entries.map { entry in
                var entry = entry; entry.category = root.title
                if !root.installersOnly {
                    entry.ownerBundleIdentifier = ["Caches", "Logs"].contains(root.url.lastPathComponent)
                        ? entry.url.lastPathComponent : root.url.lastPathComponent
                }
                return entry
            }
            combined.issues += part.issues; combined.visited += part.visited
            combined.cancelled = combined.cancelled || part.cancelled
        }
        combined.entries.sort { $0.bytes > $1.bytes }
        return combined
    }
    public static var applicationRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }
    public static func applications(in roots: [URL] = applicationRoots) -> [ApplicationInfo] {
        var result: [ApplicationInfo] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
                let localized = Bundle(url: url)?.localizedInfoDictionary ?? [:]
                let display = FileManager.default.displayName(atPath: url.path)
                result.append(ApplicationInfo(url: url.standardizedFileURL.resolvingSymlinksInPath(),
                    name: (localized["CFBundleDisplayName"] as? String) ?? (localized["CFBundleName"] as? String) ?? (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? (display.hasSuffix(".app") ? String(display.dropLast(4)) : display),
                    bundleID: info["CFBundleIdentifier"] as? String ?? "",
                    version: info["CFBundleShortVersionString"] as? String ?? "未知",
                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    installed: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                    lastUsed: NSMetadataItem(url: url)?.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func cleanupRoots(aiOnly: Bool = false) -> [CleanupRoot] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if aiOnly {
            return [("Claude 缓存", "Library/Caches/com.anthropic.claudefordesktop"),
                    ("ChatGPT 缓存", "Library/Caches/com.openai.chat"),
                    ("Codex 缓存", "Library/Caches/com.openai.codex"),
                    ("Cursor 缓存", "Library/Caches/com.todesktop.230313mzl4w4u92")].map {
                CleanupRoot(title: $0.0, url: home.appendingPathComponent($0.1), installersOnly: false)
            }
        }
        return [CleanupRoot(title: "应用缓存", url: home.appendingPathComponent("Library/Caches"), installersOnly: false),
                CleanupRoot(title: "应用日志", url: home.appendingPathComponent("Library/Logs"), installersOnly: false),
                CleanupRoot(title: "下载的安装包", url: home.appendingPathComponent("Downloads"), installersOnly: true)]
    }
    public static func relatedPaths(for app: ApplicationInfo, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        func validIdentifier(_ id: String) -> Bool {
            !id.isEmpty && id != "." && id != ".." && !id.contains("/") && !id.contains("\\")
        }
        guard validIdentifier(app.bundleID) else { return [] }
        var identifiers: Set<String> = [app.bundleID]
        // Only identities declared by embedded app extensions belong to this app.
        // Prefix matches and shared group-container names are not ownership evidence.
        let plugins = app.url.appendingPathComponent("Contents/PlugIns")
        if plugins.standardizedFileURL == plugins.resolvingSymlinksInPath(),
           let children = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            for child in children where child.pathExtension == "appex" {
                guard child.standardizedFileURL == child.resolvingSymlinksInPath() else { continue }
                let plist = child.appendingPathComponent("Contents/Info.plist")
                guard plist.standardizedFileURL == plist.resolvingSymlinksInPath(),
                      let data = try? Data(contentsOf: plist),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String, validIdentifier(id) else { continue }
                identifiers.insert(id)
            }
        }
        return identifiers.sorted().flatMap { id in
            ["Library/Caches/\(id)", "Library/Logs/\(id)", "Library/Preferences/\(id).plist",
             "Library/Saved Application State/\(id).savedState", "Library/Application Support/\(id)",
             "Library/Containers/\(id)", "Library/Application Scripts/\(id)"].map {
                home.appendingPathComponent($0)
            }
        }.filter {
            $0.standardizedFileURL == $0.resolvingSymlinksInPath() && FileManager.default.fileExists(atPath: $0.path)
        }
    }
    public static func startupItems() -> [StartupItem] {
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]
        return roots.flatMap { root -> [StartupItem] in
            let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
                let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first ?? ""
                return StartupItem(url: url, label: info["Label"] as? String ?? url.lastPathComponent,
                                   program: program, targetExists: !program.isEmpty && FileManager.default.fileExists(atPath: program))
            }
        }.sorted { $0.label < $1.label }
    }
}
