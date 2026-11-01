-- LocalClock 1.1.2 for the legacy Azeroth Survivors client (Lua 5.0 style).
-- Uses the game's device-local clock API where available; named/custom zones
-- retain the UTC-based conversion engine and US/EU daylight-saving rules.

local frame
local label
local elapsed = 0
local shown = true
local colonVisible = true
local moveUIOwnsClock = false
local moveUIRegistered = false
local minimapVisible = true
local gameClockShown = true
local nativeClockFrame
local minimapButton
local watcher
local watcherElapsed = 0
local zones = {
    ["local"] = { standard = 0, dst = false, label = "Game Local Time" },
    eastern  = { standard = -5, dst = true,  label = "Eastern" },
    central  = { standard = -6, dst = true,  label = "Central" },
    mountain = { standard = -7, dst = true,  label = "Mountain" },
    pacific  = { standard = -8, dst = true,  label = "Pacific" },
    alaska   = { standard = -9, dst = true,  label = "Alaska" },
    hawaii   = { standard = -10, dst = false, label = "Hawaii" },
    arizona  = { standard = -7, dst = false, label = "Arizona" },
    utc      = { standard = 0, dst = false, label = "UTC" },
    cet      = { standard = 1, dst = true, eu = true, label = "CET", dstLabel = "CEST" },
    eet      = { standard = 2, dst = true, eu = true, label = "EET", dstLabel = "EEST" }
}
local panel, panelTime, panelZone, panelSlider, panel24, panel12
local toolsPanel, toolsStatus, toolsModeLabel
local toolsClockButton, toolsStopwatchButton, toolsAlarmButton
local toolsStopwatchAction, toolsStopwatchReset
local alarmHourBox, alarmMinuteBox, alarmSetButton, alarmCancelButton
local syncingSlider = false
local UpdatePanel
local UpdateClock
local UpdateToolsPanel
local CreateToolsPanel
local Print
local stopwatchElapsed = 0
local stopwatchRunning = false
local utilityElapsed = 0
local fallbackAlarmFrame
local fallbackAlarmText
local fallbackAlarmRemaining = 0
local MIN_OFFSET, MAX_OFFSET = -12, 14
local zoneOrder = { "local", "eastern", "central", "mountain", "pacific", "alaska", "arizona", "hawaii", "utc", "cet", "eet" }
local menu
local localClockMenuOpensLeft = false
local function Mod(a, b)
    return a - math.floor(a / b) * b
end

local function IsLeapYear(year)
    if Mod(year, 400) == 0 then return true end
    if Mod(year, 100) == 0 then return false end
    return Mod(year, 4) == 0
end

local function DaysInMonth(year, month)
    if month == 2 then
        if IsLeapYear(year) then return 29 end
        return 28
    end
    if month == 4 or month == 6 or month == 9 or month == 11 then return 30 end
    return 31
end

local function FirstSunday(year, month, current)
    -- date("*t").wday follows standard Lua convention: Sunday = 1.
    -- Derive the weekday of the first of the month from today's weekday.
    local firstWday = current.wday - (current.day - 1)
    while firstWday < 1 do firstWday = firstWday + 7 end
    while firstWday > 7 do firstWday = firstWday - 7 end
    return 1 + Mod(1 - firstWday, 7)
end

local function LastSunday(year, month, current)
    -- Compute the last Sunday of the month using the current UTC date's
    -- weekday. This avoids os.time/os.date, which this client does not expose.
    local firstWday = current.wday - (current.day - 1)
    while firstWday < 1 do firstWday = firstWday + 7 end
    while firstWday > 7 do firstWday = firstWday - 7 end
    local lastDay = DaysInMonth(year, month)
    local lastWday = 1 + Mod((firstWday - 1) + (lastDay - 1), 7)
    return lastDay - Mod(lastWday - 1, 7)
end

local function IsUSDaylightTime(t, standardOffset)
    if not t.month or not t.day or not t.hour or not t.wday then return false end
    if t.month < 3 or t.month > 11 then return false end
    if t.month > 3 and t.month < 11 then return true end

    if t.month == 3 then
        local first = FirstSunday(t.year, 3, t)
        local second = first + 7
        if t.day > second then return true end
        if t.day < second then return false end
        local transitionHour = 2 - (standardOffset or -5)
        return t.hour >= transitionHour -- 02:00 local standard time
    end
    local first = FirstSunday(t.year, 11, t)
    if t.day < first then return true end
    if t.day > first then return false end
    local transitionHour = 2 - ((standardOffset or -5) + 1)
    return t.hour < transitionHour -- 02:00 local daylight time
end

local function IsEuropeanDaylightTime(t)
    if not t.year or not t.month or not t.day or not t.hour or not t.wday then return false end
    if t.month < 3 or t.month > 10 then return false end
    if t.month > 3 and t.month < 10 then return true end

    if t.month == 3 then
        local last = LastSunday(t.year, 3, t)
        if t.day < last then return false end
        if t.day > last then return true end
        return t.hour >= 1 -- EU summer time starts at 01:00 UTC
    end

    local last = LastSunday(t.year, 10, t)
    if t.day < last then return true end
    if t.day > last then return false end
    return t.hour < 1 -- EU summer time ends at 01:00 UTC
end

-- Azeroth Survivors 0.136.0 exposes the same device-local clock used by
-- the native minimap widget. Read it as a snapshot; never infer the device
-- time zone from the realm clock or the UTC date API.
local function ReadGameLocalTime()
    if type(AZS_GetLocalTime) ~= "function" then return nil end
    -- Support both the table snapshot and four-value Lua return shape. The
    -- public changelog describes the returned fields but not their container.
    local ok, first, second, third, fourth = pcall(AZS_GetLocalTime)
    if not ok then return nil end

    local reading
    if type(first) == "table" then
        reading = first
    elseif type(first) == "string" then
        reading = {
            text = first,
            hour = second,
            minute = third,
            is24Hour = fourth
        }
    else
        return nil
    end

    -- The changelog describes a format value without pinning its Lua type.
    -- Accept the documented boolean as well as common textual format labels.
    local formatValue = reading.is24Hour
    if formatValue == nil then formatValue = reading.format end
    if type(formatValue) == "string" then
        local normalized = string.lower(formatValue)
        if normalized == "24" or normalized == "24h" or normalized == "24-hour" or normalized == "24hour" then
            formatValue = true
        elseif normalized == "12" or normalized == "12h" or normalized == "12-hour" or normalized == "12hour" then
            formatValue = false
        else
            return nil
        end
    end

    if type(reading.text) ~= "string" or type(reading.hour) ~= "number" or
        type(reading.minute) ~= "number" or type(formatValue) ~= "boolean" then
        return nil
    end
    if reading.hour < 0 or reading.hour > 23 or reading.minute < 0 or reading.minute > 59 then
        return nil
    end
    return {
        text = reading.text,
        hour = reading.hour,
        minute = reading.minute,
        is24Hour = formatValue
    }
end

local function NormalizeGameClockShown(value)
    if value == true or value == 1 or value == "1" then return true end
    if value == false or value == 0 or value == "0" then return false end
    return nil
end

local function GetOffset(t)
    local zoneName = "eastern"
    if LocalClockDB and LocalClockDB.zone then zoneName = LocalClockDB.zone end
    if zoneName == "local" then
        if ReadGameLocalTime() then return 0, "Device Local Time" end
        -- Older clients without the getter retain the previous Eastern fallback.
        zoneName = "eastern"
    end
    if zoneName == "custom" then
        local o = (LocalClockDB and LocalClockDB.customOffset) or 0
        if o == 0 then return 0, "UTC" end
        if o > 0 then return o, "UTC+" .. o end
        return o, "UTC" .. o
    end
    local zone = zones[zoneName] or zones.eastern
    local offset = zone.standard
    local zoneLabel = zone.label
    if zone.dst then
        if zone.eu then
            if IsEuropeanDaylightTime(t) then
                offset = offset + 1
                zoneLabel = zone.dstLabel or zone.label
            end
        elseif IsUSDaylightTime(t, zone.standard) then
            offset = offset + 1
        end
    end
    return offset, zoneLabel
end

local function ShiftDate(t, offset)
    local year, month, day = t.year, t.month, t.day
    local hour = t.hour + offset
    while hour < 0 do
        hour = hour + 24
        day = day - 1
    end
    while hour >= 24 do
        hour = hour - 24
        day = day + 1
    end
    while day < 1 do
        month = month - 1
        if month < 1 then month = 12; year = year - 1 end
        day = DaysInMonth(year, month)
    end
    while day > DaysInMonth(year, month) do
        day = day - DaysInMonth(year, month)
        month = month + 1
        if month > 12 then month = 1; year = year + 1 end
    end
    return year, month, day, hour
end

local function GetGameLocalHour24(reading)
    if not reading then return 0 end
    local hour = reading.hour or 0

    -- A 24-hour source is already normalized. Some clients may expose a
    -- 12-hour numeric hour (1-12) alongside a formatted string such as
    -- "1:41 PM"; convert that numeric value when the user requests 24-hour.
    if reading.is24Hour then return hour end

    local text = string.lower(reading.text or "")
    local isPM = string.find(text, "p%.?m%.?")
    local isAM = string.find(text, "a%.?m%.?")

    if isPM then
        if hour < 12 then hour = hour + 12 end
    elseif isAM then
        if hour == 12 then hour = 0 end
    end

    -- If the API already returned 13-23 despite using a 12-hour display
    -- string, leave it untouched. This also safely handles clients whose
    -- numeric hour is already 24-hour even when their text is localized.
    return hour
end

local function GetClockText()
    local zoneName = LocalClockDB and LocalClockDB.zone or "eastern"

    if zoneName == "local" then
        local reading = ReadGameLocalTime()
        if reading then
            local formatMode = LocalClockDB and LocalClockDB.localFormat or "game"
            if formatMode == "game" then
                -- Use the game's exact language-aware string (English 12h,
                -- other localized formats 24h) without reformatting it.
                return reading.text
            end

            local hour = reading.hour
            local minute = reading.minute
            local colon = colonVisible and ":" or " "
            if formatMode == "12h" then
                local hour24 = GetGameLocalHour24(reading)
                local suffix = (hour24 >= 12) and "PM" or "AM"
                hour = Mod(hour24, 12)
                if hour == 0 then hour = 12 end
                return string.format("%d%s%02d %s", hour, colon, minute, suffix)
            end
            hour = GetGameLocalHour24(reading)
            return string.format("%02d%s%02d", hour, colon, minute)
        end
        -- If the API is temporarily unavailable, preserve a usable clock.
        -- GetOffset() supplies the legacy Eastern fallback in that case.
    end

    if not date then return "-- -- --" end
    local ok, t = pcall(date, "*t")
    if not ok or type(t) ~= "table" or not t.hour or not t.min then return "-- -- --" end

    local offset = GetOffset(t)
    local year, month, day, hour = ShiftDate(t, offset)
    local minute = t.min
    local colon = ":"
    if not colonVisible then colon = " " end
    if LocalClockDB and LocalClockDB.use12Hour then
        local suffix = "AM"
        if hour >= 12 then suffix = "PM" end
        hour = Mod(hour, 12)
        if hour == 0 then hour = 12 end
        return string.format("%d%s%02d %s", hour, colon, minute, suffix)
    end
    return string.format("%02d%s%02d", hour, colon, minute)
end

local function IsClockUsing12Hour()
    if LocalClockDB and LocalClockDB.zone == "local" then
        local formatMode = LocalClockDB.localFormat or "game"
        if formatMode == "12h" then return true end
        if formatMode == "24h" then return false end
        local reading = ReadGameLocalTime()
        if reading then return not reading.is24Hour end
    end
    return LocalClockDB and LocalClockDB.use12Hour and true or false
end

local function FormatDuration(seconds)
    seconds = math.floor(math.max(0, seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds - (hours * 3600)) / 60)
    local remainder = seconds - (hours * 3600) - (minutes * 60)
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function GetUtcTable(timestamp)
    if not date then return nil end
    local ok, t
    if timestamp then
        ok, t = pcall(date, "*t", timestamp)
    else
        ok, t = pcall(date, "*t")
    end
    if not ok or type(t) ~= "table" or not t.hour or not t.min then return nil end
    return t
end

local function ComputeAlarmTimestamp(hour, minute)
    if not time then
        return nil, "This client does not expose a UTC timestamp, so scheduled alarms are unavailable."
    end
    local now = time()
    local utcNow = GetUtcTable(now)
    if type(now) ~= "number" or not utcNow then
        return nil, "The current UTC time could not be read."
    end

    -- For Game Local Time, use the game's device-local snapshot to calculate
    -- the wall-clock interval. The native widget may be hidden; the getter
    -- remains available independently of visibility.
    local wallDelta
    if LocalClockDB and LocalClockDB.zone == "local" then
        local reading = ReadGameLocalTime()
        if reading then
            local localNow = (reading.hour * 3600) + (reading.minute * 60) + (utcNow.sec or 0)
            local targetLocal = (hour * 3600) + (minute * 60)
            wallDelta = targetLocal - localNow
            if wallDelta <= 0 then wallDelta = wallDelta + 86400 end
            return math.floor(now + wallDelta + 0.5)
        end
    end

    -- Named/custom time zones continue using LocalClock's existing UTC/DST engine.
    local currentOffset = GetOffset(utcNow)
    local _, _, _, localHour = ShiftDate(utcNow, currentOffset)
    local localNow = (localHour * 3600) + ((utcNow.min or 0) * 60) + (utcNow.sec or 0)
    local targetLocal = (hour * 3600) + (minute * 60)
    wallDelta = targetLocal - localNow
    if wallDelta <= 0 then wallDelta = wallDelta + 86400 end

    local targetOffset = currentOffset
    local targetTimestamp
    local i
    for i = 1, 4 do
        targetTimestamp = now + wallDelta - ((targetOffset - currentOffset) * 3600)
        local targetUtc = GetUtcTable(targetTimestamp)
        if not targetUtc then return nil, "The alarm date could not be calculated." end
        local newOffset = GetOffset(targetUtc)
        if newOffset == targetOffset then break end
        targetOffset = newOffset
    end

    -- A wall-clock time skipped by the spring-forward DST jump does not
    -- exist on that date. In that rare case, schedule the next occurrence.
    if not targetTimestamp or targetTimestamp <= now then
        wallDelta = wallDelta + 86400
        targetOffset = currentOffset
        for i = 1, 4 do
            targetTimestamp = now + wallDelta - ((targetOffset - currentOffset) * 3600)
            local targetUtc = GetUtcTable(targetTimestamp)
            if not targetUtc then return nil, "The alarm date could not be calculated." end
            local newOffset = GetOffset(targetUtc)
            if newOffset == targetOffset then break end
            targetOffset = newOffset
        end
    end
    if not targetTimestamp or targetTimestamp <= now then
        return nil, "The alarm time could not be scheduled."
    end
    return math.floor(targetTimestamp + 0.5)
end

local function RefreshAlarmForZoneChange()
    if not LocalClockDB or not LocalClockDB.alarmTimestamp or LocalClockDB.alarmFired then return end
    if LocalClockDB.alarmHour == nil or LocalClockDB.alarmMinute == nil then return end
    local timestamp = ComputeAlarmTimestamp(LocalClockDB.alarmHour, LocalClockDB.alarmMinute)
    if timestamp then LocalClockDB.alarmTimestamp = timestamp end
end

local function SetDisplayMode(mode)
    if mode ~= "clock" and mode ~= "stopwatch" and mode ~= "alarm" then return end
    if not LocalClockDB then LocalClockDB = {} end
    LocalClockDB.displayMode = mode
    UpdateClock()
    if UpdateToolsPanel then UpdateToolsPanel() end
end

local function SetStopwatchRunning(running)
    stopwatchRunning = running and true or false
    if LocalClockDB then
        LocalClockDB.stopwatchElapsed = stopwatchElapsed
        LocalClockDB.stopwatchRunning = stopwatchRunning
    end
    SetDisplayMode("stopwatch")
    if UpdateToolsPanel then UpdateToolsPanel() end
    if label then UpdateClock() end
end

local function ResetStopwatch()
    stopwatchElapsed = 0
    stopwatchRunning = false
    if LocalClockDB then
        LocalClockDB.stopwatchElapsed = 0
        LocalClockDB.stopwatchRunning = false
    end
    SetDisplayMode("stopwatch")
end

local function SetAlarmAt(hour, minute)
    hour = tonumber(hour)
    minute = tonumber(minute)
    if not hour or not minute or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return false, "Enter a valid time between 00:00 and 23:59."
    end
    hour = math.floor(hour)
    minute = math.floor(minute)
    local timestamp, err = ComputeAlarmTimestamp(hour, minute)
    if not timestamp then return false, err end

    LocalClockDB.alarmHour = hour
    LocalClockDB.alarmMinute = minute
    LocalClockDB.alarmTimestamp = timestamp
    LocalClockDB.alarmFired = false
    SetDisplayMode("alarm")
    if UpdateToolsPanel then UpdateToolsPanel() end
    return true
end

local function CancelAlarm()
    if LocalClockDB then
        LocalClockDB.alarmTimestamp = nil
        LocalClockDB.alarmHour = nil
        LocalClockDB.alarmMinute = nil
        LocalClockDB.alarmFired = false
    end
    if UpdateToolsPanel then UpdateToolsPanel() end
    if label then UpdateClock() end
end

local function DismissAlarm()
    if fallbackAlarmFrame then fallbackAlarmFrame:Hide() end
    if LocalClockDB then
        LocalClockDB.alarmTimestamp = nil
        LocalClockDB.alarmFired = false
        LocalClockDB.alarmHour = nil
        LocalClockDB.alarmMinute = nil
    end
    if LocalClockDB and LocalClockDB.displayMode == "alarm" then
        LocalClockDB.displayMode = "clock"
    end
    if UpdateToolsPanel then UpdateToolsPanel() end
    if label then UpdateClock() end
end

local function CreateAlarmWarningFrame()
    if fallbackAlarmFrame then return end
    fallbackAlarmFrame = CreateFrame("Frame", "LocalClockAlarmWarning", UIParent)
    fallbackAlarmFrame:SetWidth(820)
    fallbackAlarmFrame:SetHeight(74)
    fallbackAlarmFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    fallbackAlarmFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 92)
    fallbackAlarmText = fallbackAlarmFrame:CreateFontString("LocalClockAlarmWarningText", "OVERLAY")
    fallbackAlarmText:SetFont("Fonts\\FRIZQT__.TTF", 32, "THICKOUTLINE")
    fallbackAlarmText:SetTextColor(1, 0.82, 0.12)
    if fallbackAlarmText.SetJustifyH then fallbackAlarmText:SetJustifyH("CENTER") end
    fallbackAlarmText:SetPoint("CENTER", fallbackAlarmFrame, "CENTER", 0, 0)
    fallbackAlarmFrame:SetScript("OnUpdate", function()
        fallbackAlarmRemaining = fallbackAlarmRemaining - (arg1 or 0)
        if fallbackAlarmRemaining <= 0 then
            fallbackAlarmFrame:Hide()
        elseif fallbackAlarmRemaining < 2 then
            fallbackAlarmFrame:SetAlpha(fallbackAlarmRemaining / 2)
        else
            fallbackAlarmFrame:SetAlpha(1)
        end
    end)
    fallbackAlarmFrame:Hide()

    -- The alarm has its own frame because this client can route warning text
    -- through UIErrorsFrame or a custom fallback instead of RaidWarningFrame.
    -- Move UI lists this frame separately so the visible alarm is always the
    -- one being moved/scaled, regardless of which stock warning APIs exist.
    if MoveAnything_InitRun and MoveAnything_RefreshPositions then
        MoveAnything_RefreshPositions()
    end
end

local function ShowFallbackAlarmBanner(message)
    CreateAlarmWarningFrame()
    -- Respect a deliberate Move UI hide choice. Alarm audio and chat logging
    -- still happen, but a hidden visual alert remains hidden.
    if MoveAnything_IsFrameHidden and MoveAnything_IsFrameHidden("LocalClockAlarmWarning") then
        return
    end
    fallbackAlarmText:SetText(message)
    fallbackAlarmRemaining = 10
    fallbackAlarmFrame:SetAlpha(1)
    fallbackAlarmFrame:Show()
end

local function ShowAlarmWarning()
    -- Always use the named LocalClock frame. The stock path is inconsistent
    -- across Azeroth Survivors client builds: RaidNotice_AddMessage may not
    -- exist, or messages may be routed to UIErrorsFrame. A dedicated mover
    -- makes Move UI's scale/position settings apply to the exact visible text.
    ShowFallbackAlarmBanner("LOCALCLOCK ALARM: YOUR TIME IS UP!")
end

local function CheckAlarm()
    if not LocalClockDB or not LocalClockDB.alarmTimestamp or LocalClockDB.alarmFired or not time then return end
    local now = time()
    if type(now) == "number" and now >= LocalClockDB.alarmTimestamp then
        LocalClockDB.alarmTimestamp = nil
        LocalClockDB.alarmFired = true
        LocalClockDB.displayMode = "alarm"
        ShowAlarmWarning()
        if Print then Print("ALARM! Your scheduled LocalClock time has arrived.") end
        if PlaySoundFile then
            pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav")
        elseif PlaySound then
            pcall(PlaySound, "igMainMenuOpen")
        end
        if UpdateToolsPanel then UpdateToolsPanel() end
        if label then UpdateClock() end
    end
end

local function GetDisplayText()
    local mode = LocalClockDB and LocalClockDB.displayMode or "clock"
    if mode == "stopwatch" then
        return FormatDuration(stopwatchElapsed)
    elseif mode == "alarm" then
        if LocalClockDB and LocalClockDB.alarmFired then return "ALARM!" end
        if LocalClockDB and LocalClockDB.alarmTimestamp and time then
            local remaining = LocalClockDB.alarmTimestamp - time()
            if remaining < 0 then remaining = 0 end
            return FormatDuration(remaining)
        end
        return "ALARM OFF"
    end
    return GetClockText()
end

UpdateClock = function()
    if label then label:SetText(GetDisplayText()) end
    if UpdatePanel then UpdatePanel() end
    if UpdateToolsPanel then UpdateToolsPanel() end
end

local appliedMinimapScale = 1

local function GetMinimapContainer()
    if MinimapCluster then return MinimapCluster end
    if Minimap and Minimap.GetParent then
        local parent = Minimap:GetParent()
        if parent then return parent end
    end
    return UIParent
end

local function GetGameClockShown()
    -- Prefer the documented HUD API when the query function is present.
    if type(AZS_IsHudShown) == "function" then
        local ok, value = pcall(AZS_IsHudShown, "localClock")
        if ok then
            local normalized = NormalizeGameClockShown(value)
            if normalized ~= nil then
                gameClockShown = normalized
                return normalized
            end
        end
    end

    -- The saved hudLocalClock CVar is the documented preference backing this
    -- part. Preserve false explicitly; never use an and/or pseudo-ternary here.
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, "hudLocalClock")
        if ok then
            local normalized = NormalizeGameClockShown(value)
            if normalized ~= nil then
                gameClockShown = normalized
                return normalized
            end
        end
    end
    return gameClockShown
end

local function ApplyNativeClockFrameVisibility()
    if nativeClockFrame then
        if minimapVisible and GetGameClockShown() then
            nativeClockFrame:Show()
        else
            nativeClockFrame:Hide()
        end
    end
    if minimapButton then
        if minimapVisible then minimapButton:Show() else minimapButton:Hide() end
    end
end

local function SetGameClockShown(value)
    value = value and true or false

    -- Prefer the dedicated HUD API. Do not require the getter or time getter
    -- to exist: the visibility setter is an independent capability.
    if type(AZS_SetHudShown) == "function" then
        local ok, err = pcall(AZS_SetHudShown, "localClock", value)
        if ok then
            gameClockShown = value
            ApplyNativeClockFrameVisibility()
            return true
        end
        -- If the wrapper exists but errors, attempt the documented CVar path.
        if type(SetCVar) ~= "function" then
            if Print then Print("Could not change the native Game Clock: " .. tostring(err)) end
            return false
        end
    end

    -- The game documents hudLocalClock as the saved preference backing the
    -- localClock HUD part. This fallback also covers builds that expose the
    -- CVar but omit one of the Lua query/setter wrappers.
    if type(SetCVar) == "function" then
        local cvarValue = value and "1" or "0"
        local ok, err = pcall(SetCVar, "hudLocalClock", cvarValue)
        if ok then
            gameClockShown = value
            ApplyNativeClockFrameVisibility()
            return true
        end
        if Print then Print("Could not change the native Game Clock: " .. tostring(err)) end
        return false
    end

    if Print then Print("Native Game Clock visibility controls are unavailable in this client build.") end
    return false
end

local function GetMoveUIScaleMultiplier()
    if MoveAnything_FrameOptions then
        local opt = MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if opt and tonumber(opt.scale) then return tonumber(opt.scale) end
    end
    return 1
end

-- Resize the native clock surround from the exact string supplied by the
-- game's local-time API. Avoid traversing the minimap frame tree here: some
-- client builds expose protected/atypical frame regions during PLAYER_LOGIN.
local function UpdateNativeClockFrameSize()
    if not nativeClockFrame then return end

    local ok, reading = pcall(ReadGameLocalTime)
    if not ok or type(reading) ~= "table" or
        type(reading.text) ~= "string" or reading.text == "" then
        return
    end

    -- Approximate the native font's average glyph width, then add a stable
    -- 6px margin on each side. The value follows 12h/24h and localized text
    -- lengths while avoiding dependence on private minimap child regions.
    local desiredWidth = math.ceil((string.len(reading.text) * 5.2) + 12)
    if desiredWidth < 40 then desiredWidth = 40 end

    local widthOK, currentWidth = pcall(nativeClockFrame.GetWidth, nativeClockFrame)
    if not widthOK or type(currentWidth) ~= "number" then return end
    if math.abs(currentWidth - desiredWidth) >= 1 then
        pcall(nativeClockFrame.SetWidth, nativeClockFrame, desiredWidth)
    end
end

local function CreateNativeClockFrame()
    if nativeClockFrame then return end
    local parent = GetMinimapContainer()
    nativeClockFrame = CreateFrame("Frame", "LocalClockNativeFrame", parent)
    -- Start at a compact width; UpdateNativeClockFrameSize() measures the
    -- actual native time label and resizes this surround as the text changes.
    nativeClockFrame:SetWidth(46)
    nativeClockFrame:SetHeight(19)
    nativeClockFrame:SetFrameStrata("HIGH")
    if nativeClockFrame.SetBackdrop then
        -- Border only: the game's own clock text must remain visible above it.
        nativeClockFrame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        if nativeClockFrame.SetBackdropBorderColor then
            nativeClockFrame:SetBackdropBorderColor(0.78, 0.68, 0.48, 0.95)
        end
    end
    nativeClockFrame:ClearAllPoints()
    if Minimap then
        nativeClockFrame:SetPoint("CENTER", Minimap, "BOTTOM", 0, -8)
    else
        nativeClockFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    -- This surround mirrors the native Game Clock preference, but remains a
    -- separate addon frame so the border never obscures the game's text.
    ApplyNativeClockFrameVisibility()
end

local function UpdateMinimapScale()
    if not Minimap or not Minimap.GetEffectiveScale then return end
    local minimapScale = Minimap:GetEffectiveScale()
    local parent = GetMinimapContainer()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local parentScale = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
    if type(minimapScale) ~= "number" or type(uiScale) ~= "number" or uiScale <= 0 or type(parentScale) ~= "number" or parentScale <= 0 then return end

    -- The native surround is parented to MinimapCluster and inherits its scale.
    local nativeScale = minimapScale / parentScale
    -- LocalClock is parented to UIParent so Move UI can show it independently
    -- of a hidden minimap; its effective scale still matches Minimap.
    local displayScale = minimapScale / uiScale
    if nativeScale <= 0 or displayScale <= 0 then return end
    local changed = math.abs(displayScale - appliedMinimapScale) >= 0.001
    if not changed then return end
    appliedMinimapScale = displayScale

    if nativeClockFrame and nativeClockFrame.SetScale then
        nativeClockFrame:SetScale(nativeScale)
        nativeClockFrame:ClearAllPoints()
        nativeClockFrame:SetPoint("CENTER", Minimap, "BOTTOM", 0, -8 * nativeScale)
    end
    if frame and frame.SetScale then
        frame.LocalClockMinimapScale = displayScale
        if frame.HiddenSetScale then
            frame:HiddenSetScale(displayScale * GetMoveUIScaleMultiplier())
        else
            frame:SetScale(displayScale * GetMoveUIScaleMultiplier())
        end
        local moveUISavedPosition = false
        if moveUIRegistered and MoveAnything_FindFrameOptions then
            local opt = MoveAnything_FindFrameOptions("LocalClockDisplayFrame")
            if opt and opt.movable then moveUISavedPosition = true end
        end
        if not (LocalClockDB and LocalClockDB.point) and not moveUISavedPosition then
            if frame.HiddenClearAllPoints then frame:HiddenClearAllPoints() else frame:ClearAllPoints() end
            if nativeClockFrame then
                if frame.HiddenSetPoint then
                    frame:HiddenSetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * displayScale)
                else
                    frame:SetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * displayScale)
                end
            end
        end
    end
end

local function SavePosition()
    if not frame or not LocalClockDB then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    LocalClockDB.point = point or "CENTER"
    LocalClockDB.relativePoint = relativePoint or "CENTER"
    LocalClockDB.x = x or 0
    LocalClockDB.y = y or 0
    LocalClockDB.relativeToName = nil
    if relativeTo and relativeTo ~= UIParent and relativeTo.GetName then
        LocalClockDB.relativeToName = relativeTo:GetName()
    end
end

local function RestorePosition()
    if not frame then return end
    frame:ClearAllPoints()
    if LocalClockDB and LocalClockDB.point then
        local relativeTo = UIParent
        if LocalClockDB.relativeToName and getglobal then
            relativeTo = getglobal(LocalClockDB.relativeToName) or UIParent
        end
        frame:SetPoint(LocalClockDB.point, relativeTo, LocalClockDB.relativePoint or LocalClockDB.point,
            LocalClockDB.x or 0, LocalClockDB.y or 0)
    elseif nativeClockFrame then
        -- Default to directly below the built-in minimap clock.
        frame:SetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * appliedMinimapScale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

Print = function(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLocalClock:|r " .. message)
    end
end

local function MoveUIUserHidesLocalClock()
    if MoveAnything_FrameOptions then
        local opt = MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if opt and opt.hidden then return true end
    end
    if MoveAnything_IsFrameHidden then
        local ok, hidden = pcall(MoveAnything_IsFrameHidden, "LocalClockDisplayFrame")
        if ok and hidden then return true end
    end
    return false
end

local function MoveUIHidesLocalClock()
    if MoveAnything_FrameOptions then
        local opt = MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if opt and (opt.hidden or opt.minimapSuppressed) then return true end
    end
    return MoveUIUserHidesLocalClock()
end

local function SetFrameActualShown(target, value)
    if not target then return end
    if value then
        if target.HiddenShow then target:HiddenShow() else target:Show() end
    else
        if target.HiddenHide then target:HiddenHide() else target:Hide() end
    end
end

local function ApplyClockVisibility()
    if not frame then return end
    local shouldShow = shown and minimapVisible and not MoveUIHidesLocalClock()
    SetFrameActualShown(frame, shouldShow)
    if shouldShow then UpdateClock() end
end

-- Called by Move UI when its independent LocalClock Hide checkbox changes.
function LocalClock_OnMoveUIVisibilityChanged(visible)
    shown = visible and true or false
    if LocalClockDB then LocalClockDB.shown = shown end
    ApplyClockVisibility()
end

-- Called by Move UI when MinimapCluster itself is hidden or shown.
function LocalClock_OnMinimapVisibilityChanged(visible)
    minimapVisible = visible and true or false
    ApplyNativeClockFrameVisibility()

    if MoveAnything_FrameOptions then
        local opt = MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if opt then
            if minimapVisible or opt.hidden or not shown then
                -- Clear only the transient state. The user's own hidden flag
                -- remains untouched and continues to control LocalClock.
                opt.minimapSuppressed = nil
            else
                -- The minimap's Hide state temporarily checks LocalClock's
                -- Hide box without changing the user's saved preference.
                opt.minimapSuppressed = true
            end
        end
    end

    ApplyClockVisibility()
    if MoveAnythingOptions_Update and MAOptions and MAOptions.IsVisible and MAOptions:IsVisible() then
        MoveAnythingOptions_Update()
    end
end

local function SetShown(value)
    shown = value and true or false
    if LocalClockDB then LocalClockDB.shown = shown end
    if moveUIRegistered and frame then
        local opt = MoveAnything_FrameOptions and MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if opt then opt.minimapSuppressed = nil end
        local userHidden = MoveUIUserHidesLocalClock()
        if shown and userHidden and MoveAnything_ShowFrame then
            MoveAnything_ShowFrame(frame)
        elseif (not shown) and (not userHidden) and MoveAnything_HideFrame then
            MoveAnything_HideFrame(frame)
        else
            ApplyClockVisibility()
        end
        if MoveAnythingOptions_Update and MAOptions and MAOptions.IsVisible and MAOptions:IsVisible() then
            MoveAnythingOptions_Update()
        end
    else
        ApplyClockVisibility()
    end
end

local function RegisterWithMoveUI()
    if not frame or not MoveAnything_InitRun or not MoveAnything_AddFrameToMovableList then return false end
    if not moveUIRegistered then
        if not (MoveAnything_FindFrame and MoveAnything_FindFrame("LocalClockDisplayFrame")) then
            MoveAnything_AddFrameToMovableList("LocalClockDisplayFrame", "Local Clock (Time Zone)", true)
        end
        moveUIRegistered = true
        moveUIOwnsClock = true
        -- minimapSuppressed is runtime state, not a persistent user preference.
        -- Clear any value saved by an earlier session; the watcher below will
        -- re-derive it from MinimapCluster's actual Move UI hidden state.
        if MoveAnything_FrameOptions then
            local savedOpt = MoveAnything_FrameOptions["LocalClockDisplayFrame"]
            if savedOpt then savedOpt.minimapSuppressed = nil end
        end
        if frame.SetMovable then frame:SetMovable(false) end
        frame:SetScript("OnDragStart", function() end)
        frame:SetScript("OnDragStop", function() end)
        frame.OnMoveAnythingPostReset = function()
            if LocalClockDB then
                LocalClockDB.point = nil
                LocalClockDB.relativePoint = nil
                LocalClockDB.x = nil
                LocalClockDB.y = nil
                LocalClockDB.relativeToName = nil
            end
            if frame then
                frame:ClearAllPoints()
                if nativeClockFrame then
                    frame:SetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * appliedMinimapScale)
                end
                if frame.SetScale then frame:SetScale(appliedMinimapScale) end
            end
        end
        -- Refresh now that the addon-created frame exists. This reapplies any
        -- saved Move UI position, scale, or hidden state for this named frame.
        if MoveAnything_RefreshPositions then MoveAnything_RefreshPositions() end
        if MoveAnything_IsFrameHidden and MoveAnything_IsFrameHidden("LocalClockDisplayFrame") then
            -- A saved Move UI Hide preference is authoritative.
            shown = false
            if LocalClockDB then LocalClockDB.shown = false end
        elseif not shown and MoveAnything_HideFrame then
            -- Also mirror an existing LocalClockDB hidden preference into the
            -- Move UI checkbox (for users upgrading from a no-Move-UI setup).
            MoveAnything_HideFrame(frame)
        end
    end
    return true
end

local function UpdateDragOwnership()
    local useMoveUI = MoveAnything_InitRun and MoveAnything_AddFrameToMovableList and true or false
    if useMoveUI then
        RegisterWithMoveUI()
        return
    end
    if moveUIOwnsClock then
        moveUIOwnsClock = false
        moveUIRegistered = false
    end
    if not frame then return end
    if frame.SetMovable then frame:SetMovable(true) end
    frame:SetScript("OnDragStart", function()
        if not (LocalClockDB and LocalClockDB.locked) and frame.StartMoving then frame:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        SavePosition()
    end)
end

local function UpdateMinimapVisibility()
    local visible = true
    local moveUIHidden = false
    if MoveAnything_IsFrameHidden then
        local ok, result = pcall(MoveAnything_IsFrameHidden, "MinimapCluster")
        if ok and result then moveUIHidden = true end
    end
    if moveUIHidden then
        -- Move UI's saved hidden state is authoritative; the legacy client may
        -- report IsVisible through its visibility wrapper as the wanted state.
        visible = false
    elseif not MoveAnything_InitRun then
        if Minimap and Minimap.IsVisible then
            local ok, result = pcall(Minimap.IsVisible, Minimap)
            if ok then visible = result and true or false end
        elseif Minimap and Minimap.IsShown then
            local ok, result = pcall(Minimap.IsShown, Minimap)
            if ok then visible = result and true or false end
        elseif MinimapCluster and MinimapCluster.IsVisible then
            local ok, result = pcall(MinimapCluster.IsVisible, MinimapCluster)
            if ok then visible = result and true or false end
        end
    end

    if visible ~= minimapVisible then
        LocalClock_OnMinimapVisibilityChanged(visible)
    else
        ApplyClockVisibility()
        ApplyNativeClockFrameVisibility()
    end
end

-- Runs on UIParent so it can monitor a hidden minimap and notice Move UI.
local function StartWatcher()
    if watcher then return end
    watcher = CreateFrame("Frame", nil, UIParent)
    watcher:SetScript("OnUpdate", function()
        local delta = arg1 or 0
        watcherElapsed = watcherElapsed + delta
        utilityElapsed = utilityElapsed + delta
        if stopwatchRunning then
            stopwatchElapsed = stopwatchElapsed + delta
            if LocalClockDB then LocalClockDB.stopwatchElapsed = stopwatchElapsed end
        end
        if utilityElapsed >= 0.25 then
            utilityElapsed = utilityElapsed - 0.25
            CheckAlarm()
            if toolsPanel and toolsPanel:IsShown() then UpdateToolsPanel() end
        end
        if watcherElapsed >= 0.5 then
            watcherElapsed = watcherElapsed - 0.5
            UpdateDragOwnership()
            UpdateMinimapScale()
            UpdateMinimapVisibility()
            -- Resizing is best-effort and must never interrupt the main clock.
            pcall(UpdateNativeClockFrameSize)
            ApplyNativeClockFrameVisibility()
        end
    end)
end

-- Right-click options menu (standard UIDropDownMenu, available since vanilla).
local function RunCommand(cmd)
    SlashCmdList["LOCALCLOCK"](cmd)
    if CloseDropDownMenus then CloseDropDownMenus() end
end

local function AddMenuButton(info)
    if UIDropDownMenu_AddButton then UIDropDownMenu_AddButton(info, info.level) end
end

local function RefreshMenuToggle(value, checked)
    if not getglobal then return end
    local level
    for level = 1, 4 do
        local i
        for i = 1, 24 do
            local button = getglobal("DropDownList" .. level .. "Button" .. i)
            if button and button.value == value then
                button.checked = checked and 1 or nil
                local buttonName = button:GetName()
                local check = getglobal(buttonName .. "Check")
                if check then
                    -- In the legacy dropdown template the checkmark is a
                    -- Texture, not a CheckButton; Show/Hide is the reliable
                    -- way to refresh it without closing the dropdown.
                    if checked then
                        if check.Show then check:Show() end
                    else
                        if check.Hide then check:Hide() end
                    end
                    if check.SetChecked then check:SetChecked(checked and 1 or 0) end
                end
                if button.checkButton and button.checkButton.SetChecked then
                    button.checkButton:SetChecked(checked and 1 or 0)
                end
            end
        end
    end
end

local menuToggleRefreshFrame
local pendingMenuToggleValue
local pendingMenuToggleChecked

local function QueueMenuToggleRefresh(value, checked)
    pendingMenuToggleValue = value
    pendingMenuToggleChecked = checked and true or false

    if not menuToggleRefreshFrame then
        menuToggleRefreshFrame = CreateFrame("Frame", "LocalClockMenuToggleRefresh", UIParent)
    end

    menuToggleRefreshFrame:SetScript("OnUpdate", function()
        -- Run once, after UIDropDownMenuButton_OnClick has completed its own
        -- checked-state processing for the current mouse click.
        menuToggleRefreshFrame:SetScript("OnUpdate", nil)
        local refreshValue = pendingMenuToggleValue
        local refreshChecked = pendingMenuToggleChecked
        pendingMenuToggleValue = nil
        pendingMenuToggleChecked = nil
        if refreshValue then
            RefreshMenuToggle(refreshValue, refreshChecked)
        end
    end)
end

local function InitMenu(level)
    level = level or UIDROPDOWNMENU_MENU_LEVEL or 1
    local db = LocalClockDB or {}
    local info

    if level == 2 and UIDROPDOWNMENU_MENU_VALUE == "ZONE" then
        local current = db.zone or "local"
        for _, key in ipairs(zoneOrder) do
            local zoneKey = key
            local z = zones[zoneKey]
            local text = z.label
            if z.dstLabel then text = z.label .. " / " .. z.dstLabel end
            info = { level = 2, text = text, checked = (current == zoneKey) and 1 or nil,
                func = function() RunCommand("zone " .. zoneKey) end }
            AddMenuButton(info)
        end
        AddMenuButton({ level = 2, text = "Custom (slider)", checked = (current == "custom") and 1 or nil,
            func = function() RunCommand("options") end })
        return
    end

    AddMenuButton({ level = 1, text = "LocalClock", isTitle = 1, notCheckable = 1 })
    AddMenuButton({ level = 1, text = "Time zone settings...", notCheckable = 1,
        func = function() RunCommand("options") end })
    AddMenuButton({ level = 1, text = "Clock...", notCheckable = 1,
        func = function()
            CreateToolsPanel()
            SetDisplayMode("clock")
            toolsPanel:Show()
        end })
    AddMenuButton({ level = 1, text = "Stopwatch...", notCheckable = 1,
        func = function()
            CreateToolsPanel()
            SetDisplayMode("stopwatch")
            toolsPanel:Show()
        end })
    AddMenuButton({ level = 1, text = "Alarm...", notCheckable = 1,
        func = function()
            CreateToolsPanel()
            SetDisplayMode("alarm")
            toolsPanel:Show()
        end })
    AddMenuButton({ level = 1, text = "Time zone", hasArrow = 1, value = "ZONE", notCheckable = 1 })
    AddMenuButton({ level = 1, text = "12-hour", checked = IsClockUsing12Hour() and 1 or nil,
        func = function() RunCommand("12h") end })
    AddMenuButton({ level = 1, text = "24-hour", checked = (not IsClockUsing12Hour()) and 1 or nil,
        func = function() RunCommand("24h") end })
    AddMenuButton({ level = 1, text = "Lock position", checked = db.locked and 1 or nil,
        func = function() RunCommand(db.locked and "unlock" or "lock") end })
    AddMenuButton({ level = 1, text = "Reset position", notCheckable = 1,
        func = function() RunCommand("reset") end })
    AddMenuButton({ level = 1, text = "Show Game Clock", value = "LOCALCLOCK_GAMECLOCK_TOGGLE",
        checked = GetGameClockShown() and 1 or nil,
        keepShownOnClick = 1,
        func = function()
            SetGameClockShown(not GetGameClockShown())
            QueueMenuToggleRefresh("LOCALCLOCK_GAMECLOCK_TOGGLE", GetGameClockShown())
        end })
    AddMenuButton({ level = 1, text = "Show LocalClock", value = "LOCALCLOCK_VISIBILITY_TOGGLE",
        checked = shown and 1 or nil, keepShownOnClick = 1,
        func = function()
            SetShown(not shown)
            QueueMenuToggleRefresh("LOCALCLOCK_VISIBILITY_TOGGLE", shown)
        end })
    AddMenuButton({ level = 1, text = "Close", notCheckable = 1,
        func = function() if CloseDropDownMenus then CloseDropDownMenus() end end })
end

local function PositionLocalClockMenu(anchorName)
    -- Choose the root dropdown side based on the actual anchor's screen
    -- position. Every child menu reuses this direction.
    local anchor = getglobal and getglobal(anchorName or "LocalClockDisplayFrame")
    local list = getglobal and getglobal("DropDownList1")
    if not anchor or not list or not anchor.GetCenter then return end

    local centerX = anchor:GetCenter()
    local uiWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if not centerX or not uiWidth then return end

    local leftSpace = centerX
    local rightSpace = uiWidth - centerX
    local rootWidth = list.GetWidth and list:GetWidth() or 0
    localClockMenuOpensLeft = rightSpace < (rootWidth + 12) or leftSpace > rightSpace

    list:ClearAllPoints()
    if localClockMenuOpensLeft then
        list:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        list:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
    if list.SetClampedToScreen then list:SetClampedToScreen(true) end
end

local function PositionLocalClockSubmenu(level)
    local child = getglobal and getglobal("DropDownList" .. level)
    local parent = getglobal and getglobal("DropDownList" .. (level - 1))
    if not child or not parent then return end

    local parentValue = UIDROPDOWNMENU_MENU_VALUE
    local parentButton
    local i
    for i = 1, 24 do
        local button = getglobal("DropDownList" .. (level - 1) .. "Button" .. i)
        if button and parentValue and button.value == parentValue then
            parentButton = button
            break
        end
    end
    if not parentButton then return end

    child:ClearAllPoints()
    if localClockMenuOpensLeft then
        child:SetPoint("TOPRIGHT", parentButton, "TOPLEFT", -3, 0)
    else
        child:SetPoint("TOPLEFT", parentButton, "TOPRIGHT", 3, 0)
    end
    if child.SetClampedToScreen then child:SetClampedToScreen(true) end
end

local function HookLocalClockSubmenus()
    if not getglobal then return end
    local level
    for level = 2, 4 do
        local list = getglobal("DropDownList" .. level)
        if list and not list.LocalClockPositionHooked and list.SetScript and list.GetScript then
            local hookedLevel = level
            local previousOnShow = list:GetScript("OnShow")
            list:SetScript("OnShow", function()
                if previousOnShow then previousOnShow() end
                PositionLocalClockSubmenu(hookedLevel)
            end)
            list.LocalClockPositionHooked = true
        end
    end
end

local function ShowMenu(anchorName)
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then
        Print("menu not available on this client; use /clock for commands.")
        return
    end
    if not menu then
        menu = CreateFrame("Frame", "LocalClockMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menu, InitMenu, "MENU")
    local anchor = anchorName or "LocalClockDisplayFrame"
    if anchor == "LocalClockDisplayFrame" then
        local button = getglobal and getglobal("LocalClockMinimapButton")
        if button and button.IsShown and button:IsShown() then
            anchor = "LocalClockMinimapButton"
        end
    end
    ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
    PositionLocalClockMenu(anchor)
    HookLocalClockSubmenus()
end

-- Classic addon bubble attached to the minimap. The whole button is one
-- named frame: its artwork, hit area, tooltip and click behavior move together.
local function UpdateMinimapButtonPosition()
    if not minimapButton or not Minimap then return end
    local angle = tonumber(LocalClockDB and LocalClockDB.minimapButtonAngle) or 45
    local radius = (Minimap:GetWidth() * 0.5) + 8
    local radians = math.rad(angle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(radians) * radius, math.sin(radians) * radius)
end

local function SaveMinimapButtonAngle()
    if not minimapButton or not Minimap or not minimapButton.GetCenter then return end
    local centerX, centerY = Minimap:GetCenter()
    local buttonX, buttonY = minimapButton:GetCenter()
    if not centerX or not centerY or not buttonX or not buttonY then return end

    -- Both frames share the minimap's coordinate space. Using the button's
    -- final center avoids the post-drag snap caused by measuring cursor offset.
    local angle = math.deg(math.atan2(buttonY - centerY, buttonX - centerX))
    if LocalClockDB then LocalClockDB.minimapButtonAngle = angle end
    UpdateMinimapButtonPosition()
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    minimapButton = CreateFrame("Button", "LocalClockMinimapButton", Minimap)
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    if minimapButton.SetFrameLevel and Minimap.GetFrameLevel then
        minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    end
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    -- A single self-contained circular button graphic. The gold ring and
    -- clock face are part of the same alpha-masked texture, so there is no
    -- separate minimap background or offset tracking-border layer to misalign.
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\LocalClock\\Textures\\LocalClockButton.tga")
    icon:SetWidth(30)
    icon:SetHeight(30)
    icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)

    minimapButton:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
        GameTooltip:SetText("LocalClock")
        GameTooltip:AddLine("Left-click: Clock tools", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Clock settings", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag: Move button around minimap", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    minimapButton:SetScript("OnMouseDown", function()
        -- A new press starts a fresh click/drag gesture.
        if not minimapButton.isDragging then minimapButton.draggedForClick = nil end
    end)
    minimapButton:SetScript("OnClick", function()
        if minimapButton.draggedForClick then
            minimapButton.draggedForClick = nil
            return
        end
        if arg1 == "RightButton" then
            ShowMenu("LocalClockMinimapButton")
        elseif arg1 == "LeftButton" then
            CreateToolsPanel()
            toolsPanel:Show()
        end
    end)
    minimapButton:SetScript("OnDragStart", function()
        -- Shift-drag is reserved for placement so an ordinary left-click
        -- continues to open the tools panel.
        if IsShiftKeyDown and IsShiftKeyDown() then
            minimapButton.isDragging = true
            minimapButton.draggedForClick = true
            minimapButton:StartMoving()
        end
    end)
    minimapButton:SetScript("OnDragStop", function()
        if minimapButton.isDragging then
            minimapButton:StopMovingOrSizing()
            minimapButton.isDragging = nil
            SaveMinimapButtonAngle()
        end
    end)

    UpdateMinimapButtonPosition()
    ApplyNativeClockFrameVisibility()
end

-- "Your time" panel: big clock, UTC offset slider, 12/24 hour switch.
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }
local FONT = "Fonts\\FRIZQT__.TTF"

local function OffsetLabel(o)
    if o == 0 then return "UTC" end
    if o > 0 then return "UTC+" .. o end
    return "UTC" .. o
end

local function MakeTextButton(parent, name, text, size, onClick)
    local b = CreateFrame("Button", name, parent)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size)
    fs:SetText(text)
    fs:SetTextColor(GREY[1], GREY[2], GREY[3])
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.fs = fs
    b:SetWidth((fs:GetStringWidth() or 20) + 10)
    b:SetHeight(size + 8)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(GREY[1], GREY[2], GREY[3])
        if UpdatePanel then UpdatePanel() end
    end)
    return b
end

local function SetCustomOffset(value)
    value = math.floor(value + 0.5)
    if value < MIN_OFFSET then value = MIN_OFFSET end
    if value > MAX_OFFSET then value = MAX_OFFSET end
    LocalClockDB.zone = "custom"
    LocalClockDB.customOffset = value
    RefreshAlarmForZoneChange()
    UpdateClock()
end

UpdatePanel = function()
    if not panel or not panel:IsShown() then return end
    panelTime:SetText(GetClockText())
    local ok, t = pcall(date, "*t")
    if ok and type(t) == "table" then
        local offset, zoneLabel = GetOffset(t)
        if LocalClockDB.zone == "local" and ReadGameLocalTime() then
            panelZone:SetText("Game Local Time  (game-language format)")
            offset = 0
        elseif LocalClockDB.zone == "custom" then
            panelZone:SetText(OffsetLabel(offset))
        else
            panelZone:SetText(zoneLabel .. "  (" .. OffsetLabel(offset) .. ")")
        end
        if panelSlider:GetValue() ~= offset then
            syncingSlider = true
            panelSlider:SetValue(offset)
            syncingSlider = false
        end
    end
    local c24, c12 = GOLD, GREY
    if IsClockUsing12Hour() then c24, c12 = GREY, GOLD end
    panel24.fs:SetTextColor(c24[1], c24[2], c24[3])
    panel12.fs:SetTextColor(c12[1], c12[2], c12[3])
end

local function CreatePanel()
    if panel then return end
    panel = CreateFrame("Frame", "LocalClockOptions", UIParent)
    panel:SetWidth(260)
    panel:SetHeight(160)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    panel:SetScript("OnShow", function() UpdatePanel() end)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
    -- Escape closes the panel.
    if UISpecialFrames then table.insert(UISpecialFrames, "LocalClockOptions") end

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 13)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetText("Your time")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)

    local close = MakeTextButton(panel, "LocalClockOptionsClose", "x", 13, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -5)
    local more = MakeTextButton(panel, "LocalClockOptionsMore", "more...", 11, function()
        ShowMenu("LocalClockOptionsMore")
    end)
    more:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local tools = MakeTextButton(panel, "LocalClockOptionsTools", "tools...", 11, function()
        CreateToolsPanel()
        toolsPanel:Show()
    end)
    tools:SetPoint("RIGHT", more, "LEFT", -4, 0)

    panelTime = panel:CreateFontString(nil, "OVERLAY")
    panelTime:SetFont(FONT, 34)
    panelTime:SetTextColor(1, 1, 1)
    panelTime:SetPoint("TOP", panel, "TOP", 0, -32)

    panelZone = panel:CreateFontString(nil, "OVERLAY")
    panelZone:SetFont(FONT, 11)
    panelZone:SetTextColor(0.75, 0.75, 0.75)
    panelZone:SetPoint("TOP", panelTime, "BOTTOM", 0, -6)

    panelSlider = CreateFrame("Slider", "LocalClockOffsetSlider", panel, "OptionsSliderTemplate")
    panelSlider:SetWidth(190)
    panelSlider:SetHeight(16)
    panelSlider:SetPoint("TOP", panelZone, "BOTTOM", 0, -12)
    panelSlider:SetMinMaxValues(MIN_OFFSET, MAX_OFFSET)
    panelSlider:SetValueStep(1)
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local fs = getglobal and getglobal("LocalClockOffsetSlider" .. suffix)
        if fs then fs:SetText("") end
    end
    panelSlider:SetScript("OnValueChanged", function()
        if syncingSlider then return end
        SetCustomOffset(panelSlider:GetValue())
    end)

    local minus = MakeTextButton(panel, "LocalClockOptionsMinus", "-", 14, function()
        SetCustomOffset(panelSlider:GetValue() - 1)
    end)
    minus:SetPoint("RIGHT", panelSlider, "LEFT", -2, 0)
    local plus = MakeTextButton(panel, "LocalClockOptionsPlus", "+", 14, function()
        SetCustomOffset(panelSlider:GetValue() + 1)
    end)
    plus:SetPoint("LEFT", panelSlider, "RIGHT", 2, 0)

    panel24 = MakeTextButton(panel, "LocalClockOptions24", "24 hours", 13, function()
        LocalClockDB.use12Hour = false
        if LocalClockDB.zone == "local" then LocalClockDB.localFormat = "24h" end
        UpdateClock()
    end)
    panel24:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 10)
    panel12 = MakeTextButton(panel, "LocalClockOptions12", "12 hours", 13, function()
        LocalClockDB.use12Hour = true
        if LocalClockDB.zone == "local" then LocalClockDB.localFormat = "12h" end
        UpdateClock()
    end)
    panel12:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 6, 10)

    panel:Hide()
end

local function SetButtonLabel(button, text)
    if not button or not button.fs then return end
    button.fs:SetText(text)
    button:SetWidth((button.fs:GetStringWidth() or 24) + 12)
end

UpdateToolsPanel = function()
    if not toolsPanel or not toolsPanel:IsShown() then return end
    local mode = LocalClockDB and LocalClockDB.displayMode or "clock"
    if toolsModeLabel then
        if mode == "stopwatch" then
            toolsModeLabel:SetText("Display: Stopwatch")
        elseif mode == "alarm" then
            toolsModeLabel:SetText("Display: Alarm countdown")
        else
            toolsModeLabel:SetText("Display: Time zone clock")
        end
    end

    if mode == "stopwatch" then
        toolsStopwatchAction:Show()
        toolsStopwatchReset:Show()
    else
        toolsStopwatchAction:Hide()
        toolsStopwatchReset:Hide()
    end
    if mode == "alarm" then
        alarmHourBox:Show()
        alarmMinuteBox:Show()
        alarmSetButton:Show()
        alarmCancelButton:Show()
    else
        alarmHourBox:Hide()
        alarmMinuteBox:Hide()
        alarmSetButton:Hide()
        alarmCancelButton:Hide()
    end

    if stopwatchRunning then
        SetButtonLabel(toolsStopwatchAction, "Pause")
    else
        SetButtonLabel(toolsStopwatchAction, "Start")
    end

    if mode == "stopwatch" then
        toolsStatus:SetText("Elapsed: " .. FormatDuration(stopwatchElapsed))
    elseif mode == "alarm" then
        if LocalClockDB and LocalClockDB.alarmFired then
            toolsStatus:SetText("Alarm is ringing. Press Dismiss to stop it.")
            SetButtonLabel(alarmCancelButton, "Dismiss")
        elseif LocalClockDB and LocalClockDB.alarmTimestamp and time then
            local remaining = LocalClockDB.alarmTimestamp - time()
            if remaining < 0 then remaining = 0 end
            local h = LocalClockDB.alarmHour or 0
            local m = LocalClockDB.alarmMinute or 0
            local suffix = ""
            local displayHour = h
            if LocalClockDB.use12Hour then
                suffix = (h >= 12) and " PM" or " AM"
                displayHour = Mod(h, 12)
                if displayHour == 0 then displayHour = 12 end
            end
            toolsStatus:SetText("Alarm at " .. string.format("%02d:%02d", displayHour, m) .. suffix ..
                "  |  in " .. FormatDuration(remaining))
            SetButtonLabel(alarmCancelButton, "Cancel")
        else
            toolsStatus:SetText("Enter alarm time as 24-hour HH:MM in your configured zone.")
            SetButtonLabel(alarmCancelButton, "Cancel")
        end
    else
        toolsStatus:SetText("Choose Clock, Stopwatch, or Alarm for the second display.")
    end
end

local function SaveToolsPanelPosition()
    if not toolsPanel or not LocalClockDB then return end
    local point, relativeTo, relativePoint, x, y = toolsPanel:GetPoint(1)
    if not point then return end

    LocalClockDB.toolsPanelPoint = point
    LocalClockDB.toolsPanelRelativePoint = relativePoint or point
    LocalClockDB.toolsPanelX = x or 0
    LocalClockDB.toolsPanelY = y or 0
    LocalClockDB.toolsPanelRelativeToName = nil
    if relativeTo and relativeTo ~= UIParent and relativeTo.GetName then
        LocalClockDB.toolsPanelRelativeToName = relativeTo:GetName()
    end
end

local function RestoreToolsPanelPosition()
    if not toolsPanel then return end
    toolsPanel:ClearAllPoints()

    if LocalClockDB and LocalClockDB.toolsPanelPoint then
        local relativeTo = UIParent
        if LocalClockDB.toolsPanelRelativeToName and getglobal then
            relativeTo = getglobal(LocalClockDB.toolsPanelRelativeToName) or UIParent
        end
        toolsPanel:SetPoint(
            LocalClockDB.toolsPanelPoint,
            relativeTo,
            LocalClockDB.toolsPanelRelativePoint or LocalClockDB.toolsPanelPoint,
            LocalClockDB.toolsPanelX or 0,
            LocalClockDB.toolsPanelY or 0
        )
    else
        -- Preserve the existing default for first-time installations.
        toolsPanel:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

CreateToolsPanel = function()
    if toolsPanel then return end
    toolsPanel = CreateFrame("Frame", "LocalClockToolsPanel", UIParent)
    toolsPanel:SetWidth(292)
    toolsPanel:SetHeight(190)
    RestoreToolsPanelPosition()
    toolsPanel:SetFrameStrata("DIALOG")
    toolsPanel:SetMovable(true)
    toolsPanel:EnableMouse(true)
    toolsPanel:RegisterForDrag("LeftButton")
    toolsPanel:SetClampedToScreen(true)
    toolsPanel:SetScript("OnDragStart", function() toolsPanel:StartMoving() end)
    toolsPanel:SetScript("OnDragStop", function()
        toolsPanel:StopMovingOrSizing()
        SaveToolsPanelPosition()
    end)
    toolsPanel:SetScript("OnShow", function() UpdateToolsPanel() end)
    if toolsPanel.SetBackdrop then
        toolsPanel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        toolsPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.94)
        toolsPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "LocalClockToolsPanel") end

    local title = toolsPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 13)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetText("LocalClock tools")
    title:SetPoint("TOPLEFT", toolsPanel, "TOPLEFT", 12, -10)
    local close = MakeTextButton(toolsPanel, "LocalClockToolsClose", "x", 13, function() toolsPanel:Hide() end)
    close:SetPoint("TOPRIGHT", toolsPanel, "TOPRIGHT", -8, -6)

    toolsClockButton = MakeTextButton(toolsPanel, "LocalClockToolsClock", "Clock", 12,
        function() SetDisplayMode("clock") end)
    toolsClockButton:SetPoint("TOPLEFT", toolsPanel, "TOPLEFT", 18, -35)
    toolsStopwatchButton = MakeTextButton(toolsPanel, "LocalClockToolsStopwatch", "Stopwatch", 12,
        function() SetDisplayMode("stopwatch") end)
    toolsStopwatchButton:SetPoint("LEFT", toolsClockButton, "RIGHT", 14, 0)
    toolsAlarmButton = MakeTextButton(toolsPanel, "LocalClockToolsAlarm", "Alarm", 12,
        function() SetDisplayMode("alarm") end)
    toolsAlarmButton:SetPoint("LEFT", toolsStopwatchButton, "RIGHT", 14, 0)

    toolsModeLabel = toolsPanel:CreateFontString(nil, "OVERLAY")
    toolsModeLabel:SetFont(FONT, 11)
    toolsModeLabel:SetTextColor(0.8, 0.8, 0.8)
    toolsModeLabel:SetPoint("TOP", toolsPanel, "TOP", 0, -62)

    toolsStopwatchAction = MakeTextButton(toolsPanel, "LocalClockStopwatchAction", "Start", 13, function()
        if stopwatchRunning then
            SetStopwatchRunning(false)
        else
            SetStopwatchRunning(true)
        end
    end)
    toolsStopwatchAction:SetPoint("TOP", toolsPanel, "TOP", -38, -86)
    toolsStopwatchReset = MakeTextButton(toolsPanel, "LocalClockStopwatchReset", "Reset", 13, function()
        ResetStopwatch()
    end)
    toolsStopwatchReset:SetPoint("LEFT", toolsStopwatchAction, "RIGHT", 16, 0)

    alarmHourBox = CreateFrame("EditBox", "LocalClockAlarmHour", toolsPanel, "InputBoxTemplate")
    alarmHourBox:SetWidth(34)
    alarmHourBox:SetHeight(22)
    alarmHourBox:SetPoint("TOP", toolsPanel, "TOP", -104, -87)
    alarmHourBox:SetAutoFocus(false)
    if alarmHourBox.SetNumeric then alarmHourBox:SetNumeric(true) end
    if alarmHourBox.SetMaxLetters then alarmHourBox:SetMaxLetters(2) end
    if alarmHourBox.SetJustifyH then alarmHourBox:SetJustifyH("CENTER") end
    alarmHourBox:SetText("14")

    local separator = toolsPanel:CreateFontString(nil, "OVERLAY")
    separator:SetFont(FONT, 14)
    separator:SetText(":")
    separator:SetPoint("LEFT", alarmHourBox, "RIGHT", 1, 0)
    alarmMinuteBox = CreateFrame("EditBox", "LocalClockAlarmMinute", toolsPanel, "InputBoxTemplate")
    alarmMinuteBox:SetWidth(34)
    alarmMinuteBox:SetHeight(22)
    alarmMinuteBox:SetPoint("LEFT", separator, "RIGHT", 2, 0)
    alarmMinuteBox:SetAutoFocus(false)
    if alarmMinuteBox.SetNumeric then alarmMinuteBox:SetNumeric(true) end
    if alarmMinuteBox.SetMaxLetters then alarmMinuteBox:SetMaxLetters(2) end
    if alarmMinuteBox.SetJustifyH then alarmMinuteBox:SetJustifyH("CENTER") end
    alarmMinuteBox:SetText("00")

    alarmSetButton = MakeTextButton(toolsPanel, "LocalClockAlarmSet", "Set alarm", 12, function()
        local ok, err = SetAlarmAt(alarmHourBox:GetText(), alarmMinuteBox:GetText())
        if ok then
            Print("alarm set for " .. tostring(LocalClockDB.alarmHour) .. ":" .. string.format("%02d", LocalClockDB.alarmMinute) ..
                " in your configured time zone.")
        else
            Print(err or "Unable to set alarm.")
        end
        UpdateToolsPanel()
    end)
    alarmSetButton:SetPoint("LEFT", alarmMinuteBox, "RIGHT", 10, 0)
    alarmCancelButton = MakeTextButton(toolsPanel, "LocalClockAlarmCancel", "Cancel", 12, function()
        if LocalClockDB and LocalClockDB.alarmFired then
            DismissAlarm()
        else
            CancelAlarm()
        end
        UpdateToolsPanel()
    end)
    alarmCancelButton:SetPoint("LEFT", alarmSetButton, "RIGHT", 8, 0)

    toolsStatus = toolsPanel:CreateFontString(nil, "OVERLAY")
    toolsStatus:SetFont(FONT, 10)
    toolsStatus:SetTextColor(0.8, 0.8, 0.8)
    toolsStatus:SetWidth(260)
    toolsStatus:SetJustifyH("CENTER")
    toolsStatus:SetPoint("BOTTOM", toolsPanel, "BOTTOM", 0, 15)

    toolsPanel:Hide()
end

local function TogglePanel()
    CreatePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

local function CreateClock()
    if frame then return end
    CreateNativeClockFrame()

    -- Keep LocalClock independently visible/movable while anchoring its
    -- default position to the native minimap-clock surround.
    frame = CreateFrame("Frame", "LocalClockDisplayFrame", UIParent)
    frame:SetWidth(110)
    frame:SetHeight(28)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
    end

    label = frame:CreateFontString("LocalClockText", "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", frame, "CENTER", 0, 0)
    label:SetTextColor(1, 0.9, 0.65)

    frame:SetScript("OnDragStart", function()
        if not moveUIOwnsClock and not (LocalClockDB and LocalClockDB.locked) and frame.StartMoving then frame:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        if not moveUIOwnsClock then
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            SavePosition()
        end
    end)
    frame:SetScript("OnUpdate", function()
        elapsed = elapsed + (arg1 or 0)
        if elapsed >= 0.5 then
            elapsed = elapsed - 0.5
            colonVisible = not colonVisible
            UpdateClock()
        end
    end)
    frame:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then ShowMenu("LocalClockDisplayFrame") end
    end)

    RestorePosition()
    UpdateMinimapScale()
    UpdateDragOwnership()
    -- Initial sizing happens after LocalClock's own display has been created.
    pcall(UpdateNativeClockFrameSize)
    CreateMinimapButton()
    StartWatcher()
    UpdateMinimapVisibility()
    ApplyClockVisibility()
    UpdateClock()
end

SLASH_LOCALCLOCK1 = "/localclock"
SLASH_LOCALCLOCK2 = "/clock"
SlashCmdList["LOCALCLOCK"] = function(message)
    local command = string.lower(message or "")
    local zoneArg = string.gsub(command, "^zone%s+", "")
    if command == "hide" then
        SetShown(false)
        Print("hidden. Use /clock show or the menu toggle to display it.")
    elseif command == "show" then
        SetShown(true)
        Print("shown.")
    elseif command == "toggle" then
        SetShown(not shown)
        Print(shown and "shown." or "hidden.")
    elseif command == "menu" then
        ShowMenu()
    elseif command == "tools" then
        CreateToolsPanel()
        toolsPanel:Show()
    elseif command == "mode clock" then
        SetDisplayMode("clock")
    elseif command == "mode stopwatch" then
        SetDisplayMode("stopwatch")
    elseif command == "mode alarm" then
        SetDisplayMode("alarm")
    elseif command == "stopwatch start" then
        SetStopwatchRunning(true)
    elseif command == "stopwatch pause" then
        SetStopwatchRunning(false)
    elseif command == "stopwatch reset" then
        ResetStopwatch()
    elseif string.find(command, "^alarm%s+set%s+") then
        local value = string.gsub(command, "^alarm%s+set%s+", "")
        local _, _, hourText, minuteText = string.find(value, "^(%d+):(%d+)$")
        local ok, err = SetAlarmAt(hourText, minuteText)
        if ok then
            Print("alarm set for " .. string.format("%02d:%02d", LocalClockDB.alarmHour, LocalClockDB.alarmMinute) ..
                " in your configured time zone.")
        else
            Print(err or "example: /clock alarm set 14:00")
        end
    elseif command == "alarm cancel" or command == "alarm dismiss" then
        if LocalClockDB and LocalClockDB.alarmFired then DismissAlarm() else CancelAlarm() end
        Print("alarm cleared.")
    elseif command == "12h" then
        LocalClockDB.use12Hour = true
        if LocalClockDB.zone == "local" then LocalClockDB.localFormat = "12h" end
        UpdateClock()
        Print("using 12-hour time.")
    elseif command == "24h" then
        LocalClockDB.use12Hour = false
        if LocalClockDB.zone == "local" then LocalClockDB.localFormat = "24h" end
        UpdateClock()
        Print("using 24-hour time.")
    elseif string.find(command, "^zone%s+") then
        if zoneArg == "eastern european" or zoneArg == "eastern-european" or zoneArg == "european" then
            zoneArg = "eet"
        elseif zoneArg == "central european" or zoneArg == "central-european" or zoneArg == "cest" or zoneArg == "prague" then
            zoneArg = "cet"
        end
        if zones[zoneArg] then
            LocalClockDB.zone = zoneArg
            RefreshAlarmForZoneChange()
            UpdateClock()
            if zoneArg == "local" then
                Print("time zone set to Game Local Time; the game language controls the default 12/24-hour format.")
            elseif zones[zoneArg].eu then
                local ok, t = pcall(date, "*t")
                if ok and type(t) == "table" then
                    local offset, activeLabel = GetOffset(t)
                    local sign = ""
                    if offset >= 0 then sign = "+" end
                    Print("time zone set to " .. activeLabel .. " (UTC" .. sign .. tostring(offset) .. "); switches automatically for European summer time.")
                else
                    Print("time zone set to " .. zones[zoneArg].label .. "; switches automatically for European summer time.")
                end
            else
                Print("time zone set to " .. zones[zoneArg].label .. ".")
            end
        else
            Print("unknown zone. Options: local, eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, eet.")
            Print("example: /clock zone eet (automatically switches between EET and EEST)")
        end
    elseif command == "zone" then
        local current = LocalClockDB.zone or "local"
        if current == "local" then
            Print("current zone: Game Local Time (device clock; game-language format by default).")
        elseif current == "custom" then
            Print("current zone: " .. OffsetLabel(LocalClockDB.customOffset or 0) .. " (set with the slider or /clock offset).")
        elseif zones[current] and zones[current].eu then
            local ok, t = pcall(date, "*t")
            if ok and type(t) == "table" then
                local offset, activeLabel = GetOffset(t)
                local sign = ""
                if offset >= 0 then sign = "+" end
                Print("current zone: " .. activeLabel .. " (UTC" .. sign .. tostring(offset) .. ").")
            else
                Print("current zone: " .. zones[current].label .. ".")
            end
            Print("European zones switch automatically for European summer time.")
        else
            Print("current zone: " .. (zones[current] and zones[current].label or "Eastern") .. ".")
        end
        Print("set with /clock zone local, eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, or eet.")
    elseif command == "options" or command == "config" then
        CreatePanel()
        panel:Show()
    elseif string.find(command, "^offset%s+") then
        local n = tonumber((string.gsub(command, "^offset%s+", "")))
        if n then
            SetCustomOffset(n)
            RefreshAlarmForZoneChange()
            Print("time zone set to " .. OffsetLabel(LocalClockDB.customOffset) .. " (no automatic summer time).")
        else
            Print("example: /clock offset 1   or   /clock offset -5")
        end
    elseif command == "lock" then
        LocalClockDB.locked = true
        Print("position locked.")
    elseif command == "unlock" then
        LocalClockDB.locked = false
        Print("position unlocked.")
    elseif command == "reset" then
        LocalClockDB.minimapButtonAngle = 45
        UpdateMinimapButtonPosition()
        LocalClockDB.point = nil
        LocalClockDB.relativePoint = nil
        LocalClockDB.x = nil
        LocalClockDB.y = nil
        LocalClockDB.relativeToName = nil
        local moveUIOpt = MoveAnything_FrameOptions and MoveAnything_FrameOptions["LocalClockDisplayFrame"]
        if moveUIRegistered and moveUIOpt and (moveUIOpt.movable or moveUIOpt.hidden) and MoveAnything_ResetFrameOptions then
            MoveAnything_ResetFrameOptions("LocalClockDisplayFrame")
        else
            RestorePosition()
            if nativeClockFrame then
                if frame.HiddenClearAllPoints then frame:HiddenClearAllPoints() else frame:ClearAllPoints() end
                if frame.HiddenSetPoint then
                    frame:HiddenSetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * appliedMinimapScale)
                else
                    frame:SetPoint("TOP", nativeClockFrame, "BOTTOM", 0, -4 * appliedMinimapScale)
                end
            end
        end
        Print("position reset.")
    elseif command == "debug" then
        local ok, t = pcall(date, "*t")
        if ok and type(t) == "table" then
            local offset, zoneLabel = GetOffset(t)
            Print(string.format("UTC date(*t): %04d-%02d-%02d %02d:%02d:%02d; wday=%s",
                t.year or 0, t.month or 0, t.day or 0,
                t.hour or 0, t.min or 0, t.sec or 0, tostring(t.wday)))
            Print("selected zone: " .. zoneLabel .. "; applied UTC offset: " .. tostring(offset))
        else
            Print("date(*t): unavailable or failed")
        end
        if time then Print("time() timestamp: " .. tostring(time())) end
        if GetGameTime then
            local h, m = GetGameTime()
            Print("GetGameTime (realm): " .. tostring(h) .. ":" .. tostring(m))
        end
        Print("localClock API: AZS_GetLocalTime=" .. type(AZS_GetLocalTime) ..
            ", AZS_SetHudShown=" .. type(AZS_SetHudShown) ..
            ", AZS_IsHudShown=" .. type(AZS_IsHudShown))
        if type(AZS_IsHudShown) == "function" then
            local apiOK, apiValue = pcall(AZS_IsHudShown, "localClock")
            Print("AZS_IsHudShown(localClock): " ..
                (apiOK and tostring(apiValue) or "call failed: " .. tostring(apiValue)))
        end
        if type(GetCVar) == "function" then
            local cvarOK, cvarValue = pcall(GetCVar, "hudLocalClock")
            Print("hudLocalClock CVar: " ..
                (cvarOK and tostring(cvarValue) or "unavailable: " .. tostring(cvarValue)))
        else
            Print("hudLocalClock CVar: GetCVar unavailable")
        end
    else
        Print("Use the minimap bubble: left-click for tools, right-click for settings, Shift-drag to reposition it.")
        Print("Show Game Clock controls the native minimap clock; Show LocalClock controls the secondary display.")
        Print("commands: /clock options, tools, mode clock|stopwatch|alarm, show, hide, toggle, 12h, 24h, lock, unlock, reset, debug")
        Print("stopwatch: /clock stopwatch start|pause|reset")
        Print("alarm: /clock alarm set HH:MM, /clock alarm cancel")
        Print("time zones: /clock zone local, eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, eet")
        Print("US and EU daylight-saving transitions are calculated automatically for zones that observe them.")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not LocalClockDB then LocalClockDB = {} end
    local initialLocalTime = ReadGameLocalTime()
    if LocalClockDB.use12Hour == nil then
        if initialLocalTime then
            LocalClockDB.use12Hour = not initialLocalTime.is24Hour
        else
            LocalClockDB.use12Hour = true
        end
    end
    if LocalClockDB.zone == nil then
        if type(AZS_GetLocalTime) == "function" then
            LocalClockDB.zone = "local"
        else
            -- Preserve the historical first-install behavior on pre-0.136.0 clients.
            LocalClockDB.zone = "eastern"
        end
    end
    if LocalClockDB.localFormat == nil then LocalClockDB.localFormat = "game" end
    if LocalClockDB.minimapButtonAngle == nil then LocalClockDB.minimapButtonAngle = 45 end
    if LocalClockDB.shown == nil then LocalClockDB.shown = true end
    if LocalClockDB.displayMode == nil then LocalClockDB.displayMode = "clock" end
    stopwatchElapsed = tonumber(LocalClockDB.stopwatchElapsed) or 0
    -- A stopwatch does not accumulate time while the game is closed. It resumes paused.
    stopwatchRunning = false
    LocalClockDB.stopwatchRunning = false
    if LocalClockDB.alarmTimestamp and time and LocalClockDB.alarmTimestamp <= time() then
        LocalClockDB.alarmTimestamp = nil
        LocalClockDB.alarmFired = false
        LocalClockDB.alarmHour = nil
        LocalClockDB.alarmMinute = nil
    end
    shown = LocalClockDB.shown and true or false
    gameClockShown = GetGameClockShown()
    CreateClock()
    CreateAlarmWarningFrame()
end)
