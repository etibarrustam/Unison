import AppKit

// Native macOS bezel via the private OSD.framework. Used when the custom
// overlay is disabled. On macOS Tahoe the bezel draws but ignores the
// fill value (known OS limitation, also hits MonitorControl).
@MainActor
enum SystemOSD {
    typealias Kind = OverlayKind

    private static let manager: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_NOW)
        guard let cls = NSClassFromString("OSDManager") as? NSObject.Type,
              let mgr = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject
        else { return nil }
        return mgr
    }()

    private static let showSel = NSSelectorFromString(
        "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")

    static func show(_ kind: Kind, value: Double) {
        guard let mgr = manager, mgr.responds(to: showSel) else { return }
        let image: CLongLong
        switch kind {
        case .brightness: image = 1
        case .volume: image = value == 0 ? 4 : 3
        case .mute: image = 4
        }
        let filled = UInt32((LevelMath.clamp(value) * 16).rounded())
        typealias Fn = @convention(c) (NSObject, Selector, CLongLong, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void
        let fn = unsafeBitCast(mgr.method(for: showSel), to: Fn.self)
        fn(mgr, showSel, image, CGMainDisplayID(), 0x1f4, 1000, filled, 16, false)
    }
}
