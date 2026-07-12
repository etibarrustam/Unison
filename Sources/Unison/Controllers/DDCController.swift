import Foundation
import IOKit
import CIOAVService

struct DDCDisplay: Identifiable {
    let id: String
    let name: String
    // IOAVServiceRef imports into Swift as IOAVService (CF Ref suffix dropped).
    let service: IOAVService
    // Matches the display to its NSScreen; nil when the registry lacks it.
    let edidUUID: String?
}

@MainActor
final class DDCController {
    static let vcpBrightness: UInt8 = 0x10
    static let vcpVolume: UInt8 = 0x62
    static let vcpBalance: UInt8 = 0x93
    private let i2cChip: UInt32 = 0x37
    private let subAddress: UInt32 = 0x51

    // Slider drags fire faster than the DDC bus likes; coalesce writes to
    // one per interval per display with a trailing write for the final value.
    private let minWriteInterval: TimeInterval = 0.04
    private var lastWriteAt: [String: Date] = [:]
    private var pendingWrite: [String: DispatchWorkItem] = [:]

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
            result.append(DDCDisplay(id: "ext-\(index)", name: "External Display \(index)",
                                     service: av, edidUUID: edidUUID(service)))
        }
        IOObjectRelease(iterator)
        return result
    }

    func setBrightness(_ d: DDCDisplay, percent: Int) {
        throttledWrite(d, key: "\(d.id).b", DDCMessage.setVCP(Self.vcpBrightness, scaled(percent)))
    }

    func setVolume(_ d: DDCDisplay, percent: Int) {
        throttledWrite(d, key: "\(d.id).v", DDCMessage.setVCP(Self.vcpVolume, scaled(percent)))
    }

    // Balance semantics per MCCS: midpoint is centered, low favors left.
    func setBalance(_ d: DDCDisplay, pan: Double, max: Int) {
        let value = Int((LevelMath.clamp(pan) * Double(max)).rounded())
        throttledWrite(d, key: "\(d.id).bal", DDCMessage.setVCP(Self.vcpBalance, UInt16(clamping: value)))
    }

    // Like probe, but reports the feature maximum for scaling.
    func probeMax(_ d: DDCDisplay, code: UInt8) -> Int? {
        for _ in 0..<5 {
            write(d, DDCMessage.getVCP(code))
            usleep(40_000)
            var buf = [UInt8](repeating: 0, count: 12)
            let r = IOAVServiceReadI2C(d.service, i2cChip, subAddress, &buf, 12)
            if r == kIOReturnSuccess, let reply = DDCMessage.parseGetReply(code, buf) {
                return Int(reply.max)
            }
            usleep(40_000)
        }
        return nil
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

    // Walk up the registry for the EDID UUID that ties this AV service to
    // a CGDisplay.
    private func edidUUID(_ service: io_service_t) -> String? {
        var entry = service
        IOObjectRetain(entry)
        defer { IOObjectRelease(entry) }
        for _ in 0..<8 {
            if let s = IORegistryEntryCreateCFProperty(
                entry, "EDID UUID" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String {
                return s.uppercased()
            }
            var parent = io_service_t()
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            IOObjectRelease(entry)
            entry = parent
        }
        return nil
    }

    private func scaled(_ percent: Int) -> UInt16 {
        UInt16(min(100, max(0, percent)))
    }

    private func throttledWrite(_ d: DDCDisplay, key: String, _ bytes: [UInt8]) {
        pendingWrite[key]?.cancel()
        let now = Date()
        if let last = lastWriteAt[key], now.timeIntervalSince(last) < minWriteInterval {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastWriteAt[key] = Date()
                    self.write(d, bytes)
                }
            }
            pendingWrite[key] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + minWriteInterval, execute: work)
        } else {
            lastWriteAt[key] = now
            write(d, bytes)
        }
    }

    private func write(_ d: DDCDisplay, _ bytes: [UInt8]) {
        var b = bytes
        _ = IOAVServiceWriteI2C(d.service, i2cChip, subAddress, &b, UInt32(b.count))
    }
}
