# Prototypes

Small standalone experiments that de-risk features before they are built
into the app. Each one compiles and runs on its own; none of them are part
of the app target.

## SpatialMixerProbe

Question: can Unison delegate positional audio math to Apple's built-in
`AUSpatialMixer`, using speaker positions the user chooses freely, instead
of implementing vector-base amplitude panning by hand?

The probe renders a mono sine source offline through
`kAudioUnitSubType_SpatialMixer` with `VectorBasedPanning`, sweeps the
source azimuth, and measures per-channel RMS under three output layouts:
a standard quadraphonic tag, custom coordinates arranged like a quad, and
custom lopsided coordinates.

Result, verified on macOS 15 (2026-07-13): custom coordinates are fully
honored. The quad-shaped custom layout behaves identically to the real
quad tag, and the lopsided layout distributes energy according to the
declared speaker angles, including speakers behind the listener.
Directions with no nearby speaker are spread across the array instead of
dropping out.

Consequence for the app: the planned speaker arrangement feature can feed
the tap's left and right channels into an `AUSpatialMixer` as two point
sources and declare one output channel per physical speaker at its real
position. Apple maintains the panning math; Unison keeps only geometry,
delays, and UI.

Run it:

```
swiftc -O Prototypes/SpatialMixerProbe.swift -o /tmp/spatialprobe \
  -framework AudioToolbox -framework CoreAudio && /tmp/spatialprobe
```
