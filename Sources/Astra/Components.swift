import SwiftUI
import AstraCore

enum Palette {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.083)
    static let sidebar = Color(red: 0.075, green: 0.087, blue: 0.105)
    static let raised = Color(red: 0.11, green: 0.13, blue: 0.15)
    static let accent = Color(red: 0.65, green: 0.88, blue: 0.72)
    static let text = Color(red: 0.91, green: 0.94, blue: 0.94)
    static let muted = Color(red: 0.52, green: 0.59, blue: 0.63)
    static let border = Color.white.opacity(0.07)
}
func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(3).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 29, weight: .semibold)).foregroundStyle(Palette.text)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { Text(title); Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 20).padding(.vertical, 12)
                .foregroundStyle(Palette.background)
                .background(disabled ? Palette.muted : Palette.accent, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(disabled)
    }
}
struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.border, lineWidth: 1))
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
            Text(detail).font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 35)
    }
}
struct OrbitGraphic: View {
    var body: some View {
        ZStack {
            Circle().fill(Palette.accent.opacity(0.035)).frame(width: 170, height: 170)
            Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 1).frame(width: 170, height: 170)
            Circle().stroke(Palette.accent.opacity(0.16), lineWidth: 1).frame(width: 126, height: 126)
            Circle().stroke(Palette.accent.opacity(0.2), lineWidth: 1).frame(width: 84, height: 84)
            Image(systemName: "sparkle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Palette.accent)
            Circle().fill(Palette.accent).frame(width: 9, height: 9).offset(x: 65, y: -55)
            Circle().fill(Palette.accent.opacity(0.4)).frame(width: 5, height: 5).offset(x: -54, y: 31)
        }.frame(width: 190, height: 190).accessibilityHidden(true)
    }
}
struct InlineNotice: View {
    let text: String
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning ? "exclamationmark.circle" : "info.circle")
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).foregroundStyle(warning ? Color.orange.opacity(0.9) : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RemovalReview: View {
    @ObservedObject var model: FilesModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认移入废纸篓").font(.system(size: 23, weight: .semibold))
            Text("\(model.selectedEntries.count) 项 · \(sizeText(model.selectedBytes))").foregroundStyle(Palette.accent)
            Text("请检查下面的完整路径。移除前会重新校验文件；发生变化或无法读取的项目会跳过。应用支持数据可能包含设置，请确认已经备份。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.selectedEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(entry.name).fontWeight(.medium); Spacer(); Text(sizeText(entry.bytes)).foregroundStyle(Palette.accent) }
                            Text(entry.url.path).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        }.padding(12).background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(maxHeight: 260)
            HStack {
                Text("可在访达的废纸篓中恢复").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                PrimaryButton(title: "移入废纸篓", symbol: "trash", disabled: model.selectedEntries.isEmpty) {
                    dismiss(); model.removeSelected()
                }
            }
        }.padding(28).frame(width: 560).background(Palette.background).preferredColorScheme(.dark)
    }
}
