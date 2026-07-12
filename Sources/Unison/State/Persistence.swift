import Foundation

enum Persistence {
    private static let key = "unison.levels.v1"

    static func saveVolumes(_ speakers: [SpeakerDevice], brightness displays: [DisplayDevice]) {
        var map: [String: Double] = [:]
        for s in speakers { map["vol.\(s.id)"] = s.volume }
        for d in displays { map["bri.\(d.id)"] = d.brightness }
        UserDefaults.standard.set(map, forKey: key)
    }

    static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
