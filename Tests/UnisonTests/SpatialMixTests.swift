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
        // LG Right at 0.25: full left, half right.
        #expect(abs(matrix[3]!.l - 1.0) < 0.0001)
        #expect(abs(matrix[3]!.r - 0.5) < 0.0001)
        // Mac Left at 0.75: half left, full right.
        #expect(abs(matrix[4]!.l - 0.5) < 0.0001)
        #expect(abs(matrix[4]!.r - 1.0) < 0.0001)
        // Mac Right: pure right content.
        #expect(matrix[5]!.l == 0)
        #expect(abs(matrix[5]!.r - 1.0) < 0.0001)
    }

    // A speaker missing a position defaults to center: both channels full.
    @Test func speakersWithoutPositionsPlayEverything() {
        let speakers = [
            SpatialSpeaker(deviceUID: "d", channel: 1, name: "One", position: 0.5)
        ]
        let matrix = SpatialMix.matrix(speakers: speakers, deviceOrder: ["d"],
                                       channelCounts: ["d": 1], outputOffset: 2)
        #expect(abs(matrix[2]!.l - 1.0) < 0.0001)
        #expect(abs(matrix[2]!.r - 1.0) < 0.0001)
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
