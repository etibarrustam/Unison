<p align="center"><img src="Assets/logo.svg" width="140" alt="Unison logo"></p>

# Unison

Unison is a macOS menu bar app that plays your sound through every speaker you have at the same time and controls the volume and brightness of all your devices from the keyboard.

macOS plays sound to one output device at a time. Combining devices in Audio MIDI Setup is clumsy and kills the volume keys. Monitors connected over HDMI or DisplayPort give macOS no volume or brightness control at all. Unison fixes this in one app, with no audio driver to install.

## What it does

1. Appears in the sound output list as a device called Unison. Pick it and every speaker plays together. Pick a single device, or plug in headphones, and sound plays only there until you switch back.
2. Offers three sound modes. Stereo keeps every speaker's natural left and right. Mono plays the complete mix on every speaker, best when they sit in different rooms. Spatial lets you drag each speaker to where it stands in your room, including behind you, and renders the matching part of the stereo field to it.
3. Moves the volume of every speaker and the brightness of every display together, or one device at a time, from the keyboard or the menu bar panel.
4. Controls monitor volume and brightness over DDC, the same protocol the monitor's own buttons use, so monitors work even where macOS offers nothing.
5. Shows an accurate level overlay, because the macOS bezel cannot display the real level of external devices.

## Install

```
brew install etibarrustam/tap/unison
```

Open the app once, grant the two permissions below, and turn on Launch at login in Settings. The full name matters: plain unison is a different tool in Homebrew.

The app builds on your machine during install, which takes under a minute and is why it needs no Apple notarization. To build from source instead, clone this repository and run `Scripts/run.sh`.

## Permissions

Accessibility lets Unison receive the volume and brightness keys. Without it the sliders work but the keyboard does not.

System Audio Recording lets Unison read the sound your Mac plays so it can redistribute it to your speakers. This is not the microphone permission. Unison never opens the microphone and no recording indicator stays in your menu bar.

## Settings

Sound mode picks Stereo, Mono, or Spatial. In Spatial, Arrange Speakers opens a room view: drag each speaker to where it stands, anywhere around you, and nearer speakers are delayed a fraction so everything arrives at your seat together. Speakers behind you work. Height does not, because stereo carries no height information. Reset returns every speaker to its natural stereo side.

Each speaker has one tick and one balance slider. Unticked speakers stay silent and leave the menu panel. The balance slider keeps a speaker permanently below the rest, useful when one is naturally louder. A monitor appears as a single speaker even though macOS sees its audio and its volume control separately. Displays work the same way for brightness.

Keyboard picks what the volume and brightness keys control, and a step size sets how much one press changes the level. When a single device is selected in the sound output list, the keys control that device alone, the other speakers dim, and everything returns when Unison is selected again.

General and Overlay cover launch at login, hiding the menu bar icon, and switching between Unison's accurate level overlay and the standard macOS bezel.

## How it works

Unison publishes an aggregate device named Unison in the sound output list. Sound sent to it is captured with a Core Audio process tap, the public API for this since macOS 14.4, and mixed in real time onto a private aggregate containing every ticked output. Selecting any other output routes around the tap, so a single device plays natively with nothing in the signal path. In Spatial mode the system spatial mixer renders the mix with every speaker declared at its real position. Monitor control goes over DDC through the IOAVService API. The built in display uses the native brightness API. Media keys are captured with a CGEventTap.

## Uninstall

Quit the app, then:

```
brew uninstall etibarrustam/tap/unison
tccutil reset All com.unison.app
defaults delete com.unison.app
```

Remove Unison from Login Items in System Settings if you enabled launch at login. Nothing else is left behind.

## Requirements

Apple Silicon Mac on macOS 14.4 or later. The DDC path uses a private Apple API, so the app is built for personal use and is not App Store distributable.

## License

MIT. See the LICENSE file.
