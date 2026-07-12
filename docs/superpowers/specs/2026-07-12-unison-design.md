# Unison — Design Spec

**Status:** Draft for review
**Date:** 2026-07-12
**Platform:** macOS 14+ (developed on macOS Tahoe / Apple Silicon, M1 Pro)

## 1. Problem

macOS lets you play sound to several outputs at once through a **Multi-Output
Device** (e.g. MacBook speakers + monitor speakers together). But when a
Multi-Output (or Aggregate) device is active, macOS **disables the volume keys
and greys out the volume slider**. There is no built-in way to raise or lower
all outputs together from the keyboard, and monitor speakers connected over
HDMI cannot be volume-controlled by macOS at all.

Separately, controlling an external monitor's **brightness** requires a second
tool (currently MonitorControl).

The user wants **one app** that:

- Controls the volume of **all output devices together** and **each device
  individually**, driven by the keyboard.
- Controls the **brightness** of **all displays together** and each display
  individually.
- Replaces both Background Music and MonitorControl so they can be uninstalled.

## 2. Feasibility (verified on 2026-07-12)

Tested on the user's Mac (M1 Pro, LG HDR 4K over HDMI):

| Capability | Mechanism | Result |
| --- | --- | --- |
| MacBook Pro Speakers volume | CoreAudio software volume (`kAudioDevicePropertyVolumeScalar`) | Settable |
| LG monitor volume | DDC/CI VCP `0x62` via `IOAVService` | **Write works** (set 12, read back 12) |
| LG monitor brightness | DDC/CI VCP `0x10` | Works (reads 87) |
| MacBook built-in display brightness | Native display API | Standard, supported |

**Key finding — DDC reads are unreliable over HDMI.** Volume reads returned
`4`, `0`, `12`, `0` inconsistently, while **writes were reliable**. Therefore
the app must own the current level as its source of truth and only ever *write*
to the monitor. It must never depend on reading the value back.

Because we command the monitor's **real** volume over DDC, no virtual audio
driver (Background Music) is needed.

## 3. Goals

- Menu-bar app (no Dock icon) controlling volume and brightness of all
  detected outputs/displays, together or individually.
- Keyboard volume and brightness keys control all devices by default;
  configurable target.
- Generic across monitors (Dell, Samsung, LG, etc.) via standard DDC/CI, with
  per-device capability detection and graceful degradation.
- Persist levels and re-apply on launch.

## 4. Non-Goals

- Does **not** replace the Multi-Output Device. macOS still handles playing to
  multiple speakers at once; Unison only controls the individual volumes.
- No per-app volume mixing (that is what Background Music did; not needed here).
- No monitor input-switching, contrast, or color controls in the first version.
- Not distributed via the App Store (uses a private DDC API), and not signed
  for other machines yet — local self-signed build to start.

## 5. Compatibility expectations

- **Brightness (VCP `0x10`)** is a near-universal DDC standard — expected to
  work on almost any DDC-capable monitor.
- **Volume (VCP `0x62`)** is firmware-dependent and only applies to monitors
  with built-in speakers. Many Dell models support it; Samsung is mixed; some
  monitors expose no volume over DDC at all.
- DDC is cleaner over DisplayPort/USB-C than HDMI and may fail entirely through
  some KVMs, cheap hubs, or DisplayLink docks.

The app therefore **detects capabilities per monitor** and only shows the
controls a monitor actually supports. A manual override lets the user force
"control volume via DDC" when auto-detection is uncertain over a flaky link.

## 6. Architecture

Four small, independent modules behind clear interfaces, plus UI and app state.

```
        +------------------+       +-------------------------+
        |  Keyboard tap    |       |   Menu-bar popover UI   |
        |  (CGEventTap)    |       |   (SwiftUI)             |
        +---------+--------+       +------------+------------+
                  |                             |
                  v                             v
             +----+-----------------------------+----+
             |            Controller / AppState       |
             |  source of truth: level per device     |
             |  applies changes, persists, restores   |
             +--+-------------+-------------+----------+
                |             |             |
                v             v             v
        +-------+----+  +-----+------+  +---+----------------+
        | AudioCtl   |  |  DDCCtl    |  | BuiltinDisplayCtl  |
        | CoreAudio  |  | IOAVService|  | native brightness  |
        | volume     |  | vol 0x62   |  | for built-in panel |
        | + mute     |  | bright 0x10|  |                    |
        +------------+  +------------+  +--------------------+
```

### 6.1 Modules

- **AudioController** — enumerates CoreAudio output devices, reads/writes
  software volume and mute, and posts change notifications. Owns the mapping
  from a display's audio device to its DDC counterpart (matched by name/EDID)
  so the UI presents one logical device.
- **DDCController** — talks to external displays over DDC/CI using the private
  `IOAVService` API (the approach used by MonitorControl and m1ddc). Provides
  `setBrightness`, `setVolume`, and a capability probe. **Write-only in normal
  operation**; probing tolerates flaky reads with retries.
- **BuiltinDisplayController** — brightness of the MacBook's built-in panel via
  the native display-services API.
- **KeyboardTap** — a `CGEventTap` that intercepts the volume up/down/mute and
  brightness up/down media keys, consumes them, and forwards deltas to the
  Controller. Requires Accessibility permission.
- **Controller / AppState** — the single source of truth. Holds the current
  level (0–100) for every device and the two "All" groups, applies changes to
  the right backend, persists to `UserDefaults`, and re-applies on launch.

### 6.2 Device model

Two independent groups, each with an "All" entry plus per-device entries:

- **Speakers:** `All` · MacBook Pro Speakers (CoreAudio) · each external
  display with DDC volume support (DDC `0x62`).
- **Displays:** `All` · MacBook built-in (native) · each external display with
  DDC brightness support (DDC `0x10`).

Each device entry records its **backend** (CoreAudio / DDC / native) and its
**capabilities** (has volume? has brightness?), decided by detection at
connect time.

## 7. Behaviour

### 7.1 Sliders (popover)

- Two columns: **Brightness on the left, Sound on the right**.
- Each column: an **"All" slider at the top**, then individual device sliders.
- Dragging an **"All" slider sets every device in that group to the same
  absolute level** (simple, predictable mental model).
- Dragging an individual slider sets only that device.

### 7.2 Keyboard

- Volume up/down/mute keys and brightness up/down keys are captured and applied
  as a **relative step** (default: all devices in the group), which preserves
  the relative balance between devices.
- Default target is **All**; a Settings option changes the target to a specific
  device.
- Default step size is configurable (e.g. 1/16 like macOS, or a fixed percent).
- An on-screen **HUD overlay** shows the level on each key press, because macOS
  will not draw its own HUD for DDC/CoreAudio changes we make.

### 7.3 Mute

- Volume mute key toggles mute for the target group.
- CoreAudio devices use the native mute property.
- DDC displays mute by writing volume `0` and restoring the previous level on
  un-mute (the dedicated DDC mute VCP `0x8D` is unreliable across models).

### 7.4 State and persistence

- The app's stored level is authoritative. On launch and on device
  connect, it **writes** its stored levels to each device so hardware matches
  app state. It may do a single best-effort read for initial sync, but never
  relies on reads.

## 8. Settings

- Keyboard target: All (default) or a specific device, per group.
- Step size.
- Launch at login (`SMAppService`).
- Per-device show/hide in the popover.
- Manual "control volume via DDC" override per external display.
- "All" slider behaviour is fixed to absolute-set-all in v1 (documented here in
  case we revisit).

## 9. Permissions

- **Accessibility** — required for the `CGEventTap` that captures media keys.
  The app must detect when it is not granted and guide the user to System
  Settings. Without it, sliders still work but the keyboard does not.
- DDC via `IOAVService` needs no special entitlement.
- CoreAudio needs no permission.

## 10. Migration (after Unison is validated)

1. Confirm Unison controls all devices from keyboard and sliders.
2. Uninstall **MonitorControl**.
3. Uninstall **Background Music** (its own uninstaller). The audio path does not
   need it — the Multi-Output Device stays as the default output.

## 11. Tech stack

- **Swift + SwiftUI**, `MenuBarExtra` with window style for the two-column
  popover. `LSUIElement` so there is no Dock icon.
- **CoreAudio / AudioToolbox** for speaker volume and device notifications.
- **IOKit `IOAVService`** for DDC. A small native DDC module is embedded
  (referencing the MIT-licensed m1ddc for the framing); m1ddc itself is used
  only as a validation tool during development, not shipped.
- **CGEventTap** for media-key capture.
- **SMAppService** for launch-at-login.
- Built and run locally from Xcode (self-signed). Distribution/signing for
  other machines and pushing to git are deferred.

## 12. Risks and open questions

- **Sub-device volume inside a Multi-Output Device** — setting the MacBook
  Speakers' CoreAudio volume while it is a member of the Multi-Output must
  actually change its output. Its volume is settable; to verify early in
  implementation.
- **DDC read flakiness over HDMI** — mitigated by the write-only/own-the-state
  design; capability probing must retry and tolerate garbage reads.
- **Private API** — `IOAVService` is unsupported by Apple but widely used
  (MonitorControl). Acceptable for a local tool; blocks App Store distribution.
- **Monitor volume variance** — Samsung/others may not support DDC volume;
  handled by capability detection and graceful degradation.

## 13. Milestones

1. **DDC + audio spikes** — prove `setVolume`/`setBrightness` over DDC from
   native Swift (not shelling to m1ddc) and CoreAudio volume set, including the
   sub-device-in-Multi-Output check.
2. **Controller + state** — device model, persistence, apply/restore.
3. **Popover UI** — two-column layout with All + per-device sliders.
4. **Keyboard tap + HUD** — media-key capture, Accessibility flow, HUD overlay.
5. **Capability detection** — per-monitor probe and graceful degradation.
6. **Settings + launch-at-login.**
7. **Validate, then migrate** (uninstall MonitorControl and Background Music).
