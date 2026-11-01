## 1.3.2 — current menu and minimap-button fixes
- Test iteration: removed the runtime feature-detection gate that greyed out Show Game Clock; the menu now always lets the player invoke the guarded `localClock` API/CVar path.
- Fixed native clock state normalization so a real `false` from `AZS_IsHudShown("localClock")` or `hudLocalClock` is preserved rather than discarded by Lua's `and/or` idiom.
- Extended `/clock debug` with the types/results of `AZS_GetLocalTime`, `AZS_SetHudShown`, `AZS_IsHudShown`, `AZS_IsHudShown("localClock")` and the `hudLocalClock` CVar.
- Test iteration: restored the addon-managed native-clock surround and automatic width sizing from the prior build; Test 15's removal of that surround was reverted after in-game review.
- Test iteration: decoupled native Game Clock visibility detection from `AZS_GetLocalTime()` and the optional `AZS_IsHudShown()` query wrapper. The menu is enabled when `AZS_SetHudShown()` exists, with `hudLocalClock` CVar read/write fallback for builds exposing the saved preference through CVar.
- Test iteration: removed the leading zero from the hour in 12-hour clock display (for example, 6:53 PM); 24-hour mode remains zero-padded (06:53), and noon/midnight remain 12:00 AM/PM.
- Test iteration: Game Local Time now normalizes 12-hour numeric API values using the AM/PM suffix when 24-hour display is selected, including midnight/noon conversion to 00/12.
- Added a direct Clock... action to the right-click menu, parallel to Stopwatch... and Alarm...; it opens the tools panel in Clock mode. The Clock tab in the tools panel remains available.
- Test iteration: the Stopwatch/Alarm tools panel now saves its own anchor and offsets in LocalClockDB when dragged, and restores that position on the next run/session. Its first-install default remains centered slightly below screen center; the main clock's position settings are independent.
- Test iteration: defer live checkbox texture refresh until the next UI frame, after the legacy dropdown finishes its own click-state processing; keeps both Show Game Clock and Show LocalClock checkmarks synchronized without closing the menu.
- Test iteration: refreshed legacy dropdown checkmark textures with Show/Hide while retaining the open menu; submenu levels now open in the same left/right direction as the root menu and are screen-clamped.
- Stabilized menu anchoring on the minimap button when opened from the clock display, so toggling LocalClock visibility does not hide its own menu.
- Minimap-button Shift-drag now saves the final button-center angle instead of the cursor angle, preventing the button from snapping after release.
- Regression fix: removed recursive minimap-frame traversal from the native clock auto-sizing path and protected resizing so a client-specific FontString/frame API cannot interrupt LocalClock initialization or hide its main display. Dynamic 12h/24h width adjustment remains enabled.
- Test iteration: split the settings-menu entry into separate Stopwatch... and Alarm... actions; each opens the tools panel directly in its selected mode. Updated the minimap-button tooltip to the neutral Clock tools label.
- Test iteration: native Game Clock surround now measures the live clock FontString and resizes around its actual 12-hour or 24-hour text, with a consistent 6px side margin; includes a conservative text-length fallback when the native FontString cannot be found.
- Test iteration: reduced the native Game Clock surround width from 56px to 46px to remove excess side padding around the time label; retained its height and vertical placement.
- Test iteration: replaced the separate minimap background, inventory icon, and offset tracking-border texture with one centered alpha-masked circular clock-button texture.
- Test iteration: replaced the square inventory icon/background with an addon-bundled alpha-masked circular clock-face texture; retained the now-aligned gold tracking ring.
- Test iteration: cropped the square clock icon and offset the legacy tracking-border canvas to center its visible gold ring around the icon.
- Context-aware settings menu placement: opens toward the available side of the screen instead of always opening to the right.
- Reworked the minimap launcher artwork to use a circular minimap background, centered inset icon, and tighter tracking border.
- Kept Show Game Clock safely disabled when the required HUD visibility APIs are unavailable; Game Local Time reading remains independent.

## 1.4.0
- Added Azeroth Survivors 0.136.0 Game Local Time integration through `AZS_GetLocalTime()`.
- Fresh installs default to the game's device-local time and native language-specific 12/24-hour format; existing saved time zones are preserved.
- Added independent Show Game Clock and Show LocalClock menu toggles. The native clock toggle uses the `localClock` HUD API part and does not affect the minimap or the run timer.
- Added a classic LocalClock minimap launcher button. Left-click opens Stopwatch & Alarm tools, right-click opens settings, and Shift-drag repositions the button around the minimap.
- The launcher follows minimap position, scale, and visibility. Its saved angular position is independent of the secondary clock's position.
- Hiding the minimap hides both clock displays, the native-clock surround, and the launcher without changing their saved visibility preferences.
- Preserved existing named/custom time zones, stopwatch, scheduled alarms, alarm warning frame, and LocalClock display integration with Move UI.

## 1.3.3
- Fixed the LocalClock context-menu visibility item so it toggles the clock without closing the menu.
- The menu item remains open and updates its label/checkmark immediately between "Hide LocalClock" and "Show LocalClock".
- Other menu actions retain their existing close-after-selection behavior.

## 1.3.2 — previous historical entry
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
