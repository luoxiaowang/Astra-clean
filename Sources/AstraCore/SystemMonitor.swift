import Foundation
import Darwin
import IOKit.ps

public struct SystemSnapshot: Sendable {
    public var coreUsage: [Double] = []
    public var cpu: Double?
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    public var diskTotal: Int64 = 0
    public var diskFree: Int64 = 0
    public var download: Double?
    public var upload: Double?
    public var battery: Int?
    public var charging = false
    public var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    public var cpuName = "Mac"
    public var cores = ProcessInfo.processInfo.activeProcessorCount
    public var memoryAvailable = false
    public init() {}
}

public final class SystemMonitor {
    private var previousCoreTicks: [[UInt64]] = []
    private var previousCPU: [UInt64]?
    private var previousNetwork: (UInt64, UInt64, TimeInterval)?
    public init() {}
    public static func cpuUsage(previous: [UInt64]?, current: [UInt64]) -> Double? {
        guard let previous, previous.count == 4, current.count == 4 else { return nil }
        let differences = zip(current, previous).map { $0 >= $1 ? $0 - $1 : 0 }
        let total = differences.reduce(0, +)
        guard total > 0 else { return nil }
        return min(100, max(0, Double(total - differences[2]) / Double(total) * 100))
    }
    public func sample() -> SystemSnapshot {
        var result = SystemSnapshot()
        var boot = timeval(); var bootSize = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boot, &bootSize, nil, 0) == 0 {
            result.uptime = max(0, Date().timeIntervalSince1970 - Double(boot.tv_sec))
        }
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if cpuStatus == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3].map(UInt64.init)
            result.cpu = Self.cpuUsage(previous: previousCPU, current: ticks); previousCPU = ticks
        }
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        if host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &processorInfoCount) == KERN_SUCCESS, let info = processorInfo {
            var current: [[UInt64]] = []
            for index in 0..<Int(processorCount) {
                let base = index * Int(CPU_STATE_MAX)
                let ticks = (0..<4).map { UInt64(UInt32(bitPattern: info[base + $0])) }
                current.append(ticks)
                if index < previousCoreTicks.count, let usage = Self.cpuUsage(previous: previousCoreTicks[index], current: ticks) { result.coreUsage.append(usage) }
            }
            previousCoreTicks = current
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(host, HOST_VM_INFO64, $0, &vmCount) }
        }
        var pageSize: vm_size_t = 0; host_page_size(host, &pageSize)
        if vmStatus == KERN_SUCCESS {
            result.memoryUsed = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(pageSize)
            result.memoryAvailable = true
        }
        if let space = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            result.diskTotal = (space[.systemSize] as? NSNumber)?.int64Value ?? 0
            result.diskFree = (space[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
        var size = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 { result.cpuName = String(cString: buffer) }
        }
        if let traffic = networkCounters() {
            let now = ProcessInfo.processInfo.systemUptime
            if let old = previousNetwork, now > old.2, traffic.0 >= old.0, traffic.1 >= old.1 {
                result.download = Double(traffic.0 - old.0) / (now - old.2)
                result.upload = Double(traffic.1 - old.1) / (now - old.2)
            }
            previousNetwork = (traffic.0, traffic.1, now)
        }
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let details = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      let current = details[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                result.battery = current * 100 / maximum
                result.charging = details[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }
        return result
    }
    private func networkCounters() -> (UInt64, UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var incoming: UInt64 = 0; var outgoing: UInt64 = 0; var pointer = list
        while let item = pointer {
            defer { pointer = item.pointee.ifa_next }
            guard item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = item.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            incoming += UInt64(data.pointee.ifi_ibytes); outgoing += UInt64(data.pointee.ifi_obytes)
        }
        return (incoming, outgoing)
    }
}
