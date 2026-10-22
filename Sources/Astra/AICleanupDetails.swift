import SwiftUI
import AstraCore

struct AICleanupDetails: View {
    @ObservedObject var model: FilesModel
    @State private var expanded = Set<String>()
    @State private var confirm = false
    @State private var openCodeSessions: [AgentSession] = []
    @State private var openCodeDays = 0
    @State private var openCodeError = ""
    @State private var loadingOpenCode = true
    @State private var activeHistoryMenu: String?
    private let background = Color(red: 0.10, green: 0.16, blue: 0.18)
    private var historyNames: Set<String> { Set(AICleanupCatalog.histories.map(\.title) + [AgentDataCatalog.cursorHistory]) }
    private var caches: [FileEntry] { model.report.entries.filter { !historyNames.contains($0.category) && $0.category != IdleToolCatalog.category && $0.category != AgentDataCatalog.versionsCategory } }
    private var versions: [FileEntry] { model.report.entries.filter { $0.category == AgentDataCatalog.versionsCategory } }
    private var cacheAndVersions: [FileEntry] { caches + versions }
    private var running: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    private func available(_ entry: FileEntry) -> Bool { entry.complete && !AgentDataCatalog.versionIsProtected(entry) && !CleanupPresentation.isRunning(owner: entry.ownerBundleIdentifier, runningIDs: running) && !(entry.category == IdleToolCatalog.category && IdleToolCatalog.isCurrent(entry)) }
    private func bytes(_ entries: [FileEntry]) -> Int64 { entries.reduce(0) { $0 + $1.bytes } }
    private var tools: [FileEntry] { model.report.entries.filter { $0.category == IdleToolCatalog.category } }
    private var blockedBytes: Int64 { bytes(cacheAndVersions.filter { !available($0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI 工具清理与维护").font(.system(size: 22, weight: .semibold))
                    Text("可选缓存与旧版本 \(sizeText(bytes(cacheAndVersions.filter(available)))) · 缓存、临时文件和旧版本" + (blockedBytes > 0 ? " · \(sizeText(blockedBytes)) 正在使用或未完整读取" : ""))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button { model.detailActive = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45)).help("返回概览")
            }.padding(.top, 28).padding(.bottom, 26)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    section("缓存与旧版本", amount: bytes(cacheAndVersions), note: "缓存可重新生成；使用中的应用数据保留") {
                        selectableRow("缓存和临时文件", subtitle: "Claude、ChatGPT、Codex、Cursor、OpenCode 的缓存，需要时自动重建", entries: caches)
                        Divider().overlay(.white.opacity(0.04)).padding(.leading, 44)
                        selectableRow("Claude Code 安装版本", subtitle: "保留当前命令入口指向的版本；旧版本需手动选择", entries: versions)
                    }
                    section("对话与 worktree", amount: bytes(model.selectedEntries.filter { historyNames.contains($0.category) }), note: "选择保留天数，展开逐项确认后再清理") {
                        ForEach(AICleanupCatalog.histories.map(\.title) + [AgentDataCatalog.cursorHistory], id: \.self) { name in
                            historyRow(name)
                            Divider().overlay(.white.opacity(0.04)).padding(.leading, 44)
                        }
                        openCodeHistory
                        Divider().overlay(.white.opacity(0.04)).padding(.leading, 44)
                        infoRow("worktree", detail: "工作树需核对未提交改动与所属任务，当前不列入清理", symbol: "lock")
                    }
                    section("闲置工具与维护", amount: bytes(tools), note: "检查工具安装版本，保留当前版本与共享数据") {
                        if tools.isEmpty {
                            infoRow("Cursor Agent", detail: "未发现可读取的安装版本", symbol: "app.dashed")
                        } else {
                            selectableRow("Cursor Agent", subtitle: IdleToolCatalog.modificationSummary(tools) + "；只可选择旧版本，保留对话和设置", entries: tools)
                        }
                    }
                    IssueList(issues: model.report.issues, retry: { model.detailActive = false; model.scanCleanup() })
                    OutcomeList(outcomes: model.outcomes)
                    if !model.message.isEmpty { InlineNotice(text: model.message) }
                }.padding(.vertical, 8)
            }
            HStack {
                Text("已选 \(model.selectedEntries.count) 项").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("移到废纸篓 · \(sizeText(model.selectedBytes))") { confirm = true }
                    .buttonStyle(HeroButtonStyle()).disabled(model.busy || model.selectedEntries.isEmpty)
            }.padding(.vertical, 18)
        }.padding(.horizontal, 22).background(background)
            .sheet(isPresented: $confirm) { RemovalReview(model: model) }
            .task {
                let result = await Task.detached { () -> Result<[AgentSession], Error> in
                    Result { try AgentDataCatalog.openCodeSessions(token: ScanCancellation()) }
                }.value
                switch result { case .success(let sessions): openCodeSessions = sessions
                case .failure(let error): openCodeError = error.localizedDescription }
                loadingOpenCode = false
            }
    }
    private var openCodeHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenCode 聊天记录").fontWeight(.semibold)
                    Text(loadingOpenCode ? "正在读取会话…" : "\(openCodeSessions.count) 个会话 · 关联消息 \(sizeText(openCodeSessions.reduce(0) { $0 + $1.bytes }))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("查看时间", selection: $openCodeDays) {
                    Text("暂不查看").tag(0)
                    ForEach([15, 30, 90, 120], id: \.self) { days in Text("\(days) 天之前").tag(days) }
                }.frame(width: 180)
            }
            Text("只读预览；数据量不是可释放磁盘空间，暂不支持数据库会话删除。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !openCodeError.isEmpty { Text(openCodeError).foregroundStyle(.orange) }
            if openCodeDays > 0 {
                let matches = openCodeSessions.filter { $0.updated < Date().addingTimeInterval(-Double(openCodeDays) * 86400) }
                Text("符合条件 \(matches.count) 个会话").font(.system(size: 12))
                ForEach(matches) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title.isEmpty ? session.id : session.title)
                            Text(session.updated.formatted(date: .numeric, time: .shortened)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(sizeText(session.bytes))
                    }.font(.system(size: 11)).padding(.vertical, 5)
                }
            }
        }.padding(16)
    }
    private func section<Content: View>(_ title: String, amount: Int64?, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 13) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let amount { Text(sizeText(amount)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)) }
                Spacer()
                Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            VStack(spacing: 0, content: content).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.035)))
        }
    }
    private func historyRow(_ name: String) -> some View {
        let unit = name == AgentDataCatalog.cursorHistory ? "个文件历史分组" : "个会话文件"
        let all = model.report.entries.filter { $0.category == name }
        let days = model.aiHistoryAges[name, default: 0]
        let matching = all.filter { AICleanupCatalog.olderThan(days, entry: $0) }
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: days == 0 ? "lock" : "clock").foregroundStyle(.white.opacity(0.3)).frame(width: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.system(size: 14, weight: .semibold))
                    Text("\(all.count) \(unit)，共 \(sizeText(bytes(all)))，" + (days == 0 ? "选择天数后列出" : "\(matching.count) 项超过 \(days) 天"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button { activeHistoryMenu = name } label: {
                    HStack(spacing: 10) {
                        Text(days == 0 ? "暂不清理" : "\(days) 天之前")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 5)
                        .background(.white.opacity(0.06), in: Capsule())
                }.buttonStyle(.plain).disabled(model.busy)
                    .accessibilityLabel(name + "保留天数")
                    .popover(isPresented: Binding(get: { activeHistoryMenu == name }, set: { if !$0 { activeHistoryMenu = nil } }), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach([15, 30, 90, 120, 0], id: \.self) { value in
                                let candidates = all.filter { AICleanupCatalog.olderThan(value, entry: $0) }
                                Button {
                                    model.aiHistoryAges[name] = value
                                    model.selected.subtract(all.map(\.id))
                                    expanded.insert(name)
                                    activeHistoryMenu = nil
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(value == 0 ? "暂不清理" : "\(value) 天之前").font(.system(size: 14, weight: .semibold))
                                            if value > 0 {
                                                Text("\(candidates.count) \(unit) · \(sizeText(bytes(candidates)))")
                                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if days == value { Image(systemName: "checkmark") }
                                    }.padding(10).frame(width: 230, alignment: .leading).contentShape(Rectangle())
                                        .background(days == value ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                            Text("按最后修改时间筛选；文件历史取组内最新时间。使用中项目不可选。")
                                .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 230).padding(8)
                        }.padding(8).preferredColorScheme(.dark)
                    }
                Text(sizeText(bytes(all.filter { model.selected.contains($0.id) }))).font(.system(size: 13, weight: .semibold)).frame(width: 86, alignment: .trailing)
            }.padding(16)
            if days > 0 {
                selectableRow(name, subtitle: "候选 \(matching.count) 项 · \(sizeText(bytes(matching)))；请展开核对并手动勾选", entries: matching)
                    .onAppear { expanded.insert(name) }
                if matching.isEmpty {
                    Text("没有最后修改时间早于 \(days) 天的会话文件，可选择更短的保留时间。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
    }
    private func infoRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(.white.opacity(0.3)).frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text("未纳入").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
        }.padding(16)
    }
    private func selectableRow(_ name: String, subtitle: String, entries: [FileEntry]) -> some View {
        let ids = Set(entries.filter(available).map(\.id))
        let count = model.selected.intersection(ids).count
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    if !ids.isEmpty && ids.isSubset(of: model.selected) { model.selected.subtract(ids) }
                    else { model.selected.formUnion(ids) }
                } label: {
                    Image(systemName: count == 0 ? "square" : count == ids.count ? "checkmark.square.fill" : "minus.square.fill")
                        .font(.system(size: 18)).foregroundStyle(count == 0 ? .white.opacity(0.35) : Color(red: 0.48, green: 0.68, blue: 0.79))
                }.buttonStyle(.plain).disabled(ids.isEmpty || model.busy).accessibilityLabel("选择 \(name)")
                Button {
                    if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(name).fontWeight(.semibold); Text("已选 \(count)/\(ids.count)").foregroundStyle(.white.opacity(0.5)) }.font(.system(size: 13))
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text("\(sizeText(bytes(entries.filter { model.selected.contains($0.id) }))) / \(sizeText(bytes(entries)))")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: expanded.contains(name) ? "chevron.up" : "chevron.down").font(.system(size: 11)).padding(.leading, 8)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(16)
            if expanded.contains(name) {
                if entries.isEmpty { Text("没有符合条件的文件").font(.system(size: 12)).foregroundStyle(.secondary).padding(14) }
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        Toggle(entry.name, isOn: Binding(get: { model.selected.contains(entry.id) }, set: { value in
                            if value { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) }
                        })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy || !available(entry))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(.system(size: 12))
                            Text(entry.url.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if !available(entry) { Text(entry.category == IdleToolCatalog.category && IdleToolCatalog.isCurrent(entry) ? "当前版本" : AgentDataCatalog.versionIsProtected(entry) ? "当前版本或入口未确认" : "使用中或未完整读取").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Text(sizeText(entry.bytes)).font(.system(size: 12)).monospacedDigit()
                        Button { reveal(entry.url) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("在访达中显示")
                    }.padding(.horizontal, 18).padding(.vertical, 9)
                }
            }
        }
    }
}
