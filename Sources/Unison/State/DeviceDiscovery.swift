import Foundation

enum DeviceDiscovery {
    static func buildInitialState() -> (speakers: [SpeakerDevice], displays: [DisplayDevice], applier: HardwareApplier) {
        let audio = AudioController()
        let ddc = DDCController()
        let builtin = BuiltinDisplayController()

        let ddcList = ddc.discover()
        var ddcByID: [String: DDCDisplay] = [:]
        for d in ddcList { ddcByID[d.id] = d }
        let saved = Persistence.load()

        // Speakers: built-in Mac speakers via CoreAudio + each DDC display that supports volume.
        // A monitor's speakers go over DDC; CoreAudio cannot set their volume.
        var speakers: [SpeakerDevice] = []
        if let mac = audio.outputDevices().first(where: { $0.supportsSoftwareVolume && $0.name.contains("MacBook") }) {
            speakers.append(SpeakerDevice(id: "mac", name: "MacBook Speakers",
                backend: .coreAudio(mac.id),
                volume: saved["vol.mac"] ?? 0.3, muted: false))
        }
        for d in ddcList where ddc.probe(d, code: DDCController.vcpVolume) {
            speakers.append(SpeakerDevice(id: "spk-\(d.id)", name: d.name,
                backend: .ddc(d.id),
                volume: saved["vol.spk-\(d.id)"] ?? 0.3, muted: false))
        }

        // Displays: built-in panel + each DDC display that supports brightness.
        var displays: [DisplayDevice] = []
        if builtin.isAvailable {
            displays.append(DisplayDevice(id: "builtin", name: "Built-in Display",
                backend: .builtin, brightness: saved["bri.builtin"] ?? 0.7))
        }
        for d in ddcList where ddc.probe(d, code: DDCController.vcpBrightness) {
            displays.append(DisplayDevice(id: "dsp-\(d.id)", name: d.name,
                backend: .ddc(d.id), brightness: saved["bri.dsp-\(d.id)"] ?? 0.7))
        }

        let applier = HardwareApplier(audio: audio, ddc: ddc, builtin: builtin, ddcDisplays: ddcByID)
        return (speakers, displays, applier)
    }
}
