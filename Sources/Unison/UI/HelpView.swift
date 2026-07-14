import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("What Unison does",
                    "Unison controls the volume and brightness of everything connected to your Mac from one place: the built-in speakers and display, headphones, and external monitors. The volume and brightness keys move all devices together, and the menu bar panel adjusts each one individually.")

                section("Why it exists",
                    "macOS plays sound to one output device at a time, and combining devices by hand in Audio MIDI Setup disables the volume keys. Monitors connected over HDMI or DisplayPort expose no volume or brightness control to macOS at all. Unison fills these gaps: it plays sound through every ticked device at once, drives each speaker directly, and talks to monitors over DDC/CI, the protocol monitors use for their on-screen menu settings.")

                section("Playing through several devices",
                    "Unison appears in the sound output list as a device of its own. While Unison is selected, the sound your Mac plays is captured, using the System Audio Recording permission, and redistributed to every device ticked under Play through in Settings. With Stereo positions on, each speaker can be placed where it physically sits, from full left to full right, and plays the matching part of the stereo field. With it off, every device keeps its natural stereo.")

                section("Playing through one device",
                    "Pick any single device in the sound output list and sound plays only there, with nothing in the signal path. The volume keys and the menu panel follow it, the other devices dim, and the stereo options pause. Plug in headphones and macOS switches to them by itself; select Unison again and everything plays together.")

                section("Using a second display",
                    "External monitors appear automatically in both columns of the menu panel if they support DDC/CI (most do). Brightness works on nearly every monitor; volume only on monitors with speakers. If a monitor is missing, click Refresh Devices in the menu panel, and check it is connected directly rather than through a hub or KVM.")

                section("Keeping devices in balance",
                    "In Settings, each device has a max output slider. A device capped at 80% follows every volume or brightness change but always stays proportionally below the rest: at zero everything is silent or dark, at full level the capped device sits at 80%. Use it when one speaker is louder than the other, or when one display should stay dimmer, for example next to a dark code editor.")

                section("Keyboard",
                    "Volume and brightness keys move all devices by default; pick a single target device in Settings if you prefer. When one device is selected in the sound output list, the keys control that device alone. Unison needs Accessibility permission (System Settings, Privacy and Security, Accessibility) to receive the keys. Without it, the sliders still work but the keyboard does not.")

                section("Overlay",
                    "Key presses show a level overlay. Unison's own overlay displays the exact level; switching it off in Settings uses the standard macOS bezel instead, which on macOS Tahoe cannot show the real level.")

                section("Notes",
                    "Levels are remembered and restored on launch. Plug in headphones or a monitor and Unison picks them up automatically. Unison replaces tools like MonitorControl and Background Music for this workflow, and needs no audio driver.")
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
