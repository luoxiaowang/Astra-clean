import SwiftUI
import AstraCore

/// 清理的概览与结果独立呈现；返回概览时保留分类展开和选择。
struct CleanExperience: View {
    @ObservedObject var model: FilesModel
    @State private var expanded = Set<String>()
    @State private var confirm = false
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    private var groups: [String] { CleanupPresentation.order.filter { name in model.visibleEntries.contains { $0.category == name } } }
    private var runningIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap { $0 } }) }
    private func selectable(_ entry: FileEntry) -> Bool {
        entry.complete && !CleanupPresentation.isRunning(owner: entry.ownerBundleIdentifier, runningIDs: runningIDs)
    }
    private var eligible: Set<String> { Set(model.visibleEntries.filter(selectable).map(\.id)) }
    private var recommended: Set<String> {
        Set(model.visibleEntries.filter { selectable($0) && !$0.requiresReview && ["开发工具", "AI 工具", "设计缓存"].contains($0.category) }.map(\.id))
    }
    private let resultAccent = Color(red: 0.48, green: 0.68, blue: 0.82)

    var body: some View {
        Group {
            if model.detailActive {
                if model.aiOnly { AICleanupDetails(model: model) } else { details }
            } else { overview }
        }
        .sheet(isPresented: $confirm) { RemovalReview(model: model) }
        .background {
            Button("返回概览") {
                if showSearch { showSearch = false; model.query = "" }
                else if !model.removing { model.detailActive = false }
            }.keyboardShortcut(.cancelAction).hidden()
            Button("搜索结果") {
                guard model.detailActive else { return }
                showSearch.toggle(); searchFocused = showSearch
            }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }
    private var overview: some View {
        PlanetHero(planet: model.aiOnly ? .moon : .earth, moon: !model.aiOnly, satelliteAction: { switchMode(true) }, earthAction: model.aiOnly ? { switchMode(false) } : nil) {
            VStack(spacing: 12) {
                Text(model.busy ? (model.removing ? "正在处理" : "正在扫描") : model.didScan ? "共 \(sizeText(model.report.totalBytes))" : (model.aiOnly ? "月引千潮落，镜中万语空" : "让你的 Mac 轻装前行"))
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                HStack(spacing: 8) {
                    Text(model.busy || model.didScan ? model.progress : (model.aiOnly ? "" : "缓存、日志与安装包 · 在本机扫描")).lineLimit(1)
                    if model.didScan && !model.busy { Button("重新扫描") { model.scanCleanup() }.buttonStyle(.plain).foregroundStyle(Color(red: 0.5, green: 0.7, blue: 0.86)) }
                }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).padding(.top, 2)
                if model.busy {
                    ProgressView().controlSize(.small)
                    if !model.removing { Button("停止扫描") { model.cancel() }.buttonStyle(.plain) }
                } else {
                    Button(model.didScan ? "查看结果" : model.aiOnly ? "扫描 AI 数据" : "开始扫描") {
                        if model.didScan { withAnimation(.easeInOut(duration: 0.18)) { model.detailActive = true } }
                        else { model.scanCleanup() }
                    }.buttonStyle(HeroButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }.frame(maxWidth: 620)
        }
        .background(model.aiOnly ? Color(red: 0.10, green: 0.16, blue: 0.18) : .clear)
    }
    private func switchMode(_ ai: Bool) {
        guard !model.busy else { return }
        withAnimation(.easeInOut(duration: 0.3)) { model.reset(); model.aiOnly = ai; model.detailActive = false }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("准备开始清理").font(.system(size: 24, weight: .semibold))
                    Text("已选 \(sizeText(model.selectedBytes)) · \(model.selectedEntries.count) 项 · \(groups.count) 类 · 扫描共 \(sizeText(model.report.totalBytes))")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button { showSearch.toggle(); searchFocused = showSearch } label: { Image(systemName: "magnifyingglass") }.help("搜索结果（⌘F）")
                Button { model.detailActive = false; model.scanCleanup() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy).help("重新扫描")
                Button { model.detailActive = false } label: { Image(systemName: "xmark.circle.fill") }.help("返回概览（Esc）")
            }.buttonStyle(.plain).font(.system(size: 17)).padding(.top, 28)
            if showSearch { TextField("筛选名称或分类", text: $model.query).textFieldStyle(.roundedBorder).focused($searchFocused) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(groups, id: \.self) { group in category(group) }
                    if groups.isEmpty { EmptyState(symbol: "checkmark.circle", title: "没有符合条件的项目", detail: "可调整搜索条件或重新扫描。") }
                    IssueList(issues: model.report.issues, retry: { model.detailActive = false; model.scanCleanup() })
                    OutcomeList(outcomes: model.outcomes)
                    if !model.message.isEmpty { InlineNotice(text: model.message) }
                }.padding(.vertical, 8)
            }
            HStack(spacing: 12) {
                Text("已选 \(model.selected.count) 项").fontWeight(.medium)
                Button("全选") { model.selected.formUnion(eligible) }
                Text("·").foregroundStyle(.secondary)
                Button("全不选") { model.selected = [] }
                Text("·").foregroundStyle(.secondary)
                Button("推荐") { model.selected = recommended }
                Spacer()
                Button("移入废纸篓 · \(sizeText(model.selectedBytes))") { confirm = true }
                    .buttonStyle(HeroButtonStyle()).disabled(model.busy || model.selectedEntries.isEmpty)
            }.buttonStyle(.plain).font(.system(size: 12)).padding(.vertical, 16)
                .disabled(model.busy)
        }.padding(.horizontal, 24)
    }
    private func category(_ name: String) -> some View {
        let entries = model.visibleEntries.filter { $0.category == name }
        let ids = Set(entries.filter(selectable).map(\.id))
        let selectedCount = model.selected.intersection(ids).count
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    if !ids.isEmpty && ids.isSubset(of: model.selected) { model.selected.subtract(ids) }
                    else { model.selected.formUnion(ids) }
                } label: {
                    Image(systemName: selectedCount == 0 ? "square" : selectedCount == entries.count ? "checkmark.square.fill" : "minus.square.fill")
                        .font(.system(size: 18)).foregroundStyle(selectedCount == 0 ? .white.opacity(0.4) : resultAccent)
                }.buttonStyle(.plain).disabled(model.busy || ids.isEmpty).accessibilityLabel("选择分类 \(name)")
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(name)  已选 \(selectedCount)/\(entries.count)").font(.system(size: 14, weight: .semibold))
                            Text(CleanupPresentation.description(name)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Text("\(sizeText(entries.filter { model.selected.contains($0.id) }.reduce(0) { $0 + $1.bytes })) / \(sizeText(entries.reduce(0) { $0 + $1.bytes }))")
                            .foregroundStyle(resultAccent).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        Image(systemName: expanded.contains(name) ? "chevron.up" : "chevron.down").font(.system(size: 11)).padding(.leading, 14)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(18)
            if expanded.contains(name) {
                ForEach(entries) { entry in
                    HStack(spacing: 14) {
                        if !selectable(entry) {
                            Image(systemName: "lock.square").foregroundStyle(.white.opacity(0.4)).frame(width: 20)
                        } else {
                            Toggle(entry.name, isOn: Binding(get: { model.selected.contains(entry.id) }, set: {
                                if $0 { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) }
                            })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy).frame(width: 20)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name).font(.system(size: 13, weight: .medium))
                                if entry.requiresReview { Text("需确认").foregroundStyle(.orange) }
                                if !selectable(entry) { Text(entry.complete ? "使用中" : "未完整读取").foregroundStyle(.secondary) }
                            }
                            Text(entry.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: "~/"))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(sizeText(entry.bytes)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                        Image(systemName: "shield").foregroundStyle(.white.opacity(0.45)).help("清理前校验路径、文件变化及应用运行状态")
                        Button { reveal(entry.url) } label: { Image(systemName: "folder") }
                            .buttonStyle(.plain).help("在访达中显示")
                    }.padding(.horizontal, 28).padding(.vertical, 9)
                    .contextMenu {
                        Button("在访达中显示") { reveal(entry.url) }
                        Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url.path, forType: .string) }
                    }
                }
            }
        }.background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
            .frame(minWidth: 196).padding(.horizontal, 20).padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
