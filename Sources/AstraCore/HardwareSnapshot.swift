import Foundation
import IOKit
import Darwin

public struct HardwareSnapshot: Sendable {
    public var fanRPM: Double?
    public var fanMaximum: Double?
    public var cpuTemperature: Double?
    public var gpu: Double?
    public var batteryHealth: Int?
    public var batteryCycles: Int?
    public var batteryTemperature: Double?
    public var batteryVoltage: Double?
    public var batteryCurrent: Double?
    public var adapterWatts: Int?
    public var swapUsed: UInt64?
    public var memoryPressure: Int?
    public var loadAverage: Double?
    public init() {}
    public static func read() -> HardwareSnapshot {
        var value = HardwareSnapshot()
        let smc = SMCReader()
        value.fanRPM = smc.read("F0Ac").flatMap { $0 >= 0 && $0 < 20000 ? $0 : nil }
        value.fanMaximum = smc.read("F0Mx")
        let temperatures = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "TC0P"].compactMap { smc.read($0) }.filter { $0 > 0 && $0 < 150 }
        value.cpuTemperature = temperatures.max()
        func properties(_ name: String) -> [String: Any] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            guard service != 0 else { return [:] }; defer { IOObjectRelease(service) }
            var result: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &result, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
            return result?.takeRetainedValue() as? [String: Any] ?? [:]
        }
        let battery = properties("AppleSmartBattery")
        if let nominal = battery["NominalChargeCapacity"] as? Double, let design = battery["DesignCapacity"] as? Double, design > 0 {
            value.batteryHealth = min(100, Int((nominal / design * 100).rounded()))
        }
        value.batteryCycles = battery["CycleCount"] as? Int
        value.batteryTemperature = (battery["Temperature"] as? Double).map { $0 / 100 }
        value.batteryVoltage = (battery["Voltage"] as? Double).map { $0 / 1000 }
        value.batteryCurrent = (battery["Amperage"] as? NSNumber).map { Double($0.int64Value) / 1000 }
        value.adapterWatts = (battery["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
        let gpu = properties("AGXAccelerator")
        if let stats = gpu["PerformanceStatistics"] as? [String: Any] {
            value.gpu = (stats["Device Utilization %"] as? Double).map { min(100, max(0, $0)) }
        }
        var swap = xsw_usage(); var count = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &count, nil, 0) == 0 { value.swapUsed = swap.xsu_used }
        var pressure: Int32 = 0; count = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &count, nil, 0) == 0 { value.memoryPressure = Int(pressure) }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) > 0 { value.loadAverage = load[0] }
        return value
    }
}
