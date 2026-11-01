## 1.3.3
- Fixed the LocalClock context-menu visibility item so it toggles the clock without closing the menu.
- The menu item remains open and updates its label/checkmark immediately between "Hide LocalClock" and "Show LocalClock".
- Other menu actions retain their existing close-after-selection behavior.

## 1.3.2
- The alarm now always uses a dedicated, named LocalClockAlarmWarning frame so the exact visible banner can be managed by Move UI.
- The alarm frame is created at login, allowing Move UI to apply saved position, scale, and hide settings before the first alarm.
- Keeps the center-screen warning, sound, chat log, alarm timing, and stopwatch behavior.
- The native Raid Warning mover remains dedicated to the game's own RaidWarningFrame messages.

# Changelog

## 1.3.1
- Alarm now displays a prominent raid-warning-style center-screen alert when it fires.
- Uses the game's local RaidWarningFrame presentation when available; this is a local UI display and does not send a raid message.
- Falls back to UIErrorsFrame, then to an addon-owned large center-screen banner if the stock warning frame is unavailable.
- Retains the existing alarm sound, chat log entry, one-shot behavior, and dismiss controls.


## 1.3.0
- Added Clock, Stopwatch, and Alarm display modes to the independently movable secondary clock.
- Added a stopwatch with start, pause, and reset controls.
- Added a scheduled alarm with an HH:MM target in LocalClock's configured time zone and a live countdown.
- Alarm calculations use LocalClock's UTC offset/DST logic and never query the native minimap clock.
- Active scheduled alarms recalculate when the configured zone or custom offset changes.
- Corrected US DST transition UTC hours per supported US zone so alarms follow each zone's actual transition instant.
- Timing and alarm checks run from the persistent UIParent watcher, so hiding the secondary clock does not pause them.
- Preserved the dual-clock surround, visibility logic, and Move UI integration from 1.2.1.
