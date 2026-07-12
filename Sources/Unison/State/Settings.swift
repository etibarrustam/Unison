import SwiftUI
import ServiceManagement

@MainActor
final class Settings: ObservableObject {
    @AppStorage("unison.stepSize") var stepSize: Double = 0.0625
    @AppStorage("unison.keyboardTarget") var keyboardTarget: String = "all"
    @AppStorage("unison.hudVolume") var hudVolume: Bool = true
    @AppStorage("unison.hudBrightness") var hudBrightness: Bool = true

    // These publish manually and only on real changes: MenuBarExtra
    // rewrites its isInserted binding on every scene evaluation, and an
    // unconditional objectWillChange would loop the view graph forever.

    // Not persisted across launches: with no Dock icon, a hidden menu bar
    // icon would leave no way back in. Relaunching restores it.
    var menuIconVisible: Bool = true {
        willSet { if newValue != menuIconVisible { objectWillChange.send() } }
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

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let saved = UserDefaults.standard.stringArray(forKey: "unison.disabledDevices") ?? []
        disabledDevices = Set(saved)
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
