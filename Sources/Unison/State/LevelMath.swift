import Foundation

enum LevelMath {
    static func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }
    static func step(_ value: Double, by delta: Double) -> Double { clamp(value + delta) }

    // Linear pan taper: the favored channel stays at full level while the
    // opposite one fades out. Pan 0 = left, 0.5 = center, 1 = right.
    static func channelGains(volume: Double, pan: Double) -> (left: Double, right: Double) {
        let p = clamp(pan)
        return (volume * min(1, 2 * (1 - p)), volume * min(1, 2 * p))
    }
}
