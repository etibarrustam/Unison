import Foundation
import AppKit

enum DeviceDiscovery {
    static func buildInitialState() -> (speakers: [SpeakerDevice], displays: [DisplayDevice], applier: HardwareApplier) {
        let audio = AudioController()
        let ddc = DDCController()
        let builtin = BuiltinDisplayController()

        let ddcList = ddc.discover()
        var ddcByID: [String: DDCDisplay] = [:]
        for d in ddcList { ddcByID[d.id] = d }
        let saved = Persistence.load()
        let names = screenNames()

        // Speakers: every real CoreAudio output with software volume
        // (built-in, headphones, USB, Bluetooth) + each DDC display that
        // supports volume. Virtual and aggregate devices are skipped: the
        // Multi-Output Device is controlled through its members, not itself.
        // A monitor's speakers go over DDC; CoreAudio cannot set their volume.
        var speakers: [SpeakerDevice] = []
        for out in audio.outputDevices()
        where out.supportsSoftwareVolume && !out.isVirtualOrAggregate {
            let key = "spk-ca-\(out.uid)"
            speakers.append(SpeakerDevice(id: key, name: out.name,
                backend: .coreAudio(out.id),
                volume: saved["vol.\(key)"] ?? 0.3, muted: false))
        }
        for (i, d) in ddcList.enumerated() where ddc.probe(d, code: DDCController.vcpVolume) {
            let key = "spk-\(names.externalKey(i, fallback: d.id))"
            speakers.append(SpeakerDevice(id: key, name: names.externalName(i, fallback: d.name),
                backend: .ddc(d.id),
                volume: saved["vol.\(key)"] ?? 0.3, muted: false))
        }

        // Displays: built-in panel + each DDC display that supports brightness.
        var displays: [DisplayDevice] = []
        if builtin.isAvailable {
            displays.append(DisplayDevice(id: "builtin", name: names.builtin ?? "Built-in Display",
                backend: .builtin, brightness: saved["bri.builtin"] ?? 0.7))
        }
        for (i, d) in ddcList.enumerated() where ddc.probe(d, code: DDCController.vcpBrightness) {
            let key = "dsp-\(names.externalKey(i, fallback: d.id))"
            displays.append(DisplayDevice(id: key, name: names.externalName(i, fallback: d.name),
                backend: .ddc(d.id), brightness: saved["bri.\(key)"] ?? 0.7))
        }

        let applier = HardwareApplier(audio: audio, ddc: ddc, builtin: builtin, ddcDisplays: ddcByID)
        return (speakers, displays, applier)
    }

    private struct ScreenNames {
        let builtin: String?
        let externals: [(name: String, key: String)]
        // Matches DDC displays to screens by order; exact with one external,
        // best-effort with several.
        func externalName(_ index: Int, fallback: String) -> String {
            index < externals.count ? externals[index].name : fallback
        }
        // Stable identity so a monitor keeps its settings and a different
        // monitor never inherits them.
        func externalKey(_ index: Int, fallback: String) -> String {
            index < externals.count ? externals[index].key : fallback
        }
    }

    private static func screenNames() -> ScreenNames {
        var builtin: String?
        var externals: [(name: String, key: String)] = []
        var seen: Set<String> = []
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if CGDisplayIsBuiltin(n) != 0 {
                builtin = screen.localizedName
            } else {
                var key = "\(CGDisplayVendorNumber(n))-\(CGDisplayModelNumber(n))-\(CGDisplaySerialNumber(n))"
                // Two identical monitors: disambiguate by position.
                if seen.contains(key) { key += "-\(externals.count)" }
                seen.insert(key)
                externals.append((screen.localizedName, key))
            }
        }
        return ScreenNames(builtin: builtin, externals: externals)
    }
}
