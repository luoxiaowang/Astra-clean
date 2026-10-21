import SwiftUI
import AstraCore

@MainActor
final class MonitorModel: ObservableObject {
    @Published var sample = SystemSnapshot()
    @Published var hardware = HardwareSnapshot()
    @Published var history: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var downHistory: [Double] = []
    @Published var upHistory: [Double] = []
    @Published var processes: [ProcessGroup] = []
    @Published var processError = ""
    private let monitor = SystemMonitor()
    private var updating = false
    func refresh() async {
        guard !updating else { return }; updating = true; defer { updating = false }
        sample = monitor.sample()
        hardware = await Task.detached(priority: .utility) { HardwareSnapshot.read() }.value
        if let cpu = sample.cpu { append(cpu, to: &history) }
        if let gpu = hardware.gpu { append(gpu, to: &gpuHistory) }
        if sample.memoryAvailable { append(Double(sample.memoryUsed) / Double(max(1, sample.memoryTotal)) * 100, to: &memoryHistory) }
        append(sample.download ?? 0, to: &downHistory); append(sample.upload ?? 0, to: &upHistory)
        let result = await Task.detached(priority: .utility) { Result { try ProcessSampler.sample() } }.value
        switch result {
        case .success(let rows): processes = rows; processError = ""
        case .failure(let error): processError = error.localizedDescription
        }
    }
    private func append(_ value: Double, to values: inout [Double]) { values.append(value); if values.count > 45 { values.removeFirst() } }
}

struct StatusView: View {
    @StateObject private var model = MonitorModel()
    @State private var sort = ProcessSort.memory
    @State private var ascending = false
    @State private var query = ""
    @State private var showSearch = false
    @State private var pinned = Set<String>()
    @State private var inspected: ProcessGroup?
    @State private var notice: String?
    @FocusState private var searchFocused: Bool
    enum ProcessSort: String, CaseIterable { case name = "名称", memory = "内存", cpu = "% CPU", energy = "能耗", pid = "PID" }
    private var memoryPercent: Double { Double(model.sample.memoryUsed) / Double(max(1, model.sample.memoryTotal)) * 100 }
    private var pressure: String {
        guard let pressure = model.hardware.memoryPressure else { return "压力不可用" }
        return pressure >= 4 ? "压力很高" : pressure >= 2 ? "压力偏高" : "压力正常"
    }
    private var sorted: [ProcessGroup] {
        let rows = model.processes.filter { $0.matches(query) }
        return rows.sorted { a, b in
            if pinned.contains(a.id) != pinned.contains(b.id) { return pinned.contains(a.id) }
            let comparison: Bool
            switch sort {
            case .name: comparison = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .memory: comparison = a.residentBytes > b.residentBytes
            case .cpu: comparison = a.cpu > b.cpu
            case .energy: comparison = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .pid: comparison = a.pid < b.pid
            }
            let tied = (sort == .memory && a.residentBytes == b.residentBytes) || (sort == .cpu && a.cpu == b.cpu) || ((sort == .name || sort == .energy) && a.name.localizedStandardCompare(b.name) == .orderedSame) || (sort == .pid && a.pid == b.pid)
            if tied { return a.id < b.id }
            return ascending ? !comparison : comparison
        }
    }
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                let first = (proxy.size.width - 36) * 0.3368421053
                let small = (proxy.size.width - 36 - first) / 3
                HStack(spacing: 12) {
                    health.frame(width: first)
                    cpu.frame(width: small)
                    gpu.frame(width: small)
                    memory.frame(width: small)
                }.frame(height: 170)
                HStack(spacing: 12) {
                    battery.frame(width: first)
                    disk.frame(width: small)
                    network.frame(width: small)
                    fan.frame(width: small)
                }.frame(height: 170)
                processTable
            }
        }.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)
            .overlay {
                if let group = inspected {
                    Color.black.opacity(0.35).padding(.top, -88).ignoresSafeArea().onTapGesture { inspected = nil }
                    ProcessInspector(group: group, close: { inspected = nil })
                        .frame(width: 580).padding(24).offset(y: -44)
                }
            }
            .alert("操作说明", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("知道了", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
            .background {
                Button("搜索 App") { showSearch.toggle(); searchFocused = showSearch }.keyboardShortcut("f", modifiers: .command).hidden()
                Button("关闭") { if inspected != nil { inspected = nil } else { showSearch = false; query = "" } }.keyboardShortcut(.cancelAction).hidden()
            }
            .task {
                while !Task.isCancelled {
                    await model.refresh()
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                }
            }
    }
    private var health: some View {
        StatusCard(title: "健康度", icon: "sun.max", tint: .mint, badge: "\(model.sample.cpuName.replacingOccurrences(of: "Apple ", with: ""))  \(model.sample.memoryTotal / 1_073_741_824) GB  macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)") {
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(healthScore.map(String.init) ?? "—").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        Text(healthScore.map { $0 >= 90 ? "很好" : $0 >= 75 ? "良好" : "需关注" } ?? "采样中").font(.system(size: 13))
                    }.help("Astra 根据 CPU 使用率、内存压力和剩余空间计算；不代表硬件诊断结果。")
                    Text(pressure).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                PlanetView(planet: .sun).frame(width: 86, height: 86).frame(height: 70).offset(y: 10).shadow(color: .yellow.opacity(0.18), radius: 18)
            }
            Spacer(minLength: 0)
            Text("已运行 \(Int(model.sample.uptime) / 86400)天\(Int(model.sample.uptime) / 3600 % 24)小时 · \(bootDate) 开机").statusFootnote()
        }
    }
    private var healthScore: Int? {
        guard let cpu = model.sample.cpu, let pressure = model.hardware.memoryPressure, model.sample.memoryAvailable, model.sample.diskTotal > 0 else { return nil }
        let memoryPenalty = pressure >= 4 ? 25 : pressure >= 2 ? 10 : 0
        let diskPenalty = model.sample.diskTotal > 0 && Double(model.sample.diskFree) / Double(model.sample.diskTotal) < 0.1 ? 15 : 0
        return max(0, 100 - memoryPenalty - diskPenalty - (cpu > 80 ? 20 : cpu > 50 ? 10 : 0))
    }
    private var bootDate: String {
        let formatter = DateFormatter(); formatter.dateFormat = "M月d日"
        return formatter.string(from: Date().addingTimeInterval(-model.sample.uptime))
    }
    private var cpu: some View {
        StatusCard(title: "CPU", icon: "cpu", tint: .mint, badge: model.hardware.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "") {
            metric(model.sample.cpu.map { String(format: "%.0f", $0) } ?? "—", unit: "%")
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(model.sample.coreUsage.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1).fill(LinearGradient(colors: [.mint.opacity(0.9), .mint.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(2, proxy.size.height * value / 100))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 33)
            Spacer(minLength: 0)
            Text("\((model.sample.cpu ?? 0) > 30 ? "繁忙" : "低负载") · \(model.sample.cores) 核 · 平均负载 \(model.hardware.loadAverage.map { String(format: "%.1f", $0) } ?? "—")").statusFootnote()
        }
    }
    private var gpu: some View {
        StatusCard(title: "GPU", icon: "display", tint: .orange, badge: "") {
            metric(model.hardware.gpu.map { String(format: "%.0f", $0) } ?? "—", unit: "%")
            Trend(values: model.gpuHistory, tint: Color(red: 0.84, green: 0.61, blue: 0.39)).frame(height: 33)
            Spacer(minLength: 0)
            Text(model.hardware.gpu == nil ? "系统未提供 GPU 使用率" : "\((model.hardware.gpu ?? 0) > 30 ? "繁忙" : "低负载") · GPU").statusFootnote()
        }
    }
    private var memory: some View {
        StatusCard(title: "内存", icon: "memorychip", tint: .yellow, badge: pressure) {
            metric(model.sample.memoryAvailable ? String(format: "%.0f", memoryPercent) : "—", unit: "%")
            Trend(values: model.memoryHistory, tint: Color(red: 0.85, green: 0.76, blue: 0.48), filled: true).frame(height: 33)
            Spacer(minLength: 0)
            Text("\(model.sample.memoryAvailable ? sizeText(Int64(model.sample.memoryUsed)) : "不可用") · 交换空间 \(model.hardware.swapUsed.map { sizeText(Int64($0)) } ?? "不可用")").statusFootnote()
        }
    }
    private var battery: some View {
        StatusCard(title: "电池", icon: "battery.100percent", tint: .mint, badge: model.hardware.batteryHealth.map { "健康 \($0)%" } ?? "") {
            HStack {
                metric(model.sample.battery.map(String.init) ?? "—", unit: "%")
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 3)
                    Circle().trim(from: 0, to: Double(model.sample.battery ?? 0) / 100).stroke(.mint.opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "laptopcomputer").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                }.frame(width: 32, height: 32).padding(.trailing, 4)
            }
            Text(model.sample.battery == 100 ? "已充满" : model.sample.charging ? "正在充电" : "使用电池").statusFootnote()
            Spacer(minLength: 0)
            Text(model.hardware.batteryCycles.map { "循环 \($0) 次" } ?? "无电池数据").statusFootnote()
        }.help(batteryDetails)
    }
    private var batteryDetails: String {
        "最大容量 \(model.hardware.batteryHealth.map { "\($0)%" } ?? "不可用")\n循环 \(model.hardware.batteryCycles.map(String.init) ?? "不可用") 次\n电池温度 \(model.hardware.batteryTemperature.map { String(format: "%.0f°C", $0) } ?? "不可用")\n电源额定功率 \(model.hardware.adapterWatts.map { "\($0)W" } ?? "不可用")\n电池电压 \(model.hardware.batteryVoltage.map { String(format: "%.2fV", $0) } ?? "不可用")"
    }
    private var disk: some View {
        StatusCard(title: "可用空间", icon: "internaldrive", tint: .blue, badge: model.sample.diskTotal > 0 ? sizeText(model.sample.diskTotal) : "不可用") {
            metric(model.sample.diskTotal > 0 ? String(format: "%.0f", Double(model.sample.diskFree) / 1e9) : "—", unit: "GB")
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.06))
                Capsule().fill(LinearGradient(colors: [.blue.opacity(0.4), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(1, max(0, 1 - Double(model.sample.diskFree) / Double(max(1, model.sample.diskTotal)))))
            }.frame(height: 8).padding(.vertical, 13)
            Spacer(minLength: 0)
            Text(model.sample.diskTotal > 0 ? "已用 \(sizeText(model.sample.diskTotal - model.sample.diskFree)) · \(Int((1 - Double(model.sample.diskFree) / Double(max(1, model.sample.diskTotal))) * 100))%" : "磁盘容量读取失败").statusFootnote()
        }
    }
    private var network: some View {
        StatusCard(title: "网络", icon: "network", tint: .blue, badge: "网络接口") {
            metric(speedNumber(model.sample.download), unit: speedUnit(model.sample.download))
            ZStack {
                Trend(values: model.downHistory, tint: .mint, ceiling: max(1024, (model.downHistory + model.upHistory).max() ?? 1024))
                Trend(values: model.upHistory, tint: .blue, ceiling: max(1024, (model.downHistory + model.upHistory).max() ?? 1024))
            }.frame(height: 33)
            Spacer(minLength: 0)
            HStack {
                Text("上传 \(speedNumber(model.sample.upload)) \(speedUnit(model.sample.upload))").statusFootnote()
                Spacer(minLength: 2)
                Button("开启低延迟") { notice = "当前版本没有网络低延迟控制服务。此按钮不会改变 Wi-Fi 或系统网络设置。" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
        }
    }
    private var fanPercentage: String {
        guard let rpm = model.hardware.fanRPM, let maximum = model.hardware.fanMaximum, maximum > 0 else { return "" }
        return "转速 \(Int(rpm / maximum * 100))%"
    }
    private var fan: some View {
        StatusCard(title: "风扇", icon: "fan", tint: .orange, badge: fanPercentage) {
            metric(model.hardware.fanRPM.map { String(format: "%.0f", $0) } ?? "—", unit: "RPM")
            HStack(spacing: 10) {
                ForEach(["自动", "降温", "强冷"], id: \.self) { mode in
                    Button(mode) { notice = mode == "自动" ? "风扇由 macOS 自动管理。" : "Astra 尚未接入风扇控制服务，未向硬件写入转速。当前仍由 macOS 自动管理。" }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(.white.opacity(mode == "自动" ? 0.10 : 0.04), in: Capsule())
                        .foregroundStyle(.white.opacity(mode == "自动" ? 0.8 : 0.35))
                }
            }.padding(.vertical, 3)
            Spacer(minLength: 0)
            Text(model.hardware.fanRPM == nil ? "由系统自动调节 · 转速不可用" : "由系统自动调节").statusFootnote()
        }
    }
    private var processTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                sortButton(.name, title: "名称 (\(model.processes.count))").frame(maxWidth: .infinity, alignment: .leading)
                sortButton(.memory).frame(width: 100, alignment: .trailing)
                sortButton(.cpu).frame(width: 150, alignment: .trailing)
                sortButton(.energy).frame(width: 100, alignment: .trailing)
                sortButton(.pid).frame(width: 100, alignment: .trailing)
                Button { showSearch.toggle(); searchFocused = showSearch } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).frame(width: 24)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(.horizontal, 20).frame(height: 24)
            if showSearch && inspected == nil { TextField("搜索 App、进程或 PID", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused).padding(.horizontal, 16).padding(.vertical, 6) }
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { group in processRow(group) }
                    if !model.processError.isEmpty { Text(model.processError).font(.system(size: 12)).foregroundStyle(.orange).padding() }
                    if sorted.isEmpty && model.processError.isEmpty { Text(query.isEmpty ? "正在读取进程…" : "没有匹配的进程").foregroundStyle(.secondary).padding(24) }
                }
            }
        }.background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07)))
    }
    private func sortButton(_ column: ProcessSort, title: String? = nil) -> some View {
        Button { if sort == column { ascending.toggle() } else { sort = column; ascending = false } } label: {
            HStack(spacing: 3) { Text(title ?? column.rawValue); if sort == column { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 7)) } }
                .foregroundStyle(sort == column ? .white.opacity(0.85) : .white.opacity(0.45))
        }.buttonStyle(.plain).help(column == .energy ? "系统未提供能耗指数，当前按名称排序" : "按\(column.rawValue)排序")
    }
    private func processRow(_ group: ProcessGroup) -> some View {
        HStack(spacing: 16) {
            Button { searchFocused = false; inspected = group } label: {
                HStack(spacing: 10) {
                    if pinned.contains(group.id) { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                    Image(nsImage: group.application.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!).resizable().frame(width: 16, height: 16)
                    Text(group.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(sizeText(group.residentBytes)).frame(width: 100, alignment: .trailing).foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 18) {
                        GeometryReader { proxy in
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(.white.opacity(0.4)).frame(width: max(1, proxy.size.width * min(1, group.cpu / 100)))
                        }.frame(width: 48, height: 6)
                        Text(String(format: "%.1f", group.cpu)).frame(width: 48, alignment: .trailing)
                    }.frame(width: 150, alignment: .trailing).foregroundStyle(.white.opacity(0.65))
                    Text("—").frame(width: 100, alignment: .trailing).foregroundStyle(.white.opacity(0.4)).help("系统未提供能耗指数")
                    Text(String(group.pid)).frame(width: 100, alignment: .trailing).foregroundStyle(.white.opacity(0.4))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("为什么在运行？")
            Menu { processMenu(group) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
        }.font(.system(size: 12)).monospacedDigit().padding(.horizontal, 20).frame(height: 29)
            .contextMenu { processMenu(group) }
    }
    @ViewBuilder private func processMenu(_ group: ProcessGroup) -> some View {
        Button("为什么在运行？") { inspected = group }
        Button("复制 PID") { copyText(String(group.pid)) }
        Button("复制进程名称") { copyText(group.name) }
        if let app = group.application { Button("在访达中显示") { reveal(app) } }
        Button(pinned.contains(group.id) ? "取消置顶" : "置顶") { if pinned.contains(group.id) { pinned.remove(group.id) } else { pinned.insert(group.id) } }
    }
    private func metric(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.system(size: 28, weight: .semibold)); Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6)) }.monospacedDigit()
    }
    private func speedNumber(_ value: Double?) -> String { guard let value else { return "—" }; return String(format: "%.0f", value >= 1e6 ? value / 1e6 : value / 1e3) }
    private func speedUnit(_ value: Double?) -> String { (value ?? 0) >= 1e6 ? "MB/s" : "KB/s" }
}

struct StatusCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let badge: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(tint.opacity(0.7))
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 4)
                if !badge.isEmpty { Text(badge).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 5).padding(.vertical, 3).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4)) }
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            content
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }
}
struct Trend: View {
    let values: [Double]
    var tint: Color = .mint
    var filled = false
    var ceiling: Double = 100
    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * proxy.size.width, y: (1 - min(1, max(0, value / max(1, ceiling)))) * proxy.size.height)
            }
            if let first = points.first {
                if filled {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: proxy.size.height)); p.addLines(points)
                        p.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height)); p.closeSubpath()
                    }.fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                Path { p in p.addLines(points) }.stroke(tint, lineWidth: 1.3)
            }
        }
    }
}
struct Sparkline: View { let values: [Double]; var body: some View { Trend(values: values) } }
extension Text {
    func statusFootnote() -> some View { font(.system(size: 11)).foregroundStyle(.white.opacity(0.60)).lineLimit(1).minimumScaleFactor(0.8) }
}
func copyText(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }

struct ProcessInspector: View {
    let group: ProcessGroup
    let close: () -> Void
    @State private var details: ProcessDetails?
    @State private var showAll = false
    @State private var terminateRequested = false
    @State private var terminationResult = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if let app = group.application { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 28, height: 28) }
                Text(group.name).font(.system(size: 23, weight: .semibold)); Spacer()
                Button(action: close) { Image(systemName: "xmark").padding(8).background(.white.opacity(0.07), in: Circle()) }.buttonStyle(.plain)
            }
            Divider().opacity(0.3)
            Text("\(group.members.count) 个进程 · CPU \(String(format: "%.1f", group.cpu))% · MEM \(sizeText(group.residentBytes))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("父进程").foregroundStyle(.secondary); Text(String(group.members.first(where: { $0.id == group.pid })?.parent ?? 0)); Image(systemName: "chevron.right"); Text("\(group.name) \(group.pid)") }.font(.system(size: 12))
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow { Text("识别依据").foregroundStyle(.secondary); Text(group.application?.path ?? group.members.first?.executable ?? "不可用").textSelection(.enabled) }
                        GridRow { Text("启动来源").foregroundStyle(.secondary); Text(group.members.first(where: { $0.id == group.pid })?.parent == 1 ? "系统后台服务 launchd" : "父进程启动") }
                        GridRow { Text("线程数").foregroundStyle(.secondary); Text(details?.threads.map(String.init) ?? "不可用") }
                        GridRow { Text("打开文件").foregroundStyle(.secondary); Text(details?.openFiles.map(String.init) ?? "不可用") }
                        GridRow { Text("磁盘 I/O").foregroundStyle(.secondary); Text("\(details?.readBytes.map { sizeText(Int64(clamping: $0)) } ?? "—") R · \(details?.writeBytes.map { sizeText(Int64(clamping: $0)) } ?? "—") W") }
                        GridRow { Text("用户").foregroundStyle(.secondary); Text(group.members.first?.uid == getuid() ? NSUserName() : String(group.members.first?.uid ?? 0)) }
                        GridRow { Text("启动时间").foregroundStyle(.secondary); Text(details?.started.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "不可用") }
                        GridRow { Text("可执行文件").foregroundStyle(.secondary); Text(group.members.first(where: { $0.id == group.pid })?.executable ?? "不可用").lineLimit(2).textSelection(.enabled) }
                        GridRow { Text("内存口径").foregroundStyle(.secondary); Text(group.members.allSatisfy(\.memoryIsFootprint) ? "物理占用合计（含压缩内存）" : "物理占用；受限进程回退为常驻内存") }
                    }.font(.system(size: 12))
                    HStack { Text("进程"); Spacer(); Text("按内存") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
                    ForEach(Array(group.members.prefix(showAll ? group.members.count : 6))) { process in
                        HStack {
                            Text(process.name).lineLimit(1); Spacer()
                            Text(String(process.id)).foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                            Text(String(format: "%.1f%%", process.cpu)).foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                            Text(sizeText(process.residentBytes)).frame(width: 75, alignment: .trailing)
                        }.font(.system(size: 12)).padding(.vertical, 3)
                    }
                    if group.members.count > 6 {
                        Button(showAll ? "收起进程" : "其余 \(group.members.count - 6) 个进程") { showAll.toggle() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }.frame(maxHeight: 490)
            if !terminationResult.isEmpty { Text(terminationResult).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("复制摘要") { copyText("\(group.name) · PID \(group.pid) · CPU \(group.cpu)% · 内存 \(sizeText(group.residentBytes))") }
                if let app = group.application { Button("在访达中显示") { reveal(app) } }
                Button("终止") { terminateRequested = true }.disabled(group.application == nil)
            }.buttonStyle(.bordered).controlSize(.small)
        }.padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.13)))
            .task(id: group.id) { details = await Task.detached { ProcessDetails.read(pid: group.pid) }.value }
            .confirmationDialog("退出 \(group.name)？未保存的工作可能受影响。", isPresented: $terminateRequested, titleVisibility: .visible) {
                Button("请求正常退出", role: .destructive) {
                    guard let url = group.application, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == url && $0.processIdentifier == group.pid }) else { terminationResult = "进程状态已变化，请关闭详情后重新选择。"; return }
                    terminationResult = app.terminate() ? "已发送正常退出请求，请确认应用是否已退出。" : "应用未接受退出请求。"
                }
                Button("取消", role: .cancel) {}
            }
    }
}
