import Foundation

public enum DeveloperCleanup {
    public static let paths = [".npm/_cacache", ".npm/_npx", ".npm/_prebuilds", ".npm/_logs", ".bun/install/cache", ".cargo/registry/src", ".cargo/registry/cache", "Library/pnpm/store", ".nuget/packages", ".local/share/NuGet/http-cache", ".gradle/caches", ".gradle/daemon", "Library/Developer/Xcode/DerivedData"]
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) -> (ScanReport, [URL]) {
        let fm = FileManager.default
        var report = ScanReport(); var roots: [URL] = []
        var candidates = paths.map { home.appendingPathComponent($0) }
        let code = home.appendingPathComponent("Desktop/code")
        // 仅遍历目录名，识别带项目清单的构建目录；不读取源码，不进入依赖或构建树。
        if code.resolvingSymlinksInPath() == code, fm.fileExists(atPath: code.path),
           let walk = fm.enumerator(at: code, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], errorHandler: { url, error in
               report.issues.append(ScanIssue(path: url.path, error: error)); return true
           }) {
            var visited = 0
            for case let url as URL in walk {
                if token.isCancelled { break }
                visited += 1
                if visited > 50_000 { report.issues.append(ScanIssue(path: code.path, message: "项目目录发现达到上限，以下为部分结果。")); break }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                if values.isSymbolicLink == true { walk.skipDescendants(); continue }
                guard values.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if ["target", ".build"].contains(name) {
                    walk.skipDescendants()
                    let manifest = name == "target" ? "Cargo.toml" : "Package.swift"
                    if fm.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(manifest).path) { candidates.append(url) }
                } else if [".git", "node_modules", "vendor", "Pods", "dist", "build"].contains(name) || walk.level > 6 { walk.skipDescendants() }
            }
        }
        for url in candidates {
            if token.isCancelled { report.cancelled = true; break }
            guard fm.fileExists(atPath: url.path) else { continue }
            guard url.standardizedFileURL == url.resolvingSymlinksInPath() else {
                report.issues.append(ScanIssue(path: url.path, message: "专用缓存路径包含符号链接，已跳过。")); continue
            }
            do {
                var entry = try FileScanner.measure(url: url, token: token)
                entry.category = "开发工具"; entry.requiresReview = true
                report.entries.append(entry); report.visited += entry.fileCount
                roots.append(url.deletingLastPathComponent())
            } catch { report.issues.append(ScanIssue(path: url.path, error: error)) }
        }
        report.cancelled = report.cancelled || token.isCancelled
        return (report, roots)
    }
}
