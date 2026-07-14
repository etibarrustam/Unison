<p align="center"><img src="Assets/logo.svg" width="140" alt="Unison logo"></p>

# Unison

Unison is a macOS menu bar app that plays your sound through every speaker you have at the same time, and controls the volume and brightness of all your devices together from the keyboard.

macOS normally plays sound to one output device at a time. Combining devices by hand in Audio MIDI Setup is clumsy and disables the volume keys. Monitors connected over HDMI or DisplayPort give macOS no volume or brightness control at all. Unison solves all of this in one small app, with no audio driver to install.

## What it does

1. Plays system audio through several output devices at once: built in speakers, monitor speakers, headphones, anything macOS sees as an output.
2. Appears in the sound output list as a device called Unison. Pick Unison and everything plays together; pick any single device, or plug in headphones, and sound plays only there until you switch back.
3. Lets you place each physical speaker where it sits in the room, from full left to full right, so stereo images correctly across devices that stand in different places.
4. Controls the volume of every speaker and the brightness of every display, together or individually, from the volume and brightness keys or from the menu bar panel.
5. Talks to external monitors over DDC/CI, the same protocol the monitor's own menu buttons use, so monitor volume and brightness work even where macOS offers nothing.
6. Shows an accurate volume and brightness overlay, since the standard macOS bezel cannot display the real level for external devices.

## Settings

The Settings window has two columns.

General covers launching Unison at login and hiding the menu bar icon. If you hide the icon, opening the app again from Spotlight or Finder brings the Settings window back.

Overlay switches between Unison's own level overlay and the standard macOS bezel, separately for volume and brightness keys.

Keyboard chooses what the volume and brightness keys control: all devices together, which keeps your balance, or one specific device. When a single device is selected in the sound output list, the keys control that device alone. A step size slider sets how much one key press changes the level.

Speakers lists every audio output. Each device has a tick to include it in group control and a max output slider. A device capped at 80 percent follows every change but always stays proportionally below the rest, useful when one speaker is naturally louder than the others.

Sound mode chooses how the mix is built. Stereo plays every ticked device with its natural left and right. Spatial gives each speaker channel a slider from left to right matching where the speaker physically stands, and renders the mix through the macOS spatial mixer so the stereo field images correctly across the room. The Reset button returns every speaker to its natural stereo side. The Play through list chooses which devices take part in playback at all, so Audio MIDI Setup is never needed. While a single device is selected in the sound output list, the sound mode options are disabled and the other speakers dim; everything comes back when Unison is selected again.

Displays mirrors the speaker settings for brightness: a tick per display and a max output slider to keep one display dimmer than the other at every level.

## Installation

First, install it with Homebrew. This builds the app and puts Unison.app into your Applications folder by itself:

```
brew install etibarrustam/tap/unison
```

Then open the app once, from Launchpad, Spotlight, or the Applications folder, or from the terminal:

```
open /Applications/Unison.app
```

Grant the two permissions macOS asks for, described below, and you are done. Turn on Launch at login in the app settings and you never open it manually again. The full name `etibarrustam/tap/unison` matters, because plain `unison` is a different tool in Homebrew.

The app builds on your machine during the install, which takes under a minute and is what lets it run without Apple notarization.

To install from source instead, clone this repository and run `./Scripts/run.sh`. It builds the app into `build/Unison.app` and opens it.

## Permissions

Unison asks for exactly two permissions.

Accessibility lets Unison receive the volume and brightness keys. Without it the sliders still work but the keyboard does not.

System Audio Recording lets Unison read the sound your Mac plays so it can redistribute it to all your speakers. This is not the microphone permission. Unison never opens the microphone and no recording indicator stays in your menu bar.

## Uninstalling

Quit the app, then run:

```
tccutil reset All com.unison.app
defaults delete com.unison.app
```

Delete the repository folder and remove Unison from Login Items in System Settings if you enabled launch at login. Nothing else is left behind.

## How it works

Unison publishes an aggregate device named Unison in the sound output list. Sound sent to it is captured with a Core Audio process tap, the public API for this on macOS 14.4 and later, and mixed in real time onto a private aggregate containing all included outputs. Selecting any other output routes around the tap, so a single device plays natively with nothing in the signal path. In Stereo mode each speaker channel gets a left and right gain derived from its position, normalized so loud content never clips. In Spatial mode the mix is rendered by the system spatial mixer instead, with every speaker declared at its position and vector based panning projecting the stereo field onto the array. Speaker volume uses CoreAudio where the hardware allows it. Monitor volume and brightness go over DDC/CI through the IOAVService API. The built in display uses the native brightness API. Media keys are captured with a CGEventTap.

## Requirements

Apple Silicon Mac running macOS 14.4 or later. The DDC/CI path uses a private Apple API, so the app is built for personal use and is not App Store distributable.

## License

MIT. See the LICENSE file.
