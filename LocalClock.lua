-- LocalClock 1.0.5 for the legacy Azeroth Survivors client (Lua 5.0 style).
-- The game exposes UTC through date("*t") but not the os library, so named
-- US time zones are converted from UTC. US DST transitions are calculated.

local frame
local label
local elapsed = 0
local shown = true
local colonVisible = true
local moveUIOwnsClock = false
local ownershipCheckElapsed = 0

local zones = {
    eastern  = { standard = -5, dst = true,  label = "Eastern" },
    central  = { standard = -6, dst = true,  label = "Central" },
    mountain = { standard = -7, dst = true,  label = "Mountain" },
    pacific  = { standard = -8, dst = true,  label = "Pacific" },
    alaska   = { standard = -9, dst = true,  label = "Alaska" },
    hawaii   = { standard = -10, dst = false, label = "Hawaii" },
    arizona  = { standard = -7, dst = false, label = "Arizona" },
    utc      = { standard = 0, dst = false, label = "UTC" }
}

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

local function IsUSDaylightTime(t)
    if not t.month or not t.day or not t.hour or not t.wday then return false end
    if t.month < 3 or t.month > 11 then return false end
    if t.month > 3 and t.month < 11 then return true end

    if t.month == 3 then
        local first = FirstSunday(t.year, 3, t)
        local second = first + 7
        if t.day > second then return true end
        if t.day < second then return false end
        return t.hour >= 7 -- 02:00 EST = 07:00 UTC
    end

    local first = FirstSunday(t.year, 11, t)
    if t.day < first then return true end
    if t.day > first then return false end
    return t.hour < 6 -- 02:00 EDT = 06:00 UTC
end

local function GetOffset(t)
    local zoneName = "eastern"
    if LocalClockDB and LocalClockDB.zone then zoneName = LocalClockDB.zone end
    local zone = zones[zoneName] or zones.eastern
    local offset = zone.standard
    if zone.dst and IsUSDaylightTime(t) then offset = offset + 1 end
    return offset, zone.label
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

local function GetClockText()
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
        return string.format("%02d%s%02d %s", hour, colon, minute, suffix)
    end
    return string.format("%02d%s%02d", hour, colon, minute)
end

local function UpdateClock()
    if label then label:SetText(GetClockText()) end
end

local function SavePosition()
    if not frame or not LocalClockDB then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    LocalClockDB.point = point or "CENTER"
    LocalClockDB.relativePoint = relativePoint or "CENTER"
    LocalClockDB.x = x or 0
    LocalClockDB.y = y or 0
end

local function RestorePosition()
    if not frame then return end
    frame:ClearAllPoints()
    if LocalClockDB and LocalClockDB.point then
        frame:SetPoint(LocalClockDB.point, UIParent, LocalClockDB.relativePoint or LocalClockDB.point,
            LocalClockDB.x or 0, LocalClockDB.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLocalClock:|r " .. message)
    end
end

local function SetShown(value)
    shown = value
    if frame then
        if shown then frame:Show() else frame:Hide() end
    end
end

-- Move UI owns positioning after its addon has initialized and registered this frame.
-- Keep standalone dragging available when Move UI is absent.
local function UpdateDragOwnership()
    local useMoveUI = MoveAnything_InitRun and MoveAnything_FindFrame and
        MoveAnything_FindFrame("LocalClockFrame") ~= nil
    if useMoveUI == moveUIOwnsClock then return end
    moveUIOwnsClock = useMoveUI
    if not frame then return end
    if moveUIOwnsClock then
        frame:SetScript("OnDragStart", function() end)
        frame:SetScript("OnDragStop", function() end)
        Print("Move UI detected; clock positioning is controlled by Move UI.")
    else
        frame:SetScript("OnDragStart", function()
            if frame.StartMoving then frame:StartMoving() end
        end)
        frame:SetScript("OnDragStop", function()
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            SavePosition()
        end)
    end
end

local function CreateClock()
    if frame then return end
    frame = CreateFrame("Frame", "LocalClockFrame", UIParent)
    frame:SetWidth(110)
    frame:SetHeight(28)
    frame:SetFrameStrata("MEDIUM")
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
        if not moveUIOwnsClock and frame.StartMoving then frame:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        if not moveUIOwnsClock then
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            SavePosition()
        end
    end)
    frame:SetScript("OnUpdate", function()
        ownershipCheckElapsed = ownershipCheckElapsed + (arg1 or 0)
        if ownershipCheckElapsed >= 1 then
            ownershipCheckElapsed = 0
            UpdateDragOwnership()
        end
        elapsed = elapsed + (arg1 or 0)
        if elapsed >= 0.5 then
            elapsed = elapsed - 0.5
            colonVisible = not colonVisible
            UpdateClock()
        end
    end)

    RestorePosition()
    UpdateDragOwnership()
    UpdateClock()
end

SLASH_LOCALCLOCK1 = "/localclock"
SLASH_LOCALCLOCK2 = "/clock"
SlashCmdList["LOCALCLOCK"] = function(message)
    local command = string.lower(message or "")
    local zoneArg = string.gsub(command, "^zone%s+", "")

    if command == "hide" then
        SetShown(false)
        Print("hidden. Use /clock show to display it.")
    elseif command == "show" then
        SetShown(true)
        Print("shown.")
    elseif command == "toggle" then
        SetShown(not shown)
        Print(shown and "shown." or "hidden.")
    elseif command == "12h" then
        LocalClockDB.use12Hour = true
        UpdateClock()
        Print("using 12-hour time.")
    elseif command == "24h" then
        LocalClockDB.use12Hour = false
        UpdateClock()
        Print("using 24-hour time.")
    elseif string.find(command, "^zone%s+") then
        if zones[zoneArg] then
            LocalClockDB.zone = zoneArg
            UpdateClock()
            Print("time zone set to " .. zones[zoneArg].label .. ".")
        else
            Print("unknown zone. Options: eastern, central, mountain, pacific, alaska, arizona, hawaii, utc.")
            Print("example: /clock zone eastern")
        end
    elseif command == "zone" then
        local current = LocalClockDB.zone or "eastern"
        Print("current zone: " .. (zones[current] and zones[current].label or "Eastern") .. ".")
        Print("set with /clock zone eastern, central, mountain, pacific, alaska, arizona, hawaii, or utc.")
    elseif command == "reset" then
        LocalClockDB.point = nil
        LocalClockDB.relativePoint = nil
        LocalClockDB.x = nil
        LocalClockDB.y = nil
        RestorePosition()
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
    else
        Print("drag the clock with the left mouse button to move it.")
        Print("commands: /clock show, hide, toggle, 12h, 24h, reset, debug")
        Print("time zones: /clock zone eastern (or central, mountain, pacific, alaska, arizona, hawaii, utc)")
        Print("US DST is calculated automatically for Eastern, Central, Mountain, Pacific, and Alaska.")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not LocalClockDB then LocalClockDB = {} end
    if LocalClockDB.use12Hour == nil then LocalClockDB.use12Hour = true end
    if LocalClockDB.zone == nil then LocalClockDB.zone = "eastern" end
    CreateClock()
end)
