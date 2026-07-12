import Foundation
import CoreGraphics

final class BuiltinDisplayController {
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let setFn: SetFn?
    private let displayID: CGDirectDisplayID?

    init() {
        // The built-in panel is not always the main display; search for it.
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        displayID = (0..<Int(count)).map { ids[$0] }.first { CGDisplayIsBuiltin($0) != 0 }

        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        if let sym = handle.flatMap({ dlsym($0, "DisplayServicesSetBrightness") }) {
            setFn = unsafeBitCast(sym, to: SetFn.self)
        } else {
            setFn = nil
        }
    }

    var isAvailable: Bool { setFn != nil && displayID != nil }

    func setBrightness(_ value: Double) {
        guard let setFn, let displayID else { return }
        _ = setFn(displayID, Float(min(1, max(0, value))))
    }
}
