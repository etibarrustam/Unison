# Unison

A macOS menu-bar app that controls the **volume** and **brightness** of all your
output devices at once — or each one individually — from the keyboard.

It exists because macOS disables the volume keys when a Multi-Output Device is
active (e.g. laptop speakers + monitor speakers together), and because external
monitor volume/brightness are not controllable from the keyboard out of the box.

Unison replaces the need for separate tools like Background Music and
MonitorControl.

## What it does

- Volume of **all speakers together** and **each speaker** individually.
- Brightness of **all displays together** and **each display** individually.
- Volume/brightness keys drive all devices by default (configurable).
- Generic across monitors via DDC/CI, only showing controls a monitor supports.

## How it works

- MacBook speaker volume via CoreAudio.
- External monitor volume (DDC VCP `0x62`) and brightness (DDC VCP `0x10`) via
  the `IOAVService` API.
- MacBook built-in brightness via the native display API.
- Media keys captured with a `CGEventTap` (needs Accessibility permission).

## Status

Early development. Local, self-signed build for personal use. Uses a private
Apple DDC API, so it is not App Store distributable.

See `docs/superpowers/specs/2026-07-12-unison-design.md` for the full design.

## Requirements

- Apple Silicon Mac, macOS 14+.
- Accessibility permission (for keyboard control).
