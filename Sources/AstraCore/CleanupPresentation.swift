import Foundation

public enum CleanupPresentation {
    public static let order = ["App 缓存与日志", "通讯工具", "开发工具", "AI 工具", "设计缓存", "系统数据", "下载的安装包"]
    public static func category(for name: String, original: String) -> String {
        if original == "下载的安装包" { return original }
        let key = name.lowercased()
        // 通用应用缓存按路径来源归类，避免把更新器/日志按应用名称误分到专用工具。
        if original == "应用日志" { return "App 缓存与日志" }
        if original == "应用缓存" {
            if key == "homebrew" { return "开发工具" }
            if ["com.openai.codex", "codex", "com.openai.chat"].contains(key) { return "AI 工具" }
            if ["figma", "adobe", "sketch", "canva", "affinity"].contains(where: key.contains) { return "设计缓存" }
            return "App 缓存与日志"
        }
        if ["anthropic", "claude", "openai", "codex", "cursor", "230313mzl4w4u92", "opencode"].contains(where: key.contains) { return "AI 工具" }
        if ["wechat", "xinwechat", "tencent.qq", "lark", "feishu", "huhu", "slack", "dingtalk", "telegram"].contains(where: key.contains) { return "通讯工具" }
        if ["xcode", "swiftpm", "org.swift", "node-gyp", "typescript", "playwright", "pip", "homebrew", "yarn", "npm", "gradle", "jetbrains", "vscode", "visualstudio"].contains(where: key.contains) { return "开发工具" }
        if ["figma", "adobe", "sketch", "canva", "affinity"].contains(where: key.contains) { return "设计缓存" }
        if ["com.apple.", "diagnosticreports", "crashreporter"].contains(where: key.hasPrefix) { return "系统数据" }
        return "App 缓存与日志"
    }
    public static func description(_ group: String) -> String {
        switch group {
        case "App 缓存与日志": return "应用与浏览器的缓存、日志，按需选择清理"
        case "通讯工具": return "通讯应用缓存，清理后部分内容需要重新下载"
        case "开发工具": return "开发工具缓存，清理后首次构建或下载可能较慢"
        case "AI 工具": return "AI 应用缓存与日志，保留对话、项目和本地模型"
        case "设计缓存": return "设计工具缓存，不扫描作品目录"
        case "系统数据": return "用户目录中的系统组件缓存与诊断日志"
        case "下载的安装包": return "下载目录中的磁盘镜像与安装包"
        default: return "查看路径后按需选择"
        }
    }
    public static func isRunning(owner: String?, runningIDs: Set<String>) -> Bool {
        guard let owner else { return false }
        let key = owner.lowercased()
        return runningIDs.contains { key == $0.lowercased() || key.hasPrefix($0.lowercased() + ".") }
    }
}
