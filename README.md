# Unison

Unison is a macOS menu bar app that plays your sound through every speaker you have at the same time, and controls the volume and brightness of all your devices together from the keyboard.

macOS normally plays sound to one output device at a time. Combining devices by hand in Audio MIDI Setup is clumsy and disables the volume keys. Monitors connected over HDMI or DisplayPort give macOS no volume or brightness control at all. Unison solves all of this in one small app, with no audio driver to install.

## What it does

1. Plays system audio through several output devices at once: built in speakers, monitor speakers, headphones, anything macOS sees as an output.
2. Lets you place each physical speaker where it sits in the room, from full left to full right, so stereo images correctly across devices that stand in different places.
3. Controls the volume of every speaker and the brightness of every display, together or individually, from the volume and brightness keys or from the menu bar panel.
4. Talks to external monitors over DDC/CI, the same protocol the monitor's own menu buttons use, so monitor volume and brightness work even where macOS offers nothing.
5. Shows an accurate volume and brightness overlay, since the standard macOS bezel cannot display the real level for external devices.

## Settings

The Settings window has two columns.

General covers launching Unison at login and hiding the menu bar icon. If you hide the icon, opening the app again from Spotlight or Finder brings the Settings window back.

Overlay switches between Unison's own level overlay and the standard macOS bezel, separately for volume and brightness keys.

Keyboard chooses what the volume and brightness keys control: all devices together, which keeps your balance, or one specific device. A step size slider sets how much one key press changes the level.

Speakers lists every audio output. Each device has a tick to include it in group control and a max output slider. A device capped at 80 percent follows every change but always stays proportionally below the rest, useful when one speaker is naturally louder than the others.

Stereo positions turns positional mixing on and off. When it is on, each speaker channel gets a slider from left to right matching where the speaker physically stands. When it is off, sound still plays through every ticked device with its natural stereo. The Play through list chooses which devices take part in playback at all, so Audio MIDI Setup is never needed.

Displays mirrors the speaker settings for brightness: a tick per display and a max output slider to keep one display dimmer than the other at every level.

## Installation

1. Clone this repository.
2. Run `./Scripts/run.sh`. It builds the app into `build/Unison.app` and opens it.
3. Grant the two permissions macOS asks for, described below.

That is the whole installation. Unison keeps everything in this folder plus one standard preferences file that macOS manages.

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

System audio is captured with a Core Audio process tap, the public API for this on macOS 14.4 and later, and mixed in real time onto an aggregate device containing all included outputs. Each speaker channel gets a left and right gain derived from its position, normalized so loud content never clips. Speaker volume uses CoreAudio where the hardware allows it. Monitor volume and brightness go over DDC/CI through the IOAVService API. The built in display uses the native brightness API. Media keys are captured with a CGEventTap.

## Requirements

Apple Silicon Mac running macOS 14.4 or later. The DDC/CI path uses a private Apple API, so the app is built for personal use and is not App Store distributable.

## License

MIT. See the LICENSE file.
