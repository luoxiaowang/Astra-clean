import SwiftUI
import AppKit

@main
struct AstraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        if CommandLine.arguments.contains("--check-resources") {
            let valid = [Planet.earth, .moon, .mercury, .jupiter, .sun].allSatisfy { planet in
                guard let url = AstraResources.bundle?.url(forResource: planet.rawValue, withExtension: planet == .mercury ? "png" : "jpg") else { return false }
                return NSImage(contentsOf: url) != nil
            }
            print(valid ? "五个行星纹理读取成功" : "资源缺失")
            print(AstraResources.bundle?.bundlePath ?? "无资源包")
            exit(valid ? 0 : 1)
        }
    }
    var body: some Scene {
        WindowGroup("Astra") {
            ContentView().preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 768)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Astra") { NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "Astra", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "本地运行 · 独立实现")]) }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window.title == "Astra" {
                window.titlebarAppearsTransparent = true
                window.setContentSize(NSSize(width: 1200, height: 768))
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Section: String, CaseIterable, Identifiable {
    case clean = "清理", software = "软件", optimize = "优化", analyze = "分析", status = "状态"
    var id: Self { self }
    var symbol: String {
        switch self { case .clean: "sparkles"; case .software: "square.stack.3d.up"; case .optimize: "slider.horizontal.3"; case .analyze: "chart.pie"; case .status: "waveform.path.ecg" }
    }
    var subtitle: String {
        switch self { case .clean: "找回空间"; case .software: "管理应用"; case .optimize: "日常维护"; case .analyze: "看清占用"; case .status: "了解你的 Mac" }
    }
}

struct ContentView: View {
    @StateObject private var maintenance = MaintenanceModel()
    @State private var section: Section = .clean
    @StateObject private var clean = FilesModel()
    @StateObject private var analysis = FilesModel()
    @StateObject private var software = SoftwareModel()
    private var theme: Color {
        switch section {
        case .clean: Color(red: 0.14, green: 0.19, blue: 0.30)
        case .software: Color(red: 0.25, green: 0.12, blue: 0.12)
        case .optimize: Color(red: 0.23, green: 0.22, blue: 0.19)
        case .analyze: Color(red: 0.31, green: 0.16, blue: 0.07)
        case .status: Color(red: 0.30, green: 0.23, blue: 0.08)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if !(section == .clean && clean.detailActive) && !(section == .optimize && maintenance.detailActive) {
                ZStack {
                    HStack(spacing: 0) {
                        Menu {
                            Text("Astra · 本地运行")
                            Button("关于 Astra") { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
                        } label: {
                            Image(systemName: "sparkle").font(.system(size: 20)).frame(width: 34, height: 34)
                                .foregroundStyle(.black).background(.white, in: Circle())
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 44)
                        ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, item in
                            Button { withAnimation(.easeInOut(duration: 0.18)) { section = item } } label: {
                                Text(item.rawValue).font(.system(size: 14, weight: .semibold))
                                    .frame(width: 70, height: 36)
                                    .foregroundStyle(section == item ? .black : .white.opacity(0.60))
                                    .background(section == item ? Color.white : Color.clear, in: Capsule())
                            }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                                .accessibilityIdentifier("nav.\(item.id)")
                                .accessibilityAddTraits(section == item ? .isSelected : [])
                        }
                    }.padding(4).background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.08)))
                }.frame(height: 60)
            }
            Group {
                switch section {
                case .clean: CleanExperience(model: clean)
                case .software: SoftwareView(model: software)
                case .optimize: MaintenanceView(model: maintenance)
                case .analyze: AnalysisExperience(model: analysis)
                case .status: StatusView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LinearGradient(colors: [theme, theme.opacity(0.60), section == .clean ? Color(red: 0.12, green: 0.14, blue: 0.21) : Color(red: 0.15, green: 0.14, blue: 0.13)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .tint(Palette.accent)
    }
}
