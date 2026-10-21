import Foundation
import IOKit

/// 只读 AppleSMC 客户端。不包含写键、改变风扇模式或提权代码。
/// 协议参考 https://github.com/exelban/stats/blob/master/SMC/smc.swift
public final class SMCReader {
    private var connection: io_connect_t = 0
    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }; defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    public func read(_ key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var info = [UInt32](repeating: 0, count: 20); info[0] = code
        info.withUnsafeMutableBytes { $0[42] = 9 }
        guard let metadata = call(info), metadata[7] > 0, metadata[7] <= 32 else { return nil }
        var query = [UInt32](repeating: 0, count: 20); query[0] = code; query[7] = metadata[7]
        query.withUnsafeMutableBytes { $0[42] = 5 }
        guard let response = call(query) else { return nil }
        let bytes = response.withUnsafeBytes { Array($0[48..<80]) }
        return Self.decode(type: metadata[8], bytes: bytes)
    }
    private func call(_ input: [UInt32]) -> [UInt32]? {
        var output = [UInt32](repeating: 0, count: 20); var size = 80
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, source.count, target.baseAddress, &size)
            }
        }
        guard status == KERN_SUCCESS, size == 80, output.withUnsafeBytes({ $0[40] }) == 0 else { return nil }
        return output
    }
    public static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let result: Double
        switch type {
        case 0x666c7420: // flt , native IEEE754
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            result = Double(Float(bitPattern: bits))
        case 0x66706532: result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case 0x73703738: result = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case 0x75693820: result = Double(bytes[0])
        case 0x75693136: result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default: return nil
        }
        return result.isFinite ? result : nil
    }
}
