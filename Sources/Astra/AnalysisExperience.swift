import SwiftUI
import AstraCore

struct AnalysisExperience: View {
    @ObservedObject var model: FilesModel
    @State private var hovered: String?
    @State private var largestMode = false
    private var listedEntries: [FileEntry] { largestMode ? model.report.largestFiles.sorted { $0.bytes > $1.bytes } : entries }
    private var entries: [FileEntry] { model.report.entries.sorted { $0.bytes > $1.bytes } }
    private let colors: [Color] = [Color(red: 0.56, green: 0.41, blue: 0.33), Color(red: 0.60, green: 0.43, blue: 0.23), Color(red: 0.63, green: 0.32, blue: 0.20), Color(red: 0.42, green: 0.35, blue: 0.30), Color(red: 0.64, green: 0.48, blue: 0.33)]
    var body: some View {
        Group {
            if model.folder == nil {
                PlanetHero(planet: .jupiter) {
                    VStack(spacing: 30) {
                        Text("方寸藏万象，一览知轻重").font(.custom("Songti SC", size: 18)).foregroundStyle(.white.opacity(0.75))
                        Button("分析磁盘") { model.chooseFolder() }.buttonStyle(HeroButtonStyle()).keyboardShortcut(.defaultAction)
                        Button("扫描整个磁盘") { model.scanFolder(URL(fileURLWithPath: "/")) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            } else { explorer }
        }
        .background {
            Button("上一级") { goUp() }.keyboardShortcut(.upArrow, modifiers: .command).hidden()
            Button("选择文件夹") { model.chooseFolder() }.keyboardShortcut("o", modifiers: .command).hidden()
        }
    }
    private var explorer: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 18) {
                PlanetView(planet: .jupiter).frame(width: 96, height: 96).padding(.top, 8)
                Text("\(entries.count) 项 · \(sizeText(model.report.totalBytes))").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 4) {
                    modeButton("当前目录", largest: false)
                    modeButton("最大文件", largest: true)
                }.padding(3).background(.white.opacity(0.05), in: Capsule()).padding(.top, 6)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if largestMode && listedEntries.isEmpty && !model.busy {
                            Text("没有可显示的文件").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
                        }
                        ForEach(listedEntries) { entry in
                            Button { enter(entry) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.isDirectory ? "folder" : "doc").foregroundStyle(Color(red: 0.72, green: 0.57, blue: 0.4))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        if largestMode { Text(entry.url.deletingLastPathComponent().path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                                        Text((entry.complete ? "" : "≥ ") + sizeText(entry.bytes)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                    }
                                    Spacer(minLength: 0)
                                    if entry.isDirectory { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                                }.padding(.vertical, 10).padding(.horizontal, 8)
                                    .background(hovered == entry.id ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                                .onHover { hovered = $0 ? entry.id : nil }
                                .help(entry.url.path)
                                .contextMenu { entryMenu(entry) }
                        }
                    }
                }
                if largestMode {
                    Text(model.report.cancelled || !model.report.issues.isEmpty ? "已读取范围内最大的 50 个文件" : "递归扫描中最大的 50 个文件")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Button("选择其他文件夹") { model.chooseFolder() }.buttonStyle(.plain).font(.system(size: 11)).padding(.bottom, 14).disabled(model.busy)
            }.frame(width: 230)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button { goUp() } label: { Image(systemName: "chevron.left") }.disabled(model.busy || model.folder?.path == "/")
                    Menu {
                        ForEach(ancestors, id: \.path) { url in Button(url.path == "/" ? "整个磁盘" : url.lastPathComponent) { model.scanFolder(url) } }
                    } label: { Text(model.folder?.path == "/" ? "整个磁盘" : model.folder?.lastPathComponent ?? "目录").fontWeight(.semibold) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                    Spacer()
                    Text(model.busy ? model.progress : "\(model.report.cancelled ? "已停止 · 部分文件" : "文件") \(sizeText(model.report.totalBytes))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    Button { if model.busy { model.cancel() } else if let url = model.folder { model.scanFolder(url) } } label: {
                        Image(systemName: model.busy ? "xmark" : "arrow.clockwise")
                    }.help(model.busy ? "停止扫描" : "刷新当前文件夹")
                }.buttonStyle(.plain).padding(.vertical, 10)
                if model.busy {
                    Spacer(); PlanetView(planet: .jupiter).frame(width: 180, height: 180)
                    ProgressView(); Text(model.progress).font(.system(size: 12)).foregroundStyle(.secondary); Spacer()
                } else if entries.isEmpty {
                    Spacer(); EmptyState(symbol: "folder", title: "当前目录没有可显示的项目", detail: model.report.cancelled ? "扫描已停止，可刷新重试。" : "请查看读取说明或选择其他目录。"); Spacer()
                } else {
                    GeometryReader { proxy in
                        let shown = Array(entries.prefix(300))
                        let rects = TreemapLayout.rectangles(weights: shown.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: proxy.size))
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                                let rect = rects[index]
                                if rect.width > 3 && rect.height > 3 {
                                    Button { enter(entry) } label: {
                                        VStack(spacing: 5) {
                                            if rect.width > 80 && rect.height > 50 {
                                                Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc").lineLimit(1)
                                                Text((entry.complete ? "" : "≥ ") + sizeText(entry.bytes)).font(.system(size: 12))
                                            } else if rect.width > 30 && rect.height > 25 { Image(systemName: "ellipsis") }
                                        }.font(.system(size: 14, weight: .semibold)).padding(8)
                                            .frame(width: max(0, rect.width - 4), height: max(0, rect.height - 4))
                                            .background(colors[index % colors.count].opacity(hovered == entry.id ? 1 : 0.92), in: RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(.plain).position(x: rect.midX, y: rect.midY)
                                        .help("\(entry.name) · \(sizeText(entry.bytes))")
                                        .onHover { hovered = $0 ? entry.id : nil }
                                        .contextMenu { entryMenu(entry) }
                                }
                            }
                        }
                    }
                }
                IssueList(issues: model.report.issues, retry: { if let folder = model.folder { model.scanFolder(folder) } })
                Text(entries.count > 300 ? "树图展示最大的 300 项；左侧列出全部项目" : "点击文件夹进入 · 右键打开或复制路径 · ⌘↑ 返回上一级")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 16).padding(.bottom, 16)
    }
    private func modeButton(_ title: String, largest: Bool) -> some View {
        Button { largestMode = largest; hovered = nil } label: {
            Text(title).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                .foregroundStyle(.white.opacity(largestMode == largest ? 0.95 : 0.5))
                .background(largestMode == largest ? .white.opacity(0.10) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(largestMode == largest ? .isSelected : [])
    }
    private var ancestors: [URL] {
        guard var url = model.folder else { return [] }; var list = [url]
        while url.path != "/" { url = url.deletingLastPathComponent(); list.append(url) }
        return list.reversed()
    }
    private func enter(_ entry: FileEntry) { if entry.isDirectory { model.scanFolder(entry.url) } else { reveal(entry.url) } }
    private func goUp() { if let url = model.folder, url.path != "/", !model.busy { model.scanFolder(url.deletingLastPathComponent()) } }
    @ViewBuilder private func entryMenu(_ entry: FileEntry) -> some View {
        Button("在访达中打开") { reveal(entry.url) }
        Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url.path, forType: .string) }
    }
}
