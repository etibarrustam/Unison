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
}
