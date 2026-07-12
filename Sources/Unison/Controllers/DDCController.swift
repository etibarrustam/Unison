import Foundation
import IOKit
import CIOAVService

struct DDCDisplay: Identifiable {
    let id: String
    let name: String
    // IOAVServiceRef imports into Swift as IOAVService (CF Ref suffix dropped).
    let service: IOAVService
}

final class DDCController {
    static let vcpBrightness: UInt8 = 0x10
    static let vcpVolume: UInt8 = 0x62
    private let i2cChip: UInt32 = 0x37
    private let subAddress: UInt32 = 0x51

    // Find external displays exposed as DCPAVServiceProxy with Location == External.
    func discover() -> [DDCDisplay] {
        var result: [DDCDisplay] = []
        var iterator = io_iterator_t()
        let match = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return result
        }
        var index = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            guard location == "External" else { continue }
            guard let av = IOAVServiceCreateWithService(kCFAllocatorDefault, service) else { continue }
            index += 1
            result.append(DDCDisplay(id: "ext-\(index)", name: "External Display \(index)", service: av))
        }
        IOObjectRelease(iterator)
        return result
    }

    func setBrightness(_ d: DDCDisplay, percent: Int) {
        write(d, DDCMessage.setVCP(Self.vcpBrightness, scaled(percent)))
    }

    func setVolume(_ d: DDCDisplay, percent: Int) {
        write(d, DDCMessage.setVCP(Self.vcpVolume, scaled(percent)))
    }

    // Best-effort: retry a few times; success if any read parses for this code.
    func probe(_ d: DDCDisplay, code: UInt8) -> Bool {
        for _ in 0..<5 {
            write(d, DDCMessage.getVCP(code))
            usleep(40_000)
            var buf = [UInt8](repeating: 0, count: 12)
            let r = IOAVServiceReadI2C(d.service, i2cChip, subAddress, &buf, 12)
            if r == kIOReturnSuccess, DDCMessage.parseGetReply(code, buf) != nil {
                return true
            }
            usleep(40_000)
        }
        return false
    }

    private func scaled(_ percent: Int) -> UInt16 {
        UInt16(min(100, max(0, percent)))
    }

    private func write(_ d: DDCDisplay, _ bytes: [UInt8]) {
        var b = bytes
        _ = IOAVServiceWriteI2C(d.service, i2cChip, subAddress, &b, UInt32(b.count))
    }
}
