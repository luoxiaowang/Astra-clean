import SwiftUI
import AstraCore

struct FilesView: View {
    @ObservedObject var model: FilesModel
    let isAnalysis: Bool
    @State private var review = false
    @State private var showLargest = false
    @State private var limit = 150
    var displayed: [FileEntry] {
        if isAnalysis && showLargest {
            return model.report.largestFiles.filter { model.query.isEmpty || $0.name.localizedCaseInsensitiveContains(model.query) }
        }
        return model.visibleEntries
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: isAnalysis ? "空间洞察" : "轻盈日常", title: isAnalysis ? "空间，都去了哪里？" : "留出空间，装下更多。",
                    subtitle: isAnalysis ? "从一个文件夹开始，逐层查看真实占用。" : "梳理缓存、日志和安装包，把选择权留给你。")
                if !model.didScan && !model.busy { landing } else { results }
                if !isAnalysis {
                    HStack(alignment: .top, spacing: 16) {
                        featureCard("folder.badge.gearshape", "缓存与日志", "查看路径与大小，确认后清理")
                        featureCard("arrow.down.doc", "安装包", "仅扫描下载目录中的安装文件")
                        featureCard("sparkles", "AI 工具", "单独查看已知工具的缓存")
                    }
                }
                InlineNotice(text: isAnalysis ? "显示逻辑文件大小，硬链接在同次扫描内去重；APFS 克隆与压缩会使合计不同于实际磁盘占用。符号链接不跟随。" : "扫描不会删除文件。退出相关应用后再清理缓存，可减少应用重建文件造成的冲突。")
            }.padding(36).padding(.top, 18)
        }.sheet(isPresented: $review) { RemovalReview(model: model) }
    }
    private var landing: some View {
        Panel {
            HStack(spacing: 26) {
                OrbitGraphic()
                VStack(alignment: .leading, spacing: 16) {
                    Text(isAnalysis ? "每一份占用，都有迹可循。" : "一次扫描，心中有数。").font(.system(size: 21, weight: .medium)).foregroundStyle(Palette.text)
                    Text(isAnalysis ? "选择需要分析的目录，查看子文件夹和大文件。\n所有统计都在本机完成。" : "先看清，再决定。\n所有项目默认不勾选，移除时进入废纸篓。")
                        .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Palette.muted)
                    if !isAnalysis { modePicker }
                    PrimaryButton(title: isAnalysis ? "选择文件夹" : "开始扫描", symbol: isAnalysis ? "folder" : "sparkle") {
                        isAnalysis ? model.chooseFolder() : model.scanCleanup()
                    }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 18)
        }
    }
    private var modePicker: some View {
        Picker("扫描范围", selection: $model.aiOnly) {
            Text("日常清理").tag(false); Text("AI 工具缓存").tag(true)
        }.pickerStyle(.segmented).frame(width: 240).disabled(model.busy)
            .onChange(of: model.aiOnly) { _, _ in model.reset() }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.busy ? (model.removing ? "正在处理" : "正在扫描") : (model.report.cancelled ? "部分扫描结果" : "扫描发现"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Text(sizeText(model.report.totalBytes)).font(.system(size: 34, weight: .medium, design: .rounded)).foregroundStyle(Palette.text).monospacedDigit()
                        Text(model.progress).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    Spacer()
                    if model.busy {
                        ProgressView().controlSize(.small).padding(.trailing, 10)
                        if !model.removing { Button("停止扫描") { model.cancel() } }
                    } else {
                        VStack(alignment: .trailing, spacing: 12) {
                            if !isAnalysis {
                                PrimaryButton(title: "检查所选 \(model.selected.count) 项", symbol: "arrow.right", disabled: model.selected.isEmpty) { review = true }
                                Text("选中 \(sizeText(model.selectedBytes))").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Button(isAnalysis ? "选择其他目录" : "重新扫描") {
                                if isAnalysis { model.chooseFolder() } else { model.scanCleanup() }
                            }.font(.system(size: 11))
                        }
                    }
                }
            }
            if let folder = model.folder, isAnalysis {
                HStack {
                    Button { showLargest = false; model.scanFolder(folder.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }.disabled(model.busy || folder.path == "/")
                    Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).help(folder.path)
                    Spacer()
                    Button("在访达中显示") { reveal(folder) }.font(.system(size: 11))
                }
            }
            if !model.message.isEmpty { InlineNotice(text: model.message) }
            if !model.outcomes.isEmpty { OutcomeList(outcomes: model.outcomes) }
            if !model.busy {
                HStack {
                    if !isAnalysis { modePicker }
                    else { Picker("视图", selection: $showLargest) { Text("目录层级").tag(false); Text("最大文件").tag(true) }.pickerStyle(.segmented).frame(width: 210) }
                    Spacer()
                    TextField("筛选名称或分类", text: $model.query).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                }
            }
            if model.didScan && displayed.isEmpty && !model.busy {
                EmptyState(symbol: "checkmark.circle", title: model.query.isEmpty ? "没有发现符合条件的项目" : "没有匹配的结果", detail: model.report.issues.isEmpty ? "可选择其他范围再扫描。" : "部分路径未能读取，请查看下方说明。")
            }
            LazyVStack(spacing: 1) {
                ForEach(Array(displayed.prefix(limit))) { entry in
                    FileRow(entry: entry, selected: Binding(get: { model.selected.contains(entry.id) }, set: { value in
                        if value { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) }
                    }), selectable: !isAnalysis, total: max(1, model.report.totalBytes), disabled: model.busy) {
                        if isAnalysis && entry.isDirectory { showLargest = false; model.scanFolder(entry.url) } else { reveal(entry.url) }
                    }
                }
                if displayed.count > limit { Button("再显示 150 项（共 \(displayed.count) 项）") { limit += 150 }.padding() }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
            IssueList(issues: model.report.issues)
        }
    }
    private func featureCard(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FileRow: View {
    let entry: FileEntry
    @Binding var selected: Bool
    var selectable = true
    var total: Int64 = 1
    var disabled = false
    let action: () -> Void
    var body: some View {
        HStack(spacing: 13) {
            if selectable { Toggle("选择 \(entry.name)", isOn: $selected).labelsHidden().toggleStyle(.checkbox).disabled(disabled || !entry.complete) }
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill").font(.system(size: 22)).foregroundStyle(Palette.accent.opacity(0.65)).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(Palette.text)
                Text(entry.url.path).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).help(entry.url.path)
                if !entry.complete { Text("读取不完整，不能移除").font(.system(size: 10)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(sizeText(entry.bytes)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Palette.text)
                if selectable { Text(entry.category).font(.system(size: 9)).foregroundStyle(Palette.muted) }
                else {
                    GeometryReader { geometry in
                        Capsule().fill(Palette.accent.opacity(0.7)).frame(width: max(2, geometry.size.width * min(1, Double(entry.bytes) / Double(total))))
                    }.frame(width: 70, height: 3).background(Palette.raised)
                }
            }
            Button(action: action) { Image(systemName: !selectable && entry.isDirectory ? "chevron.right" : "arrow.up.forward.square").foregroundStyle(Palette.muted) }
                .buttonStyle(.plain).disabled(disabled).help(!selectable && entry.isDirectory ? "进入目录" : "在访达中显示")
        }.padding(14).background(Palette.sidebar)
    }
}
struct IssueList: View {
    let issues: [ScanIssue]
    var retry: (() -> Void)? = nil
    @State private var showPermissions = false
    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if issues.contains(where: \.permissionDenied) {
                    Button("读取权限不足 · 点击查看授权方法") { showPermissions = true }
                        .buttonStyle(.plain).foregroundStyle(.orange)
                }
            DisclosureGroup("\(issues.count) 项读取受限或未完成") {
                ForEach(Array(issues.prefix(60))) { issue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        Text(issue.message).font(.system(size: 10))
                        if issue.permissionDenied {
                            Button("授权帮助") { showPermissions = true }.buttonStyle(.link)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
                if issues.count > 60 { Text("其余 \(issues.count - 60) 项未展开，请选择更小范围重试。") }
            }.font(.system(size: 11)).foregroundStyle(.orange.opacity(0.8))
            }.sheet(isPresented: $showPermissions) { PermissionHelp(retry: retry) }
        }
    }
}
struct OutcomeList: View {
    let outcomes: [RemovalOutcome]
    var body: some View {
        if !outcomes.isEmpty {
            DisclosureGroup("查看处理明细") {
                ForEach(outcomes) { item in
                    HStack(alignment: .top) {
                        Image(systemName: item.error == nil ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(item.error == nil ? Palette.accent : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.original.path).textSelection(.enabled)
                            Text(item.error ?? "已移入废纸篓").foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if let destination = item.destination { Button("查看") { reveal(destination) } }
                    }.font(.system(size: 11)).padding(.vertical, 6)
                }
            }.font(.system(size: 11)).foregroundStyle(Palette.text)
        }
    }
}
