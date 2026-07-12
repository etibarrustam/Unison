import Foundation

// Pure DDC/CI byte framing. No hardware access. See DDC/CI standard.
enum DDCMessage {
    private static let displayAddr: UInt8 = 0x6E  // I2C write address
    private static let sourceAddr: UInt8 = 0x51    // host source address

    static func setVCP(_ code: UInt8, _ value: UInt16) -> [UInt8] {
        let high = UInt8(value >> 8)
        let low = UInt8(value & 0xFF)
        let length: UInt8 = 0x84            // 0x80 | 4 data bytes
        let opcode: UInt8 = 0x03            // Set VCP Feature
        var bytes: [UInt8] = [length, opcode, code, high, low]
        bytes.append(checksum(bytes))
        return bytes
    }

    static func getVCP(_ code: UInt8) -> [UInt8] {
        let length: UInt8 = 0x82            // 0x80 | 2 data bytes
        let opcode: UInt8 = 0x01            // Get VCP Feature
        var bytes: [UInt8] = [length, opcode, code]
        bytes.append(checksum(bytes))
        return bytes
    }

    // Reply layout: [addr, len, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, cksum]
    static func parseGetReply(_ code: UInt8, _ bytes: [UInt8]) -> (current: UInt16, max: UInt16)? {
        guard bytes.count >= 10 else { return nil }
        guard bytes[2] == 0x02, bytes[3] == 0x00, bytes[4] == code else { return nil }
        let max = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard max > 0 else { return nil }
        return (current, max)
    }

    private static func checksum(_ payload: [UInt8]) -> UInt8 {
        var c = displayAddr ^ sourceAddr
        for b in payload { c ^= b }
        return c
    }
}
