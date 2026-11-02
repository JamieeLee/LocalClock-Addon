# LocalClock for Azeroth Survivors

**Version:** 1.1.3-RC
**Status:** Release candidate — optional test update.
**Client:** Legacy Azeroth Survivors (Interface 11200 / Lua 5.0-style API)

LocalClock adds a movable secondary clock, a classic minimap launcher, and stopwatch/alarm tools. On Azeroth Survivors 0.136.0 or newer, it reads the device-local hour/minute snapshot to determine the device UTC offset, then calculates the displayed time from an explicit UTC source. It can also independently control the native local clock below the minimap.

## Minimap launcher

The LocalClock bubble follows the minimap's position, scale, and visibility. It is a single addon-owned frame and saves its own position around the minimap.

- **Left-click:** Open the LocalClock tools panel. Its position is saved independently when moved and restored on later runs.
- **Settings menu:** Separate Clock, Stopwatch and Alarm entries open the tools panel in the corresponding mode.
- **Right-click:** Open LocalClock settings.
- **Drag:** Move the bubble around the minimap, following the classic Azerloot-style edge path. Shift is not required.

The launcher remains independently usable without Move UI. The secondary clock and alarm warning retain their existing Move UI handoff.

## Game Local Time and clock visibility

On Azeroth Survivors 0.136.0 or newer, a fresh LocalClock installation defaults to **Game Local Time**. It uses the API's numeric local hour/minute snapshot to derive the device offset from UTC, then calculates the displayed time through LocalClock's own UTC conversion engine. The game's `is24Hour` field controls the default 12/24-hour presentation; the API's preformatted text is not displayed directly. The native minimap clock can be hidden separately through `AZS_SetHudShown("localClock", false)`.

The right-click menu has two independent checkboxes:

- **Show Game Clock:** Controls only the game's native local clock. It does not hide the minimap or the run timer.
- **Show LocalClock:** Controls the larger secondary LocalClock display.

The two options are independent. Hiding the minimap hides both clock displays and the minimap bubble; their saved visibility preferences are retained and restored when the minimap is shown again.

Existing saved time-zone choices are preserved during the update. If a previous installation already saved Eastern, CET, a custom offset, or another zone, LocalClock keeps it. Choose **Game Local Time** in the Time zone submenu to use the device-local clock instead.

The native Game Clock checkbox uses the `localClock` HUD setter when available, with the documented `hudLocalClock` CVar as a fallback. Older game builds without either control retain the legacy time-zone fallback and do not receive unknown API calls.

## Time-zone settings

Right-click the LocalClock bubble (or the secondary clock) and choose **Time zone settings...** to open the large clock and UTC-offset panel.

Supported named zones include Eastern, Central, Mountain, Pacific, Alaska, Hawaii, Arizona, UTC, CET/CEST, and EET/EEST. US and EU daylight-saving transitions are calculated for the corresponding named zones. A custom UTC offset is also available from the slider.

When Game Local Time is selected, the default format follows the game language using the API's `is24Hour` flag. The 12-hour and 24-hour controls allow an explicit display override. All clock arithmetic starts from UTC; Game Local Time derives the device offset from the numeric local snapshot, while named zones continue using LocalClock's existing UTC/DST conversion engine.

## Stopwatch and alarms

Open the tools panel with the minimap bubble's left-click or `/clock tools`.

- Clock, Stopwatch, and Alarm are selectable display modes for the secondary display.
- Stopwatch supports start, pause, and reset.
- Alarms accept an `HH:MM` target in the currently selected LocalClock time zone, show a live countdown, play a sound, and display a center-screen warning when they fire.
- An active stopwatch resumes paused after restarting the game. Scheduled alarms persist across sessions.

## Commands

Commands can be entered using `/clock` or `/localclock`.

| Command | Description |
|---|---|
| `/clock` | Show help |
| `/clock menu` | Open the settings menu |
| `/clock options` | Open time-zone settings |
| `/clock tools` | Open Stopwatch & Alarm tools |
| `/clock show` / `/clock hide` | Show or hide the secondary LocalClock display |
| `/clock toggle` | Toggle the secondary LocalClock display |
| `/clock 12h` / `/clock 24h` | Set the secondary display format |
| `/clock zone` | Show the selected time zone |
| `/clock zone local` | Use Game Local Time |
| `/clock zone eastern` (or another supported zone) | Select a named time zone |
| `/clock offset -5` | Set a custom UTC offset |
| `/clock reset` | Reset the bubble and secondary clock positions |
| `/clock debug` | Print clock/API diagnostic information |

Stopwatch commands: `/clock stopwatch start`, `/clock stopwatch pause`, `/clock stopwatch reset`.  
Alarm commands: `/clock alarm set HH:MM`, `/clock alarm cancel`.

## Installation

1. Close Azeroth Survivors.
2. Extract the `LocalClock` folder from the ZIP.
3. Place that folder in the game's `Interface/AddOns/` directory.
4. Start the game and enable LocalClock in the AddOns list if needed.

When upgrading, replace the existing `LocalClock` folder. Saved settings are stored separately by the game in `LocalClockDB`.

## Compatibility

This addon targets the legacy Azeroth Survivors client and its Lua 5.0-style API. Game Local Time and the native Game Clock toggle require the 0.136.0 API additions. On earlier builds, LocalClock falls back to the pre-existing UTC-based time-zone implementation. It is not intended for modern World of Warcraft clients without modification.
