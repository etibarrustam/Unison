import SwiftUI

// Top-down room editor for spatial mode: the listener sits in the middle
// facing up, one draggable dot per speaker channel. A dot's direction
// from the listener drives the spatial mix and its distance drives the
// wavefront alignment delay. Dots are colored by device and cannot move
// to another device: a speaker's position in the room is adjustable, the
// hardware it belongs to is not.
struct SpeakerArrangementView: View {
    @ObservedObject var settings: Settings
    let spatial: SpatialEngine
    @Environment(\.dismiss) private var dismiss

    private let room = 3.0            // meters from the listener to the edge
    private let canvas: CGFloat = 440
    private let minDistance = 0.3     // meters; keeps dots off the listener

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal]

    private var speakers: [SpatialSpeaker] { spatial.availableSpeakers() }

    private var deviceUIDs: [String] {
        var seen: [String] = []
        for s in speakers where !seen.contains(s.deviceUID) { seen.append(s.deviceUID) }
        return seen
    }

    private func color(_ uid: String) -> Color {
        Self.palette[(deviceUIDs.firstIndex(of: uid) ?? 0) % Self.palette.count]
    }

    private func deviceName(_ uid: String) -> String {
        spatial.outputDeviceList().first { $0.uid == uid }?.name ?? uid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrange Speakers").font(.headline)
            Text("Drag each speaker to where it stands in your room. You are in the middle, facing the top. Nearer speakers are delayed a fraction so everything arrives at your seat together.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            roomView
                .frame(width: canvas, height: canvas)
            legend
            HStack {
                Button("Reset") {
                    settings.speakerPlacements = [:]
                    apply()
                }
                .help("Return every speaker to its natural stereo side")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var roomView: some View {
        ZStack {
            // Distance rings, one per meter.
            ForEach(1...3, id: \.self) { m in
                Circle()
                    .stroke(.quaternary, lineWidth: 1)
                    .frame(width: ringSize(Double(m)), height: ringSize(Double(m)))
            }
            Text("Front").font(.caption2).foregroundStyle(.secondary)
                .position(x: canvas / 2, y: 10)
            Text("Behind you").font(.caption2).foregroundStyle(.secondary)
                .position(x: canvas / 2, y: canvas - 10)

            VStack(spacing: 2) {
                Image(systemName: "person.fill").font(.system(size: 22))
                Text("You").font(.caption2).foregroundStyle(.secondary)
            }
            .position(x: canvas / 2, y: canvas / 2)

            ForEach(speakers) { sp in
                speakerDot(sp)
            }
        }
    }

    private func speakerDot(_ sp: SpatialSpeaker) -> some View {
        let p = placement(sp)
        let side = sp.name.hasSuffix("Left") ? "L" : sp.name.hasSuffix("Right") ? "R" : "\(sp.channel)"
        return ZStack {
            Circle().fill(color(sp.deviceUID)).frame(width: 28, height: 28)
            Text(side).font(.caption.bold()).foregroundStyle(.white)
        }
        .position(point(p))
        .help("\(sp.name), \(String(format: "%.1f", SpatialMix.distance(x: p.x, y: p.y))) m")
        .gesture(DragGesture(coordinateSpace: .local).onChanged { g in
            settings.speakerPlacements[sp.id] = clamp(meters(g.location))
            apply()
        })
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(deviceUIDs, id: \.self) { uid in
                HStack(spacing: 4) {
                    Circle().fill(color(uid)).frame(width: 8, height: 8)
                    Text(deviceName(uid)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func apply() {
        spatial.applyMix(mode: .spatial(settings.speakerPlacements))
    }

    // MARK: - Geometry

    private var scale: CGFloat { (canvas / 2 - 28) / CGFloat(room) }

    private func ringSize(_ m: Double) -> CGFloat { CGFloat(m) * scale * 2 }

    private func placement(_ sp: SpatialSpeaker) -> (x: Double, y: Double) {
        if let p = settings.speakerPlacements[sp.id], p.count == 2 { return (p[0], p[1]) }
        let d = spatial.defaultPlacement(sp)
        return (d[0], d[1])
    }

    private func point(_ p: (x: Double, y: Double)) -> CGPoint {
        CGPoint(x: canvas / 2 + CGFloat(p.x) * scale,
                y: canvas / 2 - CGFloat(p.y) * scale)
    }

    private func meters(_ pt: CGPoint) -> (x: Double, y: Double) {
        (Double((pt.x - canvas / 2) / scale), Double((canvas / 2 - pt.y) / scale))
    }

    private func clamp(_ p: (x: Double, y: Double)) -> [Double] {
        let d = SpatialMix.distance(x: p.x, y: p.y)
        if d < 0.001 { return [0, minDistance] }
        let k = d < minDistance ? minDistance / d : d > room ? room / d : 1
        return [p.x * k, p.y * k]
    }
}
