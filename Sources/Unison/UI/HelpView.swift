import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("What Unison does",
                    "Unison controls the volume and brightness of everything connected to your Mac from one place: the built-in speakers and display, headphones, and external monitors. The volume and brightness keys move all devices together, and the menu bar panel adjusts each one individually.")

                section("Why it exists",
                    "When you play sound to several outputs at once (a Multi-Output Device, set up in Audio MIDI Setup), macOS disables the volume keys and greys out the volume slider. And monitors connected over HDMI or DisplayPort expose no volume or brightness control to macOS at all. Unison fills both gaps: it drives each speaker directly and talks to monitors over DDC/CI, the protocol monitors use for their on-screen menu settings.")

                section("Using a second display",
                    "External monitors appear automatically in both columns of the menu panel if they support DDC/CI (most do). Brightness works on nearly every monitor; volume only on monitors with speakers. If a monitor is missing, click Refresh Devices in the menu panel, and check it is connected directly rather than through a hub or KVM.")

                section("Keeping devices in balance",
                    "In Settings, each device has a max output slider. A device capped at 80% follows every volume or brightness change but always stays proportionally below the rest: at zero everything is silent or dark, at full level the capped device sits at 80%. Use it when one speaker is louder than the other, or when one display should stay dimmer, for example next to a dark code editor.")

                section("Keyboard",
                    "Volume and brightness keys move all devices by default; pick a single target device in Settings if you prefer. Unison needs Accessibility permission (System Settings, Privacy and Security, Accessibility) to receive the keys. Without it, the sliders still work but the keyboard does not.")

                section("Overlay",
                    "Key presses show a level overlay. Unison's own overlay displays the exact level; switching it off in Settings uses the standard macOS bezel instead, which on macOS Tahoe cannot show the real level.")

                section("Notes",
                    "Levels are remembered and restored on launch. Plug in headphones or a monitor, then use Refresh Devices to pick them up. Unison replaces tools like MonitorControl and Background Music for this workflow.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 520)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
