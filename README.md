# Display Assistant

A menu bar app that controls an external monitor's brightness and volume over DDC/CI,
for displays macOS can't adjust itself. Built for an LG UltraGear on Apple Silicon.

- Menu bar panel with Control Center style Display and Sound sliders per monitor
- Keyboard brightness, volume and mute keys, with fine steps (see [Keyboard](#keyboard))
- Control Center / menu bar controls: mute toggle, brightness up/down, volume up/down
- Siri, Shortcuts and Spotlight actions: set/get brightness and volume, mute/unmute/toggle
- `displayctl` command-line tool for scripts

Displays that don't answer DDC, Apple's own displays and the built-in display are never shown
or touched; their keys and controls keep working natively.

## Keyboard

Once Accessibility access is granted, the standard media keys control the monitor. On an Apple
keyboard these are the top-row keys (hold `fn` if you have them set to act as F1–F12).

| Key | Apple keyboard | Action |
| --- | --- | --- |
| Brightness down / up | `F1` / `F2` | Dims or brightens the display under the pointer by 1/16 (about 6%) |
| Mute | `F10` | Mutes or unmutes the display's speakers |
| Volume down / up | `F11` / `F12` | Changes the display's volume by 1/16 (about 6%) |
| Fine step | `⌥ Option` + `⇧ Shift` + any key above | Moves by 1/64 (about 1.5%) instead; four fine steps equal one normal step |

- Holding a key repeats the step. An indicator under the menu bar shows the new level.
- Brightness keys act on the external display the pointer is on. With the pointer on the built-in
  display, an Apple display or a display without DDC, the key is passed through to macOS.
- Volume and mute keys are only taken over while the Mac's sound output is a display
  (HDMI/DisplayPort/USB-C). With speakers, headphones or a Studio Display selected, they work as usual.
- `⌥ Option` alone with a brightness key is left to macOS (it opens Displays settings), which is why
  fine steps need both modifiers — the same shortcut macOS uses for its own displays.

In the panel, click the speaker icon at the left of the **Sound** slider to mute, and the gear
to open Displays settings.

## Install

Download the latest build from [Releases](https://github.com/tajshaik24/display-assistant/releases),
move it to `/Applications` and open it. Builds are signed but not notarized, so the first launch has to
be allowed under System Settings → Privacy & Security → **Open Anyway**.

## Build from source

Requires Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and macOS 26 or later.

    ./scripts/build.sh --install

Then:

1. Open the panel from the menu bar and press **Enable** to grant Accessibility access for the keyboard keys.
2. Add the controls: Control Center → Edit Controls → search for "Display".

The signing team is set in `project.yml`, and the matching app group in `Shared/Shared.swift`.

## Layout

| Path | Purpose |
| --- | --- |
| `DisplayKit/` | Swift package: DDC/CI over `IOAVService`, display discovery, `displayctl` |
| `App/` | The menu bar app |
| `Controls/` | Control Center extension (sandboxed; forwards commands to the app) |
| `Shared/` | Command and state definitions used by both |

## Notes

- DDC works over USB-C, Thunderbolt and DisplayPort. Some docks, adapters and DisplayLink
  devices don't pass it through. DDC/CI must be enabled in the monitor's on-screen menu.
- Control Center controls can only be buttons and toggles, so sliders live in the menu bar panel.
