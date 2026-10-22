import Foundation
import CryptoKit
import Darwin

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let fileCount: Int
    public let isDirectory: Bool
    public let fingerprint: String
    public let complete: Bool
    public var category: String = "文件"
    public var requiresReview = false
    public var historyDate: Date?
    public var ownerApplicationURL: URL?
    public var ownerBundleIdentifier: String?
    public var name: String { url.lastPathComponent }
}

public struct ScanIssue: Identifiable, Sendable {
    public var id: String { path + message }
    public let path: String
    public let message: String
    public let permissionDenied: Bool
    public init(path: String, message: String) { self.path = path; self.message = message; permissionDenied = false }
    public init(path: String, error: Error) {
        self.path = path; message = error.localizedDescription
        permissionDenied = Self.isPermissionError(error as NSError)
    }
    private static func isPermissionError(_ error: NSError, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        if error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) { return true }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionError(underlying, depth: depth + 1) }
        return false
    }
}

public struct ScanReport: Sendable {
    public var entries: [FileEntry] = []
    public var largestFiles: [FileEntry] = []
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public var visited = 0
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    public init() {}
}

public enum AstraError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum FileSizeMetric: Sendable { case logical, allocated }

public enum FileScanner {
    private final class Context {
        let token: ScanCancellation
        let metric: FileSizeMetric
        let progress: (Int, String) -> Void
        var inodes = Set<String>()
        var issues: [ScanIssue] = []
        var largest: [FileEntry] = []
        var visited = 0
        init(_ token: ScanCancellation, _ progress: @escaping (Int, String) -> Void, metric: FileSizeMetric = .logical) {
            self.token = token; self.progress = progress; self.metric = metric
        }
    }

    public static func scan(root: URL, token: ScanCancellation = ScanCancellation(),
                            include: (URL) -> Bool = { _ in true },
                            progress: @escaping (Int, String) -> Void = { _, _ in }) -> ScanReport {
        let context = Context(token, progress)
        var result = ScanReport()
        if token.isCancelled { result.cancelled = true; return result }
        do {
            let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
            let children = try FileManager.default.contentsOfDirectory(at: canonical, includingPropertiesForKeys: nil)
                .sorted { $0.path < $1.path }
            for child in children {
                if token.isCancelled { break }
                if !include(child) { continue }
                do {
                    if let item = try walk(child, depth: 0, context: context) { result.entries.append(item) }
                } catch { context.issues.append(ScanIssue(path: child.path, error: error)) }
            }
        } catch { context.issues.append(ScanIssue(path: root.path, error: error)) }
        result.entries.sort { $0.bytes > $1.bytes }
        result.largestFiles = context.largest.sorted { $0.bytes > $1.bytes }.prefix(50).map { $0 }
        result.issues = context.issues
        result.cancelled = token.isCancelled
        result.visited = context.visited
        return result
    }

    public static func measure(url: URL, token: ScanCancellation = ScanCancellation(), metric: FileSizeMetric = .logical) throws -> FileEntry {
        let context = Context(token, { _, _ in }, metric: metric)
        guard let result = try walk(url.standardizedFileURL, depth: 0, context: context), result.complete,
              !token.isCancelled, context.issues.isEmpty else {
            throw AstraError.message("未能完整读取该项目，或项目是符号链接，请重新扫描。")
        }
        return result
    }

    private static func walk(_ url: URL, depth: Int, context: Context) throws -> FileEntry? {
        if context.token.isCancelled { throw AstraError.message("扫描已取消") }
        guard depth < 128, context.visited < 300_000 else { throw AstraError.message("达到扫描上限，请选择更小的目录。") }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let kind = info.st_mode & mode_t(S_IFMT)
        if kind == mode_t(S_IFLNK) { return nil }
        guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { return nil }
        context.visited += 1
        if context.visited % 100 == 0 { context.progress(context.visited, url.path) }
        let directory = kind == mode_t(S_IFDIR)
        let stamp = "\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        var digest = SHA256(); digest.update(data: Data(stamp.utf8))
        var bytes: Int64 = 0; var count = 0; var complete = true
        if directory {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            for child in children {
                if context.token.isCancelled { complete = false; break }
                do {
                    if let item = try walk(child, depth: depth + 1, context: context) {
                        bytes += item.bytes; count += item.fileCount; complete = complete && item.complete
                        digest.update(data: Data((child.lastPathComponent + "\0" + item.fingerprint).utf8))
                    } else {
                        // Include link metadata in the signature, without touching its target.
                        let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: child.path)) ?? "特殊文件"
                        digest.update(data: Data((child.lastPathComponent + "\0" + target).utf8))
                    }
                } catch {
                    complete = false
                    context.issues.append(ScanIssue(path: child.path, error: error))
                }
            }
        } else {
            let inode = "\(info.st_dev):\(info.st_ino)"
            if context.inodes.insert(inode).inserted { bytes = context.metric == .allocated ? Int64(info.st_blocks) * 512 : Int64(info.st_size) }
            count = 1
        }
        let item = FileEntry(url: url, bytes: bytes, fileCount: count, isDirectory: directory,
                             fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined(), complete: complete)
        if !directory && bytes > 0 {
            context.largest.append(item)
            if context.largest.count > 100 { context.largest = Array(context.largest.sorted { $0.bytes > $1.bytes }.prefix(50)) }
        }
        return item
    }
}
