-- LocalClock 1.1.0 for the legacy Azeroth Survivors client (Lua 5.0 style).
-- The game exposes UTC through date("*t") but not the os library, so named
-- time zones are converted from UTC. US and EU DST transitions are calculated.

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
    utc      = { standard = 0, dst = false, label = "UTC" },
    cet      = { standard = 1, dst = true, eu = true, label = "CET", dstLabel = "CEST" },
    eet      = { standard = 2, dst = true, eu = true, label = "EET", dstLabel = "EEST" }
}
local panel, panelTime, panelZone, panelSlider, panel24, panel12
local syncingSlider = false
local UpdatePanel
local MIN_OFFSET, MAX_OFFSET = -12, 14
local zoneOrder = { "eastern", "central", "mountain", "pacific", "alaska", "arizona", "hawaii", "utc", "cet", "eet" }
local menu
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

local function GetOffset(t)
    local zoneName = "eastern"
    if LocalClockDB and LocalClockDB.zone then zoneName = LocalClockDB.zone end
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
        elseif IsUSDaylightTime(t) then
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
    if UpdatePanel then UpdatePanel() end
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
            if not (LocalClockDB and LocalClockDB.locked) and frame.StartMoving then frame:StartMoving() end
        end)
        frame:SetScript("OnDragStop", function()
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            SavePosition()
        end)
    end
end

-- Right-click options menu (standard UIDropDownMenu, available since vanilla).
local function RunCommand(cmd)
    SlashCmdList["LOCALCLOCK"](cmd)
    if CloseDropDownMenus then CloseDropDownMenus() end
end

local function AddMenuButton(info)
    if UIDropDownMenu_AddButton then UIDropDownMenu_AddButton(info, info.level) end
end

local function InitMenu(level)
    level = level or UIDROPDOWNMENU_MENU_LEVEL or 1
    local db = LocalClockDB or {}
    local info

    if level == 2 and UIDROPDOWNMENU_MENU_VALUE == "ZONE" then
        local current = db.zone or "eastern"
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
    AddMenuButton({ level = 1, text = "Time zone", hasArrow = 1, value = "ZONE", notCheckable = 1 })
    AddMenuButton({ level = 1, text = "12-hour", checked = db.use12Hour and 1 or nil,
        func = function() RunCommand("12h") end })
    AddMenuButton({ level = 1, text = "24-hour", checked = (not db.use12Hour) and 1 or nil,
        func = function() RunCommand("24h") end })
    AddMenuButton({ level = 1, text = "Lock position", checked = db.locked and 1 or nil,
        func = function() RunCommand(db.locked and "unlock" or "lock") end })
    AddMenuButton({ level = 1, text = "Reset position", notCheckable = 1,
        func = function() RunCommand("reset") end })
    AddMenuButton({ level = 1, text = "Hide clock (/clock show)", notCheckable = 1,
        func = function() RunCommand("hide") end })
    AddMenuButton({ level = 1, text = "Close", notCheckable = 1,
        func = function() if CloseDropDownMenus then CloseDropDownMenus() end end })
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
    ToggleDropDownMenu(1, nil, menu, anchorName or "LocalClockFrame", 0, 0)
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
    UpdateClock()
end

UpdatePanel = function()
    if not panel or not panel:IsShown() then return end
    panelTime:SetText(GetClockText())
    local ok, t = pcall(date, "*t")
    if ok and type(t) == "table" then
        local offset, zoneLabel = GetOffset(t)
        if LocalClockDB.zone == "custom" then
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
    if LocalClockDB.use12Hour then c24, c12 = GREY, GOLD end
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
        UpdateClock()
    end)
    panel24:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 10)
    panel12 = MakeTextButton(panel, "LocalClockOptions12", "12 hours", 13, function()
        LocalClockDB.use12Hour = true
        UpdateClock()
    end)
    panel12:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 6, 10)

    panel:Hide()
end

local function TogglePanel()
    CreatePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
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
        if not moveUIOwnsClock and not (LocalClockDB and LocalClockDB.locked) and frame.StartMoving then frame:StartMoving() end
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
    frame:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then TogglePanel() end
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
    elseif command == "menu" then
        ShowMenu()
    elseif command == "12h" then
        LocalClockDB.use12Hour = true
        UpdateClock()
        Print("using 12-hour time.")
    elseif command == "24h" then
        LocalClockDB.use12Hour = false
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
            UpdateClock()
            if zones[zoneArg].eu then
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
            Print("unknown zone. Options: eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, eet.")
            Print("example: /clock zone eet (automatically switches between EET and EEST)")
        end
    elseif command == "zone" then
        local current = LocalClockDB.zone or "eastern"
        if current == "custom" then
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
        Print("set with /clock zone eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, or eet.")
    elseif command == "options" or command == "config" then
        CreatePanel()
        panel:Show()
    elseif string.find(command, "^offset%s+") then
        local n = tonumber((string.gsub(command, "^offset%s+", "")))
        if n then
            SetCustomOffset(n)
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
        Print("drag the clock with the left mouse button to move it; right-click it for settings.")
        Print("commands: /clock options, offset <n>, menu, show, hide, toggle, 12h, 24h, lock, unlock, reset, debug")
        Print("time zones: /clock zone eastern, central, mountain, pacific, alaska, arizona, hawaii, utc, cet, eet")
        Print("US and EU daylight-saving transitions are calculated automatically for zones that observe them.")
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
