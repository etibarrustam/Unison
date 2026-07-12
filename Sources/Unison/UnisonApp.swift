import SwiftUI

// Recovery path for a hidden menu bar icon in a Dock-less app: opening
// Unison again never restarts it and never re-shows the icon; instead the
// running instance presents the Settings window.
final class ReopenHandler: NSObject, NSApplicationDelegate {
    @MainActor static weak var settings: Settings?
    @MainActor static weak var state: AppState?
    private static let reopenNote = Notification.Name("com.unison.app.reopen")
    private var recoveryWindow: NSWindow?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A windowless menu bar app must not be reaped by macOS automatic
        // or sudden termination.
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar controller")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Single instance: hand off to the running copy and exit.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.unison.app"
        // isTerminated filter: a just-killed predecessor can linger in the
        // list and must not make the fresh instance defer to a corpse.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                      && !$0.isTerminated }
        NSLog("Unison: didFinishLaunching pid=\(ProcessInfo.processInfo.processIdentifier) others=\(others.map { "\($0.processIdentifier):term=\($0.isTerminated)" })")
        if !others.isEmpty {
            NSLog("Unison: deferring to existing instance, exiting")
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenNote, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNote, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.presentRecovery() }
        }
        // Fresh launch with the icon hidden: show Settings so the app
        // is reachable.
        if Self.settings?.menuIconVisible == false {
            Self.presentRecovery()
        }
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NSLog("Unison: reopen event received")
        Self.presentRecovery()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSLog("Unison: applicationShouldTerminate called")
        return .terminateNow
    }

    // Menu bar app: closing the last window (Settings, or the HUD fading
    // out) must never quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor private static var sharedRecoveryWindow: NSWindow?

    @MainActor
    static func presentRecovery() {
        NSLog("Unison: presentRecovery")
        guard let settings, let state else { return }
        let w = sharedRecoveryWindow ?? {
            let w = NSWindow(contentViewController:
                NSHostingController(rootView: SettingsView(settings: settings, state: state)))
            w.title = "Unison Settings"
            w.isReleasedWhenClosed = false
            sharedRecoveryWindow = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
    }
}

@main
struct UnisonApp: App {
    @NSApplicationDelegateAdaptor(ReopenHandler.self) private var reopenHandler
    @StateObject private var state: AppState
    @StateObject private var settings: Settings
    private let keyboard = KeyboardTap()
    private let watcher = DeviceWatcher()

    init() {
        let built = DeviceDiscovery.buildInitialState()
        let s = AppState(applier: built.applier)
        s.speakers = built.speakers
        s.displays = built.displays
        _state = StateObject(wrappedValue: s)
        let cfg = Settings()
        _settings = StateObject(wrappedValue: cfg)
        ReopenHandler.settings = cfg
        ReopenHandler.state = s
        s.isEnabled = { [weak cfg] id in cfg?.isEnabled(id) ?? true }
        s.volumeScale = { [weak cfg] id in cfg?.volumeScales[id] ?? 1 }
        s.brightnessScale = { [weak cfg] id in cfg?.brightnessScales[id] ?? 1 }
        s.spatialEnabled = { [weak cfg] in cfg?.spatialEnabled ?? false }
        s.speakerPosition = { [weak cfg] id in cfg?.position(id) ?? .center }
        // Apply only after the scale and enable closures are wired, so the
        // launch write already respects per-device caps.
        s.applyAll()
        startKeyboard(s, cfg)
        watcher.onChange = { [weak s] in s?.refreshDevices() }
        watcher.start()
    }

    private func startKeyboard(_ state: AppState, _ settings: Settings) {
        let granted = KeyboardTap.accessibilityGranted(prompt: true)
        NSLog("Unison: accessibility granted: \(granted)")
        keyboard.onKey = { key in
            let step = settings.stepSize
            switch key {
            case .volumeUp, .volumeDown:
                let delta = key == .volumeUp ? step : -step
                let shown: Double
                if settings.keyboardTarget == "all" {
                    state.nudgeAllVolume(delta)
                    shown = state.speakers.first?.volume ?? 0
                } else if let s = state.speakers.first(where: { $0.id == settings.keyboardTarget }) {
                    let v = LevelMath.step(s.volume, by: delta)
                    state.setVolume(id: s.id, v)
                    shown = v
                } else {
                    state.nudgeAllVolume(delta)
                    shown = state.speakers.first?.volume ?? 0
                }
                LevelHUD.show(.volume, value: shown, custom: settings.hudVolume)
            case .mute:
                state.toggleMuteAll()
                let muted = state.enabledSpeakersMuted
                let v = muted ? 0 : state.speakers.first?.volume ?? 0
                LevelHUD.show(.mute, value: v, custom: settings.hudVolume)
            case .brightnessUp, .brightnessDown:
                let delta = key == .brightnessUp ? step : -step
                let shown: Double
                if settings.keyboardBrightnessTarget == "all" {
                    state.nudgeAllBrightness(delta)
                    shown = state.displays.first?.brightness ?? 0
                } else if let d = state.displays.first(where: { $0.id == settings.keyboardBrightnessTarget }) {
                    let v = LevelMath.step(d.brightness, by: delta)
                    state.setBrightness(id: d.id, v)
                    shown = v
                } else {
                    state.nudgeAllBrightness(delta)
                    shown = state.displays.first?.brightness ?? 0
                }
                LevelHUD.show(.brightness, value: shown, custom: settings.hudBrightness)
            }
        }
        let started = keyboard.start()
        NSLog("Unison: event tap started: \(started)")
    }

    var body: some Scene {
        MenuBarExtra("Unison", systemImage: "slider.horizontal.3",
                     isInserted: $settings.menuIconVisible) {
            PopoverView(state: state, settings: settings)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView(settings: settings, state: state)
        }

        Window("Unison Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
