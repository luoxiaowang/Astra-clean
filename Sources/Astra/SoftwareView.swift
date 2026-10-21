import SwiftUI
import AstraCore

struct SoftwareView: View {
    @ObservedObject var model: SoftwareModel
    @State private var segment = 0
    @State private var showCandidates = false
    @State private var selected = Set<String>()
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    private var chosen: [ApplicationInfo] { model.apps.filter { selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(Array(["卸载", "更新", "启动项"].enumerated()), id: \.offset) { index, title in
                        Button { segment = index; model.query = "" } label: {
                            Text(title).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 7)
                                .background(segment == index ? .white.opacity(0.12) : .clear, in: Capsule())
                        }.buttonStyle(.plain).foregroundStyle(.white.opacity(segment == index ? 0.95 : 0.55))
                    }
                }.padding(3).background(.white.opacity(0.05), in: Capsule())
                Button { if segment == 1 { model.checkUpdates() } else { model.load() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 16))
                }.buttonStyle(.plain).help("刷新").disabled(model.loading)
                if model.loading || model.preparing { ProgressView().controlSize(.small) }
                Spacer()
                if segment == 0 {
                    ForEach(SoftwareModel.Sort.allCases, id: \.self) { sort in
                        Button { model.changeSort(sort) } label: {
                            HStack(spacing: 4) {
                                Text(sort.rawValue)
                                if model.sort == sort { Image(systemName: model.ascending ? "arrow.up" : "arrow.down") }
                            }.font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(model.sort == sort ? 0.95 : 0.45))
                        }.buttonStyle(.plain).accessibilityValue(model.sort == sort ? (model.ascending ? "升序" : "降序") : "")
                    }
                }
                if showSearch {
                    TextField("搜索 App", text: $model.query).textFieldStyle(.plain).frame(width: 150).focused($searchFocused)
                    Button { model.query = ""; showSearch = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("清空搜索")
                } else {
                    Button { showSearch = true; searchFocused = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 16)) }.buttonStyle(.plain).help("搜索 App（⌘F）")
                }
            }.frame(height: 36)
            switch segment {
            case 0: uninstall
            case 1: updates
            default: startup
            }
        }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 16)
        .onAppear { if model.apps.isEmpty { model.load() } }
        .sheet(isPresented: $showCandidates, onDismiss: { selected = []; model.load() }) { UninstallSheet(model: model.candidates) }
        .background {
            Button("搜索 App") { showSearch = true; searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden()
            Button("关闭搜索") { model.query = ""; showSearch = false; selected = [] }.keyboardShortcut(.cancelAction).hidden()
        }
    }
    private var uninstall: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("已安装 App  \(model.filtered.count) 个 · \(sizeText(model.filtered.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }))\(model.loading ? " · 正在统计" : "")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 16).padding(.vertical, 12)
                    ForEach(model.filtered) { app in
                        Button {
                            if selected.contains(app.id) { selected.remove(app.id) } else { selected.insert(app.id) }
                        } label: {
                            HStack(spacing: 16) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(app.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                                    HStack(spacing: 8) {
                                        Text(app.version)
                                        Text("·")
                                        Text(model.sizes[app.id].map(sizeText) ?? "正在统计")
                                        Text("·")
                                        Text(activity(app)).foregroundStyle(.white.opacity(0.5))
                                    }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                                }
                                Spacer()
                                Image(systemName: selected.contains(app.id) ? "checkmark.square.fill" : "square").font(.system(size: 19)).foregroundStyle(selected.contains(app.id) ? Palette.accent : .white.opacity(0.35))
                            }.padding(.horizontal, 16).frame(height: 68).contentShape(Rectangle())
                                .background(selected.contains(app.id) ? .white.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("\(app.name)，\(app.version)，\(model.sizes[app.id].map(sizeText) ?? "正在统计")")
                            .accessibilityAddTraits(selected.contains(app.id) ? .isSelected : [])
                            .contextMenu {
                                Button("在访达中显示") { reveal(app.url) }
                                Button("复制路径") { copyText(app.url.path) }
                                Button(selected.contains(app.id) ? "取消选择" : "选择") { if selected.contains(app.id) { selected.remove(app.id) } else { selected.insert(app.id) } }
                            }
                    }
                    if model.filtered.isEmpty && !model.loading { Text("没有匹配的 App").foregroundStyle(.secondary).padding(24) }
                }
            }
            if !selected.isEmpty {
                HStack(spacing: 16) {
                    Text("\(chosen.first?.name ?? "") · \(chosen.count) 个 App · \(sizeText(chosen.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }))").font(.system(size: 12))
                    Button("取消选择") { selected = [] }.buttonStyle(.plain)
                    Spacer()
                    Button(model.preparing ? "正在读取…" : "移除 \(chosen.count) 项") { model.prepare(chosen) { showCandidates = true } }
                        .buttonStyle(HeroButtonStyle()).disabled(model.preparing)
                }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
            if !model.error.isEmpty { Text(model.error).font(.system(size: 11)).foregroundStyle(.orange) }
        }
    }
    private func activity(_ app: ApplicationInfo) -> String {
        guard let date = app.lastUsed else { return "最近使用未知" }
        let formatter = RelativeDateTimeFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date()) + "打开过"
    }
    private var updates: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Panel {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Homebrew 应用更新").font(.system(size: 18, weight: .medium))
                        Text("使用本地 Homebrew 元数据检查 cask。其他来源的应用请在各自应用中检查更新。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        PrimaryButton(title: model.checking ? "正在检查…" : "检查更新", symbol: "arrow.clockwise", disabled: model.checking) { model.checkUpdates() }
                        if !model.updateMessage.isEmpty { InlineNotice(text: model.updateMessage) }
                    }
                }
                ForEach(model.updates.filter { model.query.isEmpty || $0.name.localizedCaseInsensitiveContains(model.query) }) { update in
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(update.name).fontWeight(.medium); Spacer(); Text("\(update.installed) → \(update.latest)").foregroundStyle(Palette.accent) }
                            Text("在终端执行：brew upgrade --cask \(update.name)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        }
                    }
                }
                InlineNotice(text: "第一版提供更新检查和命令提示，不会自动替换应用。本地元数据可能滞后；需要时先在终端执行 brew update。")
            }
        }
    }
    private var startup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("\(model.startup.count) 个可读取的后台服务配置").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("打开登录项设置") { openLoginItems() }
                }
                InlineNotice(text: "这里展示 LaunchAgents / LaunchDaemons 配置，不代表当前运行状态。完整登录项及启停控制请使用系统设置。")
                ForEach(model.startup.filter { model.query.isEmpty || $0.label.localizedCaseInsensitiveContains(model.query) }) { item in
                    Panel {
                        HStack {
                            Image(systemName: "power").foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.label).font(.system(size: 12, weight: .medium))
                                Text(item.program.isEmpty ? "未声明程序路径" : item.program).font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                if !item.targetExists { Text("目标不可见或路径需进一步检查").font(.system(size: 10)).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Button("定位") { reveal(item.url) }
                        }
                    }
                }
            }
        }
    }
}

func openLoginItems() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
}

struct UninstallSheet: View {
    @ObservedObject var model: FilesModel
    @Environment(\.dismiss) var dismiss
    @State private var review = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("卸载明细").font(.system(size: 23, weight: .semibold))
            Text("选择应用和需要一并移除的关联数据，所有项目默认不勾选。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.report.entries) { entry in
                        FileRow(entry: entry, selected: Binding(get: { model.selected.contains(entry.id) }, set: { value in
                            if value { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) }
                        }), disabled: model.busy) { reveal(entry.url) }
                    }
                }
                IssueList(issues: model.report.issues)
                if !model.message.isEmpty { InlineNotice(text: model.message).padding(.top) }
                OutcomeList(outcomes: model.outcomes)
            }.frame(height: 350)
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text("正在校验并处理…").font(.system(size: 11)) }
                Spacer()
                Button("关闭") { dismiss() }.disabled(model.busy)
                PrimaryButton(title: "检查所选 \(model.selected.count) 项", disabled: model.selected.isEmpty || model.busy) { review = true }
            }
        }.padding(28).frame(width: 680).background(Palette.background).preferredColorScheme(.dark)
            .sheet(isPresented: $review) { RemovalReview(model: model) }
    }
}
