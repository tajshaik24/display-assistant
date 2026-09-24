# Display Assistant

A menu bar app that controls an external monitor's brightness and volume over DDC/CI,
for displays macOS can't adjust itself, and keeps its brightness in sync with your Apple displays.
Built for an LG UltraGear on Apple Silicon.

- Menu bar panel with Control Center style Display and Sound sliders per monitor
- **Sync Brightness**: all displays move together, so the monitor follows your MacBook's
  auto-brightness and brightness keys (see [Brightness sync](#brightness-sync))
- Keyboard brightness, volume and mute keys, with fine steps (see [Keyboard](#keyboard))
- Control Center controls: open the sliders, one-tap brightness and volume levels, mute toggle
  (see [Control Center](#control-center))
- **HDR switch** per display in the panel, and a Shortcuts action to turn HDR on or off
  (for example from an automation when a movie app opens)
- Siri, Shortcuts and Spotlight actions: set/get brightness and volume, mute/unmute/toggle, HDR on/off/toggle
- `displayctl` command-line tool for scripts (brightness, volume, mute, HDR)

Displays macOS controls itself (the built-in display, Studio Display, Pro Display XDR, LG UltraFine)
appear in the panel with a brightness slider, but their keys, volume and system controls stay native.
Displays that can be controlled neither way are never shown or touched.

With HDR on, macOS takes over a DDC monitor's brightness. The app then sets brightness through macOS
(the panel slider and brightness keys keep working) while volume and mute still go over DDC.

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

## Control Center

macOS only lets apps add buttons and toggles to Control Center — sliders are reserved for Apple's own
modules. Add these from Control Center → Edit Controls → search "Display":

| Control | What it does |
| --- | --- |
| **Display Sliders** | Opens the brightness and volume sliders as a panel where Control Center appears. Click anywhere else or press `esc` to close it. |
| **Display Brightness Level** | Sets a brightness you choose when adding it (for example 30% for evenings, 80% for daytime). Add as many as you like. |
| **Display Volume Level** | The same for the display's speaker volume. |
| **Mute Display** | Toggle that mutes or unmutes the display's speakers. |

## Brightness sync

With two or more displays, the panel shows a **Sync Brightness** switch. While it is on, changing
any display's brightness — from the panel, the keyboard, Control Center, Siri, or macOS itself
(auto-brightness, the native keys) — moves the others with it.

- Displays keep the relationship they had when sync was switched on, because 50% on one panel is
  rarely as bright as 50% on another: a monitor set a little brighter than the MacBook stays a
  little brighter. The difference narrows toward the ends, so all displays reach 0% and 100% together.
- To set a new relationship, switch sync off, set each display, and switch it on again. If the Apple
  display is at 0% or 100% when you switch sync on, the displays simply match.
- Apple displays are read through the private DisplayServices framework and checked every 1.5 s;
  the monitor is only sent a DDC command when its own 0–100 value actually changes.

## Install

Download the latest build from [Releases](https://github.com/tajshaik24/display-assistant/releases),
unzip it and move **Display Assistant.app** to `/Applications`.

Builds are signed but not notarized, so macOS blocks the first launch of a downloaded copy. Clear that
once, either way:

- **Terminal (quickest):** after moving the app to `/Applications`, run

  ```bash
  xattr -dr com.apple.quarantine "/Applications/Display Assistant.app"
  ```

  This removes the quarantine flag your browser put on the download; the app then opens normally.
- **No Terminal:** open the app once, let macOS block it, then choose System Settings →
  Privacy & Security → **Open Anyway**.

Then, on each Mac (permissions don't carry over between machines):

1. Open the panel from the menu bar and press **Enable** to grant Accessibility access for the keyboard keys.
2. Optional: Control Center → Edit Controls → search for "Display".

Launch at Login switches itself on. Building from source (below) avoids the Gatekeeper step entirely.

## Build from source

Requires Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and macOS 26 or later.

```bash
# Build and install to /Applications, replacing and relaunching any running copy
./build-app.sh --install

# Release build only (output in build/Build/Products/Release/)
./build-app.sh

# Debug build
./build-app.sh debug
```

By default the script signs with your **Apple Development** identity (auto-detected), which keeps the
Accessibility permission stable across rebuilds. Pass `--identity "-"` for ad-hoc signing or
`--identity "NAME"` to choose a specific certificate. The signing team is set in `project.yml`, and the
matching app group in `Shared/Shared.swift`.

`./build-app.sh release --notarize` signs with a **Developer ID Application** certificate, submits the
app to Apple's notary service and staples the ticket, producing `build/DisplayAssistant.zip` for a
release that opens without a Gatekeeper warning. See the header of `build-app.sh` for the one-time
`notarytool` credentials setup.

After the first install:

1. Open the panel from the menu bar and press **Enable** to grant Accessibility access for the keyboard keys.
2. Add the controls: Control Center → Edit Controls → search for "Display".

## Layout

| Path | Purpose |
| --- | --- |
| `DisplayKit/` | Swift package: DDC/CI over `IOAVService`, native brightness, sync arithmetic, display discovery, `displayctl` |
| `App/` | The menu bar app |
| `Controls/` | Control Center extension (sandboxed; forwards commands to the app) |
| `Shared/` | Command and state definitions used by both |

## Notes

- DDC works over USB-C, Thunderbolt and DisplayPort. Some docks, adapters and DisplayLink
  devices don't pass it through. DDC/CI must be enabled in the monitor's on-screen menu.
