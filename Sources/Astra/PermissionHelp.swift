import SwiftUI

struct PermissionHelp: View {
    var retry: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var openFailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("允许 Astra 读取受限目录").font(.system(size: 22, weight: .semibold))
            Text("macOS 阻止了部分文件读取。可在「系统设置 → 隐私与安全性」中检查 Astra 的「文件与文件夹」权限；受保护的应用数据可能需要「完全磁盘访问权限」。")
            Text("完全磁盘访问权限会允许 Astra 读取更广泛的受保护文件。是否开启由你决定，应用不能自动授予。普通文件权限、文件变化或扫描上限问题不一定能通过此授权解决。")
                .foregroundStyle(.secondary)
            Text("1. 打开系统设置中的权限页面。\n2. 找到 Astra 并开启；未列出时，点「+」添加下方应用。\n3. 按系统提示退出并重新打开 Astra，再扫描。")
                .lineSpacing(5)
            Text(Bundle.main.bundleURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("在访达中显示 Astra") { reveal(Bundle.main.bundleURL) }
                Button("文件与文件夹") { open("Privacy_FilesAndFolders") }
                Button("完全磁盘访问权限") { open("Privacy_AllFiles") }
            }
            if openFailed { Text("未能打开设置。请从苹果菜单进入「系统设置 → 隐私与安全性」。").foregroundStyle(.orange) }
            HStack {
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if let retry { Button("重新扫描") { dismiss(); retry() }.buttonStyle(.borderedProminent) }
            }
        }.font(.system(size: 13)).padding(28).frame(width: 550).preferredColorScheme(.dark)
    }
    private func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) else { return }
        openFailed = !NSWorkspace.shared.open(url)
    }
}
