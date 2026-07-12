import Testing
@testable import Unison

struct LevelMathTests {
    @Test func clamp() {
        #expect(LevelMath.clamp(-0.2) == 0.0)
        #expect(LevelMath.clamp(1.5) == 1.0)
        #expect(LevelMath.clamp(0.4) == 0.4)
    }

    @Test func stepClampsAtBounds() {
        #expect(LevelMath.step(0.95, by: 0.1) == 1.0)
        #expect(LevelMath.step(0.05, by: -0.1) == 0.0)
        #expect(abs(LevelMath.step(0.5, by: 0.0625) - 0.5625) < 0.0001)
    }

    // Pan 0 = full left, 0.5 = center (both full), 1 = full right.
    @Test func channelGains() {
        let center = LevelMath.channelGains(volume: 0.8, pan: 0.5)
        #expect(abs(center.left - 0.8) < 0.0001)
        #expect(abs(center.right - 0.8) < 0.0001)

        let left = LevelMath.channelGains(volume: 0.8, pan: 0)
        #expect(abs(left.left - 0.8) < 0.0001)
        #expect(left.right == 0)

        let right = LevelMath.channelGains(volume: 0.8, pan: 1)
        #expect(right.left == 0)
        #expect(abs(right.right - 0.8) < 0.0001)

        let leaning = LevelMath.channelGains(volume: 0.8, pan: 0.75)
        #expect(abs(leaning.left - 0.4) < 0.0001)
        #expect(abs(leaning.right - 0.8) < 0.0001)
    }
}
