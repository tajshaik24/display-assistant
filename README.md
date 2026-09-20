# Display Assistant

A menu bar app that controls an external monitor's brightness and volume over DDC/CI,
for displays macOS can't adjust itself. Built for an LG UltraGear on Apple Silicon.

- Menu bar panel with sliders per display (click the speaker icon to mute)
- Keyboard brightness keys control the display under the pointer; volume and mute keys
  control the display while sound is routed to it. Hold ⌥⇧ for fine steps.
- Control Center / menu bar controls: mute toggle, brightness up/down, volume up/down
- Siri, Shortcuts and Spotlight actions: set/get brightness and volume, mute/unmute/toggle
- `displayctl` command-line tool for scripts

Displays that don't answer DDC, Apple's own displays and the built-in display are never shown
or touched; their keys and controls keep working natively.

## Build and install

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
