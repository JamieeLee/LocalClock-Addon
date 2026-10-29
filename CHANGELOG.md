# LocalClock 1.0.8

## Added
- Added Eastern European Time (EET) with automatic Eastern European Summer Time (EEST) switching.
- Added `eet`, `european`, `eastern european`, and `eastern-european` as aliases for the new regional setting.
- Added status/debug output for the active EET/EEST label and applied UTC offset.

## Compatibility
- Preserved the existing timezone presets and their existing behavior: Eastern, Central, Mountain, Pacific, Alaska, Arizona, Hawaii, and UTC.
- Kept the implementation self-contained and compatible with the legacy WoW 1.12-style Lua environment.
- No changes to Azeroth Survivors or dependencies on other addons.

## Testing note
- EET/EEST transition logic was checked against EU daylight-saving boundaries.
- Final behavior should still be verified in Azeroth Survivors in-game.
