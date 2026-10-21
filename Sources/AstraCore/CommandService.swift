import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String
}
public enum CommandService {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 60, environmentOverrides: [String: String] = [:]) throws -> CommandResult {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("astra-output-\(UUID()).log")
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["NONINTERACTIVE"] = "1"
        environment.merge(environmentOverrides) { _, new in new }
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let stopDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw AstraError.message("操作超时，主进程已终止；若外部工具启动了其他进程，请检查其状态。")
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: temporary)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 2_000_000) ?? Data()
        return CommandResult(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
    public static var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

public struct BrewUpdate: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let installed: String
    public let latest: String
}
public enum UpdateService {
    public static func check() throws -> [BrewUpdate] {
        guard let brew = CommandService.brew else { throw AstraError.message("未安装 Homebrew。其他应用请使用应用内的检查更新入口。") }
        let result = try CommandService.run(executable: brew, arguments: ["outdated", "--cask", "--json=v2"], timeout: 90)
        guard result.exitCode == 0 else { throw AstraError.message("Homebrew 查询失败：\(result.output.prefix(600))") }
        guard let data = result.output.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { throw AstraError.message("未能解析 Homebrew 更新结果。") }
        return casks.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let installed = (item["installed_versions"] as? [String])?.joined(separator: ", ") ?? "未知"
            return BrewUpdate(name: name, installed: installed, latest: item["current_version"] as? String ?? "未知")
        }
    }
}
