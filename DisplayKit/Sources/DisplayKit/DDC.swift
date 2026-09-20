import CIOAVService
import Foundation

/// MCCS VCP feature codes we care about.
public enum VCPCode: UInt8, Sendable {
    case brightness = 0x10
    case volume = 0x62
    case mute = 0x8D
}

public struct VCPValue: Equatable, Sendable {
    public let current: UInt16
    public let max: UInt16
}

/// DDC/CI over the Apple Silicon IOAVService I2C channel.
///
/// Not thread-safe: all calls for a given display must come from one serial queue,
/// since a monitor's DDC controller can only handle one transaction at a time.
public final class DDCChannel {
    private let service: IOAVService

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    // Monitors need breathing room between I2C transactions or they drop them.
    private static let writeSettleTime: useconds_t = 10_000
    private static let readSettleTime: useconds_t = 40_000
    private static let retryDelay: useconds_t = 20_000

    init(service: IOAVService) {
        self.service = service
    }

    public func read(_ code: VCPCode, attempts: Int = 4) -> VCPValue? {
        for attempt in 0..<attempts {
            if attempt > 0 { usleep(Self.retryDelay) }
            guard send([0x01, code.rawValue]) else { continue }
            usleep(Self.readSettleTime)

            var reply = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(service, Self.chipAddress, Self.dataAddress, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
            // [src, len, 0x02 (VCP reply), result, code, type, maxH, maxL, curH, curL, checksum]
            let checksum = reply.dropLast().reduce(UInt8(0x50), ^)
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == code.rawValue, checksum == reply[10] else { continue }
            return VCPValue(
                current: UInt16(reply[8]) << 8 | UInt16(reply[9]),
                max: UInt16(reply[6]) << 8 | UInt16(reply[7])
            )
        }
        return nil
    }

    @discardableResult
    public func write(_ code: VCPCode, value: UInt16, attempts: Int = 3) -> Bool {
        for attempt in 0..<attempts {
            if attempt > 0 { usleep(Self.retryDelay) }
            if send([0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]) {
                usleep(Self.writeSettleTime)
                return true
            }
        }
        return false
    }

    private func send(_ payload: [UInt8]) -> Bool {
        var packet: [UInt8] = [0x80 | UInt8(payload.count)] + payload
        packet.append(packet.reduce(UInt8(0x6E ^ 0x51), ^))
        // Many monitor controllers (LG included) drop a lone command, so send it twice.
        var success = false
        for _ in 0..<2 {
            usleep(Self.writeSettleTime)
            success = IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, &packet, UInt32(packet.count)) == KERN_SUCCESS
        }
        return success
    }
}
