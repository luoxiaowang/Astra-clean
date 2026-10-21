import SwiftUI
import AstraCore

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published var detailActive = false
    @Published var running = false
    @Published var finished = false
    @Published var active = ""
    @Published var results: [MaintenanceResult] = []
    func run() {
        guard !running else { return }
        running = true; finished = false; results = []
        Task {
            for task in MaintenanceService.tasks {
                active = task.title
                let result = await Task.detached(priority: .utility) { MaintenanceService.execute(task) }.value
                results.append(result)
            }
            active = ""; running = false; finished = true
        }
    }
}
struct MaintenanceView: View {
    @ObservedObject var model: MaintenanceModel
    var body: some View {
        Group {
          if model.detailActive { details } else { hero }
        }.background { Button("关闭结果") { model.detailActive = false }.keyboardShortcut(.cancelAction).hidden() }
    }
    private var hero: some View {
        PlanetHero(planet: .mercury) {
            VStack(spacing: 22) {
                if model.running {
                    Text("正在执行系统维护").font(.system(size: 24, weight: .semibold))
                    Text("\(model.active) · \(model.results.count + 1) / \(MaintenanceService.tasks.count)").foregroundStyle(.secondary).font(.system(size: 12))
                    taskList
                    ProgressView(value: Double(model.results.count), total: Double(MaintenanceService.tasks.count)).frame(width: 236)
                } else if model.finished {
                    Text("检查与维护完成").font(.system(size: 24, weight: .semibold))
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("查看结果") { model.detailActive = true }.buttonStyle(HeroButtonStyle())
                    Button("重新优化") { model.run() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("傍日疾如电，从容一拂间").font(.custom("Songti SC", size: 18)).foregroundStyle(.white.opacity(0.75))
                    Button("优化 Mac") { model.run() }.buttonStyle(HeroButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
    }
    private var summary: String {
        "已维护 \(model.results.filter { $0.status == .maintained }.count) 项 · 已检查 \(model.results.filter { $0.status != .maintained }.count) 项 · \(model.results.filter { !$0.succeeded }.count) 项需查看"
    }
    private var taskList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(MaintenanceService.tasks) { task in
                        let result = model.results.first { $0.title == task.title }
                        HStack(spacing: 10) {
                            Image(systemName: result == nil ? (model.active == task.title ? "circle.fill" : "circle") : result!.succeeded ? "checkmark" : "exclamationmark.circle")
                            Text(task.title)
                            Spacer()
                            Text(result?.status.rawValue ?? (model.active == task.title ? "进行中" : "等待"))
                        }.font(.system(size: 11)).foregroundStyle(model.active == task.title ? .white : .white.opacity(0.5)).id(task.id)
                    }
                }.padding(14)
            }.frame(width: 420, height: 114).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: model.active) { _, value in
                    if let task = MaintenanceService.tasks.first(where: { $0.title == value }) { withAnimation { proxy.scrollTo(task.id, anchor: .center) } }
                }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("优化详情").font(.system(size: 24, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.detailActive = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)) }.buttonStyle(.plain).help("关闭")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("维护与检查").fontWeight(.semibold); Spacer(); Text(String(model.results.count)) }.foregroundStyle(.secondary)
                    Divider().opacity(0.4)
                    ForEach(model.results) { item in
                        HStack(alignment: .top) {
                            Image(systemName: item.succeeded ? "checkmark" : "exclamationmark.circle")
                            Text(item.title)
                            Spacer()
                            Text("\(item.status.rawValue) · \(item.detail)").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }.font(.system(size: 14))
            }
        }.padding(24).padding(.top, 12)
    }
}
