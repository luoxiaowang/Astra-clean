import Foundation

public struct MaintenanceTask: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let group: String
}
public enum MaintenanceStatus: String, Sendable {
    case maintained = "已维护", healthy = "正常", attention = "需关注", unavailable = "未完成"
}
public struct MaintenanceResult: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let status: MaintenanceStatus
    public let detail: String
    public var succeeded: Bool { status == .maintained || status == .healthy }
}
public enum MaintenanceService {
    public static let tasks: [MaintenanceTask] = [
        .init(id: "previews", title: "重建快速预览缓存", group: "启动加速"),
        .init(id: "plugins", title: "重新加载快速预览插件", group: "启动加速"),
        .init(id: "userAgents", title: "检查用户后台服务配置", group: "系统维护"),
        .init(id: "systemAgents", title: "检查系统后台服务配置", group: "系统维护"),
        .init(id: "daemons", title: "检查后台守护服务配置", group: "系统维护"),
        .init(id: "targets", title: "检查失效后台服务路径", group: "系统维护"),
        .init(id: "savedState", title: "检查 30 天前的窗口状态", group: "系统维护"),
        .init(id: "disk", title: "检查磁盘可用空间", group: "系统状态"),
        .init(id: "memory", title: "检查内存压力", group: "系统状态"),
        .init(id: "battery", title: "检查电池健康", group: "系统状态"),
        .init(id: "spotlight", title: "检查 Spotlight 索引状态", group: "网络与搜索"),
        .init(id: "dns", title: "检查 DNS 配置", group: "网络与搜索"),
        .init(id: "images", title: "检查已挂载磁盘镜像", group: "系统维护")
    ]
    public static func inspectPlists(at root: URL, title: String) -> MaintenanceResult {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]).filter { $0.pathExtension == "plist" }
            var invalid = 0; var unreadable = 0
            for file in files.prefix(2000) {
                do {
                    let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
                    if values.isSymbolicLink == true { unreadable += 1; continue }
                    let data = try Data(contentsOf: file, options: .mappedIfSafe)
                    if let value = try? PropertyListSerialization.propertyList(from: data, format: nil), let dictionary = value as? [String: Any], dictionary["Label"] is String { } else { invalid += 1 }
                } catch { unreadable += 1 }
            }
            return .init(title: title, status: invalid > 0 ? .attention : unreadable > 0 || files.count > 2000 ? .unavailable : .healthy,
                         detail: "检查 \(min(files.count, 2000)) 项 · 损坏 \(invalid) 项 · 未读取 \(unreadable + max(0, files.count - 2000)) 项；未修改配置。")
        } catch {
            return .init(title: title, status: .unavailable, detail: error.localizedDescription)
        }
    }
    public static func execute(_ task: MaintenanceTask) -> MaintenanceResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func result(_ status: MaintenanceStatus, _ detail: String) -> MaintenanceResult { .init(title: task.title, status: status, detail: detail) }
        do {
            switch task.id {
            case "previews", "plugins":
                let response = try CommandService.run(executable: URL(fileURLWithPath: "/usr/bin/qlmanage"), arguments: task.id == "previews" ? ["-r", "cache"] : ["-r"], timeout: 30)
                return result(response.exitCode == 0 ? .maintained : .unavailable, response.exitCode == 0 ? "系统已完成此项维护。" : "退出码 \(response.exitCode)：\(response.output.prefix(500))")
            case "userAgents": return inspectPlists(at: home.appendingPathComponent("Library/LaunchAgents"), title: task.title)
            case "systemAgents": return inspectPlists(at: URL(fileURLWithPath: "/Library/LaunchAgents"), title: task.title)
            case "daemons": return inspectPlists(at: URL(fileURLWithPath: "/Library/LaunchDaemons"), title: task.title)
            case "targets":
                let items = Catalog.startupItems(); let missing = items.filter { !$0.targetExists }
                return result(items.isEmpty ? .unavailable : missing.isEmpty ? .healthy : .attention,
                              "读取 \(items.count) 项 · \(missing.count) 项目标路径不可见；可能涉及权限或外置磁盘，未自动删除。")
            case "savedState":
                let root = home.appendingPathComponent("Library/Saved Application State")
                let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
                var old = 0; var unknown = 0
                for url in urls {
                    if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                        if date < Date().addingTimeInterval(-30 * 86400) { old += 1 }
                    } else { unknown += 1 }
                }
                return result(unknown > 0 ? .unavailable : old > 0 ? .attention : .healthy, "\(old) 项超过 30 天 · \(unknown) 项不可读取；保留窗口恢复数据。")
            case "disk":
                let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
                guard let free = values.volumeAvailableCapacity, let total = values.volumeTotalCapacity, total > 0 else { return result(.unavailable, "无法读取磁盘容量。") }
                let ratio = Double(free) / Double(total)
                return result(ratio < 0.1 ? .attention : .healthy, String(format: "可用空间 %.1f GB · %.0f%%", Double(free) / 1e9, ratio * 100))
            case "memory":
                guard let pressure = HardwareSnapshot.read().memoryPressure else { return result(.unavailable, "无法读取内存压力。") }
                return result(pressure >= 2 ? .attention : .healthy, pressure >= 2 ? "内存压力偏高；未强制清空内存或关闭应用。" : "内存压力正常。")
            case "battery":
                let response = try CommandService.run(executable: URL(fileURLWithPath: "/usr/sbin/system_profiler"), arguments: ["SPPowerDataType", "-json"], timeout: 15)
                guard response.exitCode == 0, let data = response.output.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["SPPowerDataType"] as? [[String: Any]], let battery = rows.first?["sppower_battery_health_info"] as? [String: Any], let condition = battery["sppower_battery_health"] as? String else { return result(.unavailable, "此设备未提供电池健康状态。") }
                return result(["normal", "good"].contains(condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ? .healthy : .attention, "系统电池状态：\(condition)")
            case "spotlight":
                let response = try CommandService.run(executable: URL(fileURLWithPath: "/usr/bin/mdutil"), arguments: ["-s", "/"], timeout: 10)
                return result(response.exitCode != 0 ? .unavailable : response.output.contains("enabled") ? .healthy : .attention, response.output.trimmingCharacters(in: .whitespacesAndNewlines))
            case "dns":
                let response = try CommandService.run(executable: URL(fileURLWithPath: "/usr/sbin/scutil"), arguments: ["--dns"], timeout: 10)
                let count = response.output.components(separatedBy: "\n").filter { $0.contains("nameserver[") }.count
                return result(response.exitCode != 0 ? .unavailable : count > 0 ? .healthy : .attention, "系统配置了 \(count) 个 DNS 服务器条目；未修改网络设置。")
            case "images":
                let response = try CommandService.run(executable: URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["info", "-plist"], timeout: 15)
                guard response.exitCode == 0, let data = response.output.data(using: .utf8), let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let images = info["images"] as? [Any] else { return result(.unavailable, "无法读取磁盘镜像列表。") }
                return result(images.isEmpty ? .healthy : .attention, "\(images.count) 个已挂载镜像；无法判定是否闲置，未自动弹出。")
            default: return result(.unavailable, "未知任务，未执行。")
            }
        } catch { return result(.unavailable, error.localizedDescription) }
    }
}
