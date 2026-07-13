import Testing
@testable import Unison

struct SpatialMixTests {
    // Two devices, two channels each, ordered LG then MacBook in the
    // aggregate. Positions spread left to right.
    @Test func matrixMapsChannelsWithGains() {
        let speakers = [
            SpatialSpeaker(deviceUID: "lg", channel: 1, name: "LG Left", position: 0.0),
            SpatialSpeaker(deviceUID: "lg", channel: 2, name: "LG Right", position: 0.25),
            SpatialSpeaker(deviceUID: "mac", channel: 1, name: "Mac Left", position: 0.75),
            SpatialSpeaker(deviceUID: "mac", channel: 2, name: "Mac Right", position: 1.0)
        ]
        let matrix = SpatialMix.matrix(
            speakers: speakers,
            deviceOrder: ["lg", "mac"],
            channelCounts: ["lg": 2, "mac": 2],
            outputOffset: 2)  // aggregate channels 0-1 belong to BlackHole

        // LG Left is aggregate channel 2 (0-based): pure left content.
        #expect(abs(matrix[2]!.l - 1.0) < 0.0001)
        #expect(matrix[2]!.r == 0)
        // LG Right at 0.25: 2:1 left to right, normalized to unity sum.
        #expect(abs(matrix[3]!.l - 2.0 / 3.0) < 0.0001)
        #expect(abs(matrix[3]!.r - 1.0 / 3.0) < 0.0001)
        // Mac Left at 0.75: 1:2 left to right, normalized to unity sum.
        #expect(abs(matrix[4]!.l - 1.0 / 3.0) < 0.0001)
        #expect(abs(matrix[4]!.r - 2.0 / 3.0) < 0.0001)
        // Mac Right: pure right content.
        #expect(matrix[5]!.l == 0)
        #expect(abs(matrix[5]!.r - 1.0) < 0.0001)
    }

    // A centered speaker mixes both sides at half gain, so the summed
    // signal stays at unity instead of clipping on correlated content.
    @Test func speakersWithoutPositionsPlayEverything() {
        let speakers = [
            SpatialSpeaker(deviceUID: "d", channel: 1, name: "One", position: 0.5)
        ]
        let matrix = SpatialMix.matrix(speakers: speakers, deviceOrder: ["d"],
                                       channelCounts: ["d": 1], outputOffset: 2)
        #expect(abs(matrix[2]!.l - 0.5) < 0.0001)
        #expect(abs(matrix[2]!.r - 0.5) < 0.0001)
    }

    // Full-scale correlated content must never clip: l + r stays at or
    // below 1 for every position.
    @Test func gainsNeverExceedUnitySum() {
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let speakers = [SpatialSpeaker(deviceUID: "d", channel: 1, name: "S", position: p)]
            let matrix = SpatialMix.matrix(speakers: speakers, deviceOrder: ["d"],
                                           channelCounts: ["d": 1], outputOffset: 0)
            let g = matrix[0]!
            #expect(g.l + g.r <= 1.0001)
        }
    }

    // Devices not mentioned in the speaker list get silence, and unknown
    // devices in the speaker list are ignored.
    @Test func unmatchedChannelsAbsent() {
        let speakers = [
            SpatialSpeaker(deviceUID: "ghost", channel: 1, name: "?", position: 0.5)
        ]
        let matrix = SpatialMix.matrix(speakers: speakers, deviceOrder: ["real"],
                                       channelCounts: ["real": 2], outputOffset: 2)
        #expect(matrix.isEmpty)
    }
}
