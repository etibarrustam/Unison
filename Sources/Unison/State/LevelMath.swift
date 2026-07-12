import Foundation

enum LevelMath {
    static func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }
    static func step(_ value: Double, by delta: Double) -> Double { clamp(value + delta) }
}
