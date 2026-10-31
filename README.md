# LocalClock for Azeroth Survivors

**Client:** Legacy Azeroth Survivors (Interface 11200 / Lua 5.0-style API)

LocalClock adds a small, movable on-screen clock that displays time converted from the game's UTC clock into a selected time zone. The colon blinks every half-second.

## Installation

1. Close Azeroth Survivors.
2. Extract the `LocalClock` folder from the ZIP.
3. Place that folder in the game's `Interface/AddOns/` directory.
4. Start the game. The clock should appear near the center of the screen.
5. Drag the clock with the left mouse button to move it. Its position is saved.

If upgrading from an older version, replace the old `LocalClock` folder with the new one. The addon's saved settings are kept separately by the game.

## Commands

Commands can be entered using either `/clock` or `/localclock`.

| Command | Description |
|---|---|
| `/clock` | Show the help text |
| `/clock show` | Show the clock |
| `/clock hide` | Hide the clock |
| `/clock toggle` | Toggle visibility |
| `/clock 12h` | Use 12-hour time with AM/PM |
| `/clock 24h` | Use 24-hour time |
| `/clock zone` | Show the currently selected time zone |
| `/clock zone eastern` | Set Eastern Time |
| `/clock zone central` | Set Central Time |
| `/clock zone mountain` | Set Mountain Time |
| `/clock zone pacific` | Set Pacific Time |
| `/clock zone alaska` | Set Alaska Time |
| `/clock zone arizona` | Set Arizona time (no daylight saving adjustment) |
| `/clock zone hawaii` | Set Hawaii time (no daylight saving adjustment) |
| `/clock zone utc` | Display UTC |
| `/clock reset` | Reset the clock's position |
| `/clock debug` | Print the raw clock time, selected zone, and applied UTC offset |

## Time-zone behavior

The client exposes UTC through its `date()` function, but does not expose Lua's standard `os` library or a usable `timezone` CVar. LocalClock therefore applies a UTC offset itself.

- **Eastern, Central, Mountain, Pacific, and Alaska:** the addon calculates US daylight saving time transitions automatically.
- **Arizona and Hawaii:** no daylight saving adjustment is applied.
- **UTC:** no offset is applied.

The default time zone on a fresh install is **Eastern**. The default display format is **12-hour time**.

This is a client-side conversion, not a read of the Windows time-zone setting. Select the zone that matches your location with `/clock zone ...`. Daylight-saving rules are implemented for the listed US zones; the addon does not automatically discover your Windows time zone.

## Saved settings

The game stores LocalClock settings in the `LocalClockDB` SavedVariables table, including the selected zone, 12/24-hour preference, and clock position.

## Troubleshooting

- If the clock is hidden, use `/clock show`.
- If the time is incorrect, use `/clock zone eastern` (or the appropriate zone) and then `/clock debug`.
- If the clock is off-screen, use `/clock reset`.
- If the addon does not load, verify the folder layout is `Interface/AddOns/LocalClock/LocalClock.toc` and `LocalClock.lua`.

## Compatibility note

This addon targets the original legacy Azeroth Survivors client and its Lua 5.0-style API. It is not intended for modern World of Warcraft clients without modification.
