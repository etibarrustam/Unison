import AppKit
import CoreAudio

// Watches for device hot-plug: CoreAudio device list changes (headphones,
// USB, Bluetooth) and screen configuration changes (monitors). Events are
// debounced because plugging one device fires several notifications.
@MainActor
final class DeviceWatcher {
    var onChange: (() -> Void)?
    private var pending: DispatchWorkItem?

    func start() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, .main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.schedule() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
