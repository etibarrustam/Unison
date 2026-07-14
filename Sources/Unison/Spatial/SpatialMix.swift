import Foundation

// One physical speaker: a single channel of an output device.
struct SpatialSpeaker: Identifiable {
    let deviceUID: String
    let channel: Int      // 1-based channel within its device
    let name: String
    var position: Double  // 0 left ... 1 right

    var id: String { "\(deviceUID)#\(channel)" }
}

enum SpatialMix {
    // Bridge until the arrangement editor exists: a 0...1 slider position
    // maps onto the front arc, -90 degrees (full left) to +90 (full right).
    static func azimuth(fromPosition p: Double) -> Float {
        Float((LevelMath.clamp(p) - 0.5) * 180)
    }

    // Aggregate output channel (0-based) to L/R content gains. Devices
    // are laid out in aggregate order after outputOffset leading channels
    // (the loopback device's own outputs, which must stay silent).
    static func matrix(speakers: [SpatialSpeaker],
                       deviceOrder: [String],
                       channelCounts: [String: Int],
                       outputOffset: Int) -> [Int: (l: Double, r: Double)] {
        var offsets: [String: Int] = [:]
        var next = outputOffset
        for uid in deviceOrder {
            offsets[uid] = next
            next += channelCounts[uid] ?? 0
        }
        var result: [Int: (l: Double, r: Double)] = [:]
        for s in speakers {
            guard let base = offsets[s.deviceUID],
                  let count = channelCounts[s.deviceUID],
                  s.channel >= 1, s.channel <= count else { continue }
            let g = LevelMath.channelGains(volume: 1, pan: s.position)
            // Both sides land in one physical channel, so the correlated
            // sum must stay at unity or loud content clips.
            let sum = g.left + g.right
            let scale = sum > 1 ? 1 / sum : 1
            result[base + s.channel - 1] = (g.left * scale, g.right * scale)
        }
        return result
    }
}
