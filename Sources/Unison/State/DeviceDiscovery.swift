import Foundation
import AppKit

@MainActor
enum DeviceDiscovery {
    static func buildInitialState() -> (speakers: [SpeakerDevice], displays: [DisplayDevice], applier: HardwareApplier) {
        let audio = AudioController()
        let ddc = DDCController()
        let builtin = BuiltinDisplayController()

        let ddcList = ddc.discover()
        var ddcByID: [String: DDCDisplay] = [:]
        for d in ddcList { ddcByID[d.id] = d }
        let saved = Persistence.load()
        let screens = screenInfo()

        // Speakers: real CoreAudio outputs with software volume, plus DDC
        // monitors with speakers. Aggregates are driven via their members.
        var speakers: [SpeakerDevice] = []
        var balanceMax: [String: Int] = [:]
        for out in audio.outputDevices()
        where out.supportsSoftwareVolume && !out.isVirtualOrAggregate {
            let key = "spk-ca-\(out.uid)"
            speakers.append(SpeakerDevice(id: key, name: out.name,
                backend: .coreAudio(out.id),
                volume: saved["vol.\(key)"] ?? 0.3, muted: false,
                pannable: audio.supportsPan(out.id) || audio.hasChannelVolumes(out.id)))
        }
        for (i, d) in ddcList.enumerated() {
            let ident = screens.match(d, index: i)
            let key = "spk-\(ident.key)"
            guard cachedProbe(ddc, d, code: DDCController.vcpVolume, cacheKey: key) else { continue }
            // Write-only philosophy: balance is sent regardless; a probe
            // only refines the value range. Firmware without balance
            // ignores the command.
            balanceMax[d.id] = cachedBalanceMax(ddc, d, cacheKey: key) ?? 100
            speakers.append(SpeakerDevice(id: key, name: ident.name,
                backend: .ddc(d.id),
                volume: saved["vol.\(key)"] ?? 0.3, muted: false,
                pannable: true))
        }

        // Displays: built-in panel plus DDC monitors with brightness.
        var displays: [DisplayDevice] = []
        if builtin.isAvailable {
            displays.append(DisplayDevice(id: "builtin", name: screens.builtin ?? "Built-in Display",
                backend: .builtin, brightness: saved["bri.builtin"] ?? 0.7))
        }
        for (i, d) in ddcList.enumerated() {
            let ident = screens.match(d, index: i)
            let key = "dsp-\(ident.key)"
            guard cachedProbe(ddc, d, code: DDCController.vcpBrightness, cacheKey: key) else { continue }
            displays.append(DisplayDevice(id: key, name: ident.name,
                backend: .ddc(d.id), brightness: saved["bri.\(key)"] ?? 0.7))
        }

        let applier = HardwareApplier(audio: audio, ddc: ddc, builtin: builtin,
                                      ddcDisplays: ddcByID, ddcBalanceMax: balanceMax)
        return (speakers, displays, applier)
    }

    // Audio balance support and its maximum, cached like the other probes.
    // 0 max marks unsupported so flaky monitors are not re-probed forever.
    private static func cachedBalanceMax(_ ddc: DDCController, _ d: DDCDisplay,
                                         cacheKey: String) -> Int? {
        let key = "unison.balmax.\(cacheKey)"
        if let cached = UserDefaults.standard.object(forKey: key) as? Int {
            return cached > 0 ? cached : nil
        }
        let max = ddc.probeMax(d, code: DDCController.vcpBalance)
        UserDefaults.standard.set(max ?? 0, forKey: key)
        return max
    }

    // Probing blocks the main thread on flaky DDC links, so positive
    // results are cached per monitor identity; unsupported codes re-probe.
    private static func cachedProbe(_ ddc: DDCController, _ d: DDCDisplay,
                                    code: UInt8, cacheKey: String) -> Bool {
        let key = "unison.caps.\(cacheKey).\(code)"
        if UserDefaults.standard.bool(forKey: key) { return true }
        let ok = ddc.probe(d, code: code)
        if ok { UserDefaults.standard.set(true, forKey: key) }
        return ok
    }

    private struct ScreenInfo {
        let builtin: String?
        let externalsByUUID: [String: (name: String, key: String)]
        let externalsInOrder: [(name: String, key: String)]

        // Prefer the EDID UUID (exact identity); fall back to order.
        func match(_ d: DDCDisplay, index: Int) -> (name: String, key: String) {
            if let uuid = d.edidUUID, let hit = externalsByUUID[uuid] { return hit }
            if index < externalsInOrder.count { return externalsInOrder[index] }
            return (d.name, d.id)
        }
    }

    private static func screenInfo() -> ScreenInfo {
        var builtin: String?
        var byUUID: [String: (name: String, key: String)] = [:]
        var inOrder: [(name: String, key: String)] = []
        var seen: Set<String> = []
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if CGDisplayIsBuiltin(n) != 0 {
                builtin = screen.localizedName
                continue
            }
            var key = "\(CGDisplayVendorNumber(n))-\(CGDisplayModelNumber(n))-\(CGDisplaySerialNumber(n))"
            if seen.contains(key) { key += "-\(inOrder.count)" }
            seen.insert(key)
            let entry = (screen.localizedName, key)
            inOrder.append(entry)
            if let cfUUID = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() {
                let uuid = CFUUIDCreateString(kCFAllocatorDefault, cfUUID) as String
                byUUID[uuid.uppercased()] = entry
            }
        }
        return ScreenInfo(builtin: builtin, externalsByUUID: byUUID, externalsInOrder: inOrder)
    }
}
