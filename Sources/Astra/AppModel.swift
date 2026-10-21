import Foundation
import SwiftUI
import AstraCore

@MainActor
final class FilesModel: ObservableObject {
    @Published var detailActive = false
    @Published var report = ScanReport()
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var removing = false
    @Published var didScan = false
    @Published var progress = ""
    @Published var query = ""
    @Published var aiOnly = false
    @Published var aiHistoryAges: [String: Int] = [:]
    @Published var folder: URL?
    @Published var outcomes: [RemovalOutcome] = []
    @Published var message = ""
    private var token = ScanCancellation()
    var allowedRoots: [URL] = []
    var selectedEntries: [FileEntry] { report.entries.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { RemovalService.deduplicated(selectedEntries).reduce(0) { $0 + $1.bytes } }
    var visibleEntries: [FileEntry] { report.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query) } }

    func cancel() { token.cancel(); progress = "正在停止扫描…" }
    func reset() {
        token.cancel(); token = ScanCancellation()
        report = ScanReport(); selected = []; aiHistoryAges = [:]; busy = false; didScan = false; outcomes = []; message = ""; query = ""
    }
    func scanCleanup() {
        guard !busy else { return }
        let roots = Catalog.cleanupRoots(aiOnly: aiOnly)
        let includeAI = aiOnly
        allowedRoots = roots.map { $0.url.standardizedFileURL } + (includeAI ? AICleanupCatalog.roots() + AgentDataCatalog.roots() + [IdleToolCatalog.root()] : [])
        begin()
        let current = token
        Task {
            let result = await Task.detached(priority: .userInitiated) { [weak self] in
                var result = Catalog.scanCleanup(roots: roots, token: current) { count, path in
                    Task { @MainActor in if self?.token === current { self?.progress = "正在检查 · \(count) 项\n\(URL(fileURLWithPath: path).lastPathComponent)" } }
                }
                if !includeAI {
                    result.entries = result.entries.map { item in
                        var item = item
                        item.category = CleanupPresentation.category(for: item.name, original: item.category)
                        return item
                    }
                }
                if includeAI && !current.isCancelled {
                    let extra = AgentDataCatalog.scan(token: current)
                    result.entries += extra.entries; result.issues += extra.issues
                    result.visited += extra.visited; result.cancelled = result.cancelled || extra.cancelled
                    let history = AICleanupCatalog.scan(token: current)
                    result.entries += history.entries; result.issues += history.issues
                    result.visited += history.visited; result.cancelled = result.cancelled || history.cancelled
                    let tools = IdleToolCatalog.scan(token: current)
                    result.entries += tools.entries; result.issues += tools.issues
                    result.visited += tools.visited; result.cancelled = result.cancelled || tools.cancelled
                }
                var extraRoots: [URL] = []
                if !includeAI && !current.isCancelled {
                    let (extra, roots) = DeveloperCleanup.scan(token: current)
                    result.entries += extra.entries; result.issues += extra.issues
                    result.visited += extra.visited; result.cancelled = result.cancelled || extra.cancelled
                    extraRoots = roots
                    result.entries = RemovalService.deduplicated(result.entries).sorted { $0.bytes > $1.bytes }
                }
                return (result, extraRoots)
            }.value
            if token === current {
                let (result, extraRoots) = result
                allowedRoots += extraRoots
                finish(result)
                if !includeAI && !result.cancelled && !current.isCancelled {
                    let running = Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap { $0 } })
                    selected = Set(result.entries.filter {
                        $0.complete && !$0.requiresReview && ["开发工具", "AI 工具", "设计缓存"].contains($0.category)
                        && !CleanupPresentation.isRunning(owner: $0.ownerBundleIdentifier, runningIDs: running)
                    }.map(\.id))
                }
                if !result.cancelled && !current.isCancelled { detailActive = true }
            }
        }
    }
    func scanFolder(_ url: URL) {
        guard !busy else { return }
        folder = url.resolvingSymlinksInPath(); allowedRoots = [folder!]
        begin(); let current = token; let target = folder!
        Task {
            let result = await Task.detached(priority: .userInitiated) { [weak self] in
                FileScanner.scan(root: target, token: current, progress: { count, path in
                    Task { @MainActor in if self?.token === current { self?.progress = "已检查 \(count) 项\n\(URL(fileURLWithPath: path).lastPathComponent)" } }
                })
            }.value
            if token === current { finish(result) }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "分析此目录"; panel.message = "选择要查看空间占用的文件夹"
        if panel.runModal() == .OK, let url = panel.url { scanFolder(url) }
    }
    private func begin() {
        token.cancel(); token = ScanCancellation(); busy = true; removing = false
        selected = []; aiHistoryAges = [:]; report = ScanReport(); outcomes = []; message = ""; progress = "正在读取文件…"
    }
    private func finish(_ value: ScanReport) {
        report = value; busy = false; didScan = true
        progress = value.cancelled ? "扫描已取消，以下为部分结果" : "已检查 \(value.visited) 项"
    }
    func removeSelected() {
        guard !busy, !selectedEntries.isEmpty else { return }
        let entries = selectedEntries; let roots = allowedRoots
        busy = true; removing = true; progress = "正在重新校验并移入废纸篓…"
        Task {
            let results = await Task.detached(priority: .userInitiated) { RemovalService.trash(entries, allowedRoots: roots) }.value
            outcomes = results
            let removed = Set(results.filter { $0.error == nil }.map { $0.original.path })
            report.entries.removeAll { removed.contains($0.url.path) }
            selected = []; busy = false; removing = false
            message = "\(removed.count) 项已移入废纸篓，\(results.count - removed.count) 项未处理"
        }
    }
    func loadCandidates(_ entries: [FileEntry], roots: [URL], issues: [ScanIssue] = []) {
        reset(); allowedRoots = roots; report.entries = entries; report.issues = issues; didScan = true
    }
}

@MainActor
final class SoftwareModel: ObservableObject {
    @Published var apps: [ApplicationInfo] = []
    @Published var sizes: [String: Int64] = [:]
    @Published var query = ""
    @Published var loading = false
    @Published var preparing = false
    @Published var error = ""
    @Published var updates: [BrewUpdate] = []
    @Published var updateMessage = ""
    @Published var checking = false
    @Published var startup: [StartupItem] = []
    enum Sort: String, CaseIterable { case name = "名称", size = "占用体积", recent = "最近使用", installed = "安装日期" }
    @Published var sort = Sort.recent
    @Published var ascending = true
    func changeSort(_ value: Sort) {
        if sort == value { ascending.toggle() } else { sort = value; ascending = value != .size }
    }
    let candidates = FilesModel()
    var filtered: [ApplicationInfo] {
        let list = apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
        return list.sorted { a, b in
            let result: ComparisonResult
            switch sort {
            case .name: result = a.name.localizedStandardCompare(b.name)
            case .size:
                guard let av = sizes[a.id] else { return sizes[b.id] == nil ? a.id < b.id : false }
                guard let bv = sizes[b.id] else { return true }
                result = av == bv ? .orderedSame : av < bv ? .orderedAscending : .orderedDescending
            case .recent, .installed:
                let av = sort == .recent ? a.lastUsed : a.installed
                let bv = sort == .recent ? b.lastUsed : b.installed
                guard let av else { return bv == nil ? a.id < b.id : false }
                guard let bv else { return true }
                result = av.compare(bv)
            }
            if result == .orderedSame { return a.id < b.id }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
    func load() {
        guard !loading else { return }; loading = true; error = ""
        Task {
            let list = await Task.detached { Catalog.applications() }.value
            apps = list
            startup = await Task.detached { Catalog.startupItems() }.value
            loading = false
            calculateSizes()
        }
    }
    func calculateSizes() {
        guard !loading else { return }; loading = true
        let list = apps
        Task {
            for app in list {
                let size = await Task.detached(priority: .utility) { try? FileScanner.measure(url: app.url).bytes }.value
                if let size { sizes[app.id] = size }
            }
            loading = false
        }
    }
    func prepare(_ app: ApplicationInfo, completion: @escaping () -> Void) { prepare([app], completion: completion) }
    func prepare(_ chosen: [ApplicationInfo], completion: @escaping () -> Void) {
        guard !preparing else { return }; preparing = true; error = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([FileEntry], [URL], [ScanIssue]) in
                let paths = chosen.flatMap { [$0.url] + Catalog.relatedPaths(for: $0) }
                var entries: [FileEntry] = []; var issues: [ScanIssue] = []
                for app in chosen {
                  for path in [app.url] + Catalog.relatedPaths(for: app) {
                    do {
                        var entry = try FileScanner.measure(url: path)
                        entry.category = path == app.url ? "应用程序" : "关联数据（请核对）"
                        entry.ownerApplicationURL = app.url
                        entries.append(entry)
                    } catch { issues.append(ScanIssue(path: path.path, message: error.localizedDescription)) }
                }
                }
                return (entries, paths.map { $0.deletingLastPathComponent().resolvingSymlinksInPath() }, issues)
            }.value
            candidates.loadCandidates(result.0, roots: result.1, issues: result.2)
            preparing = false; completion()
        }
    }
    func checkUpdates() {
        guard !checking else { return }; checking = true; updateMessage = "正在查询 Homebrew…"; updates = []
        Task {
            let result = await Task.detached { Result { try UpdateService.check() } }.value
            switch result {
            case .success(let list): updates = list; updateMessage = list.isEmpty ? "本地 Homebrew 元数据中未发现可更新的应用。" : "发现 \(list.count) 个可更新应用。"
            case .failure(let err): updateMessage = err.localizedDescription
            }
            checking = false
        }
    }
}
