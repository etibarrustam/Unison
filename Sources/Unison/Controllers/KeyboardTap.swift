import AppKit
import CoreGraphics

// Runs on the main run loop; the tap callback fires on the main thread.
@MainActor
final class KeyboardTap {
    enum MediaKey { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }
    var onKey: ((MediaKey) -> Void)?

    private var tap: CFMachPort?

    static func accessibilityGranted(prompt: Bool) -> Bool {
        // Literal key avoids the concurrency-unsafe kAXTrustedCheckOptionPrompt global.
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask = 1 << 14  // NSSystemDefined
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let this = Unmanaged<KeyboardTap>.fromOpaque(refcon!).takeUnretainedValue()
            // Safe: the tap source is scheduled on the main run loop.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                // macOS disables taps whose callback is too slow; recover.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    this.reenable(after: type)
                    return false
                }
                return this.handle(event)
            }
            if consumed { return nil }  // consume keys we own
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // Accessibility is often granted after the first launch, and creating
    // the tap fails until then. Retry quietly so the keys start working
    // the moment the permission arrives, with no relaunch.
    private var retryTimer: Timer?

    func startRetrying() {
        if start() { return }
        NSLog("Unison: event tap unavailable, waiting for the Accessibility permission")
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.start() {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    NSLog("Unison: event tap started after permission grant")
                }
            }
        }
    }

    private func reenable(after type: CGEventType) {
        guard let tap else { return }
        NSLog("Unison: event tap disabled (type \(type.rawValue)), re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Returns true if the event is a media key we handle (and should consume).
    private func handle(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return false }
        let keyCode = (ns.data1 & 0xFFFF0000) >> 16
        let keyState = (ns.data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else { return false }  // key down only
        let key: MediaKey?
        switch keyCode {
        case 0: key = .volumeUp       // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown     // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute           // NX_KEYTYPE_MUTE
        case 2: key = .brightnessUp   // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: key = nil
        }
        guard let key else { return false }
        // Defer DDC and HUD work; the callback must return fast or macOS
        // disables the tap for being too slow.
        Task { @MainActor in self.onKey?(key) }
        return true
    }
}
