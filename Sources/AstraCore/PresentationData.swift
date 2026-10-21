import Foundation
import Darwin

public enum TreemapLayout {
    public static func rectangles(weights: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: weights.count)
        let items = weights.enumerated().filter { $0.element.isFinite && $0.element > 0 }
            .map { (index: $0.offset, weight: $0.element) }.sorted { $0.weight > $1.weight }
        func partition(_ values: [(index: Int, weight: Double)], _ rect: CGRect) {
            guard !values.isEmpty else { return }
            if values.count == 1 { result[values[0].index] = rect; return }
            let total = values.reduce(0) { $0 + $1.weight }
            var cut = 1; var sum = values[0].weight
            while cut < values.count - 1 && abs(sum + values[cut].weight - total / 2) < abs(sum - total / 2) {
                sum += values[cut].weight; cut += 1
            }
            let ratio = sum / total
            if rect.width >= rect.height {
                let w = rect.width * ratio
                partition(Array(values[..<cut]), CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height))
                partition(Array(values[cut...]), CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
            } else {
                let h = rect.height * ratio
                partition(Array(values[..<cut]), CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h))
                partition(Array(values[cut...]), CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
            }
        }
        guard bounds.width > 0, bounds.height > 0 else { return result }
        partition(items, bounds); return result
    }
}

public struct LiveProcess: Identifiable, Sendable {
    public let id: Int32
    public let parent: Int32
    public let cpu: Double
    public let residentBytes: Int64
    public let uid: UInt32
    public let executable: String
    public var memoryIsFootprint = false
    public var name: String { URL(fileURLWithPath: executable).lastPathComponent }
}
public struct ProcessGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let application: URL?
    public let members: [LiveProcess]
    public var cpu: Double { members.reduce(0) { $0 + $1.cpu } }
    public var residentBytes: Int64 { members.reduce(0) { $0 + $1.residentBytes } }
    public var pid: Int32 {
        if let application {
            let main = application.appendingPathComponent("Contents/MacOS/").path + "/"
            if let process = members.first(where: { $0.executable.hasPrefix(main) }) { return process.id }
        }
        let ids = Set(members.map(\.id))
        return members.first(where: { !ids.contains($0.parent) })?.id ?? members.first?.id ?? 0
    }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || members.contains {
            String($0.id).contains(query) || $0.executable.localizedCaseInsensitiveContains(query)
        }
    }
}
public enum ProcessSampler {
    public static func parse(_ output: String) -> [LiveProcess] {
        output.split(separator: "\n").compactMap { line in
            let pieces = line.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard pieces.count == 6, let pid = Int32(pieces[0]), pid > 0,
                  let parent = Int32(pieces[1]), let cpu = Double(pieces[2]), cpu.isFinite, cpu >= 0,
                  let kb = Int64(pieces[3]), kb >= 0, kb <= Int64.max / 1024, let uid = UInt32(pieces[4]) else { return nil }
            return LiveProcess(id: pid, parent: parent, cpu: cpu, residentBytes: kb * 1024, uid: uid, executable: String(pieces[5]))
        }
    }
    public static func group(_ processes: [LiveProcess]) -> [ProcessGroup] {
        let byPID = Dictionary(processes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func appPath(_ path: String) -> String? {
            guard path.hasPrefix("/"), let range = path.range(of: ".app/") else { return nil }
            return String(path[..<range.lowerBound]) + ".app"
        }
        func owner(_ process: LiveProcess) -> String? {
            if let own = appPath(process.executable) { return own }
            var seen = Set<Int32>(); var parent = process.parent
            while parent > 1, seen.insert(parent).inserted, let item = byPID[parent] {
                if let path = appPath(item.executable) { return path }; parent = item.parent
            }
            return nil
        }
        let grouped = Dictionary(grouping: processes) { owner($0) ?? "pid:\($0.id)" }
        return grouped.map { key, members in
            let url = key.hasPrefix("/") ? URL(fileURLWithPath: key) : nil
            let info = url.flatMap { Bundle(url: $0)?.infoDictionary }
            let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? url?.deletingPathExtension().lastPathComponent ?? members[0].name
            return ProcessGroup(id: key, name: name, application: url, members: members.sorted { $0.residentBytes > $1.residentBytes })
        }
    }
    public static func sample() throws -> [ProcessGroup] {
        let result = try CommandService.run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-ww", "-axo", "pid=,ppid=,%cpu=,rss=,uid=,comm="], timeout: 8, environmentOverrides: ["LC_ALL": "en_US.UTF-8"])
        guard result.exitCode == 0 else { throw NSError(domain: "Astra.ProcessSampler", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: "无法读取进程列表"]) }
        let enriched = parse(result.output).map { process in
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(process.id, &path, UInt32(path.count))
            let executable = length > 0 ? String(cString: path) : process.executable
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(process.id, RUSAGE_INFO_V2, $0) }
            }
            let footprint = status == 0 && usage.ri_phys_footprint <= UInt64(Int64.max)
            return LiveProcess(id: process.id, parent: process.parent, cpu: process.cpu,
                               residentBytes: footprint ? Int64(usage.ri_phys_footprint) : process.residentBytes,
                               uid: process.uid, executable: executable, memoryIsFootprint: footprint)
        }
        return group(enriched)
    }
}

public struct ProcessDetails: Sendable {
    public var threads: Int?
    public var openFiles: Int?
    public var started: Date?
    public var readBytes: UInt64?
    public var writeBytes: UInt64?
    public static func read(pid: Int32) -> ProcessDetails {
        var result = ProcessDetails()
        var task = proc_taskinfo()
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size { result.threads = Int(task.pti_threadnum) }
        var bsd = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size { result.started = Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec)) }
        let descriptorBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        if descriptorBytes > 0 {
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(descriptorBytes) / MemoryLayout<proc_fdinfo>.stride)
            let actualBytes = descriptors.withUnsafeMutableBytes { buffer in
                proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
            }
            if actualBytes > 0 { result.openFiles = Int(actualBytes) / MemoryLayout<proc_fdinfo>.stride }
        }
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) { p in p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) } }
        if status == 0 { result.readBytes = usage.ri_diskio_bytesread; result.writeBytes = usage.ri_diskio_byteswritten }
        return result
    }
}
