import AppKit

// Downloads the BlackHole package and hands it to the macOS installer,
// which shows the native wizard and password prompt. When the driver
// registers, the device watcher picks it up and spatial mode starts.
@MainActor
final class DriverInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle, downloading, launched, failed(String)
    }
    @Published private(set) var phase: Phase = .idle

    private static let pkgURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg")!

    func install() {
        guard phase != .downloading else { return }
        phase = .downloading
        Task {
            do {
                let (tmp, response) = try await URLSession.shared.download(from: Self.pkgURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    phase = .failed("Download failed. Check your connection and try again.")
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BlackHole2ch.pkg")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                NSWorkspace.shared.open(dest)
                phase = .launched
            } catch {
                phase = .failed("Download failed. Check your connection and try again.")
            }
        }
    }
}
