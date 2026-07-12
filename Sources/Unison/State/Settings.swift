import SwiftUI
import ServiceManagement

@MainActor
final class Settings: ObservableObject {
    @AppStorage("unison.stepSize") var stepSize: Double = 0.0625
    @AppStorage("unison.keyboardTarget") var keyboardTarget: String = "all"
    @AppStorage("unison.keyboardBrightnessTarget") var keyboardBrightnessTarget: String = "all"
    @AppStorage("unison.hudVolume") var hudVolume: Bool = true
    @AppStorage("unison.hudBrightness") var hudBrightness: Bool = true
    @AppStorage("unison.spatial") var spatialEnabled: Bool = false

    // These publish manually and only on real changes: MenuBarExtra
    // rewrites its isInserted binding on every scene evaluation, and an
    // unconditional objectWillChange would loop the view graph forever.

    // Persisted. Recovery from a hidden icon: opening the app again fires
    // the reopen handler, which turns the icon back on.
    var menuIconVisible: Bool {
        willSet { if newValue != menuIconVisible { objectWillChange.send() } }
        didSet {
            guard menuIconVisible != oldValue else { return }
            UserDefaults.standard.set(menuIconVisible, forKey: "unison.menuIconVisible")
        }
    }

    var disabledDevices: Set<String> {
        willSet { if newValue != disabledDevices { objectWillChange.send() } }
        didSet {
            guard disabledDevices != oldValue else { return }
            UserDefaults.standard.set(Array(disabledDevices), forKey: "unison.disabledDevices")
        }
    }

    var launchAtLogin: Bool {
        willSet { if newValue != launchAtLogin { objectWillChange.send() } }
        didSet {
            guard launchAtLogin != oldValue else { return }
            updateLoginItem(launchAtLogin)
        }
    }

    // Per-device output scales in 0.1...1.0 (1 = full output). The popover
    // shows uniform levels; hardware receives level * scale.
    var volumeScales: [String: Double] {
        willSet { if newValue != volumeScales { objectWillChange.send() } }
        didSet {
            guard volumeScales != oldValue else { return }
            UserDefaults.standard.set(volumeScales, forKey: "unison.volumeScales")
        }
    }
    var brightnessScales: [String: Double] {
        willSet { if newValue != brightnessScales { objectWillChange.send() } }
        didSet {
            guard brightnessScales != oldValue else { return }
            UserDefaults.standard.set(brightnessScales, forKey: "unison.brightnessScales")
        }
    }

    // Speaker positions for stereo placement, raw values of SpeakerPosition.
    var speakerPositions: [String: String] {
        willSet { if newValue != speakerPositions { objectWillChange.send() } }
        didSet {
            guard speakerPositions != oldValue else { return }
            UserDefaults.standard.set(speakerPositions, forKey: "unison.speakerPositions")
        }
    }

    func position(_ id: String) -> SpeakerPosition {
        SpeakerPosition(rawValue: speakerPositions[id] ?? "center") ?? .center
    }

    init() {
        speakerPositions = UserDefaults.standard.dictionary(forKey: "unison.speakerPositions") as? [String: String] ?? [:]
        menuIconVisible = UserDefaults.standard.object(forKey: "unison.menuIconVisible") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let saved = UserDefaults.standard.stringArray(forKey: "unison.disabledDevices") ?? []
        disabledDevices = Set(saved)
        volumeScales = UserDefaults.standard.dictionary(forKey: "unison.volumeScales") as? [String: Double] ?? [:]
        brightnessScales = UserDefaults.standard.dictionary(forKey: "unison.brightnessScales") as? [String: Double] ?? [:]
    }

    func isEnabled(_ id: String) -> Bool { !disabledDevices.contains(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        if on { disabledDevices.remove(id) } else { disabledDevices.insert(id) }
    }

    private func updateLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Unison login item error: \(error.localizedDescription)")
        }
    }
}
