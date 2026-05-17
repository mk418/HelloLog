local ADDON_NAME = ...

HelloLog = HelloLog or {}
local HL = HelloLog

HL.version = "0.2.0"
HL.prefix = "|cFF66CCFFHelloLog|r: "

function HL:Print(msg)
    print(self.prefix .. msg)
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

function HL:RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

HL:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    HelloLogDB = HelloLogDB or {}
    HelloLogDB.sessions = HelloLogDB.sessions or {}
    HL.db = HelloLogDB

    HL.Session:Init()
    HL.Loot:Init()
    HL.Rep:Init()
    HL.Kills:Init()
    HL.Deaths:Init()
    HL.Consumables:Init()
    HL.UI:Init()
    HL.Minimap:Init()
    HL.Options:Init()
end)

SLASH_HELLOLOG1 = "/hl"
SLASH_HELLOLOG2 = "/hellolog"
SlashCmdList.HELLOLOG = function(msg)
    local cmd = strlower(strtrim(msg or ""))
    if cmd == "start" then
        HL.Session:Start()
    elseif cmd == "stop" then
        HL.Session:Stop()
    elseif cmd == "show" then
        HL.UI:Toggle()
    elseif cmd == "detail" or cmd == "details" then
        HL.UI:ToggleExpanded()
    elseif cmd == "reset" then
        HL.Session:Reset()
    elseif cmd == "resetpos" or cmd == "reset-pos" then
        HL.UI:ResetPosition()
        HL:Print("frame position reset.")
    elseif cmd == "wipe" or cmd == "clear" then
        HL.Session:Wipe()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        HL.Options:Open()
    elseif cmd == "minimap" then
        HL.Minimap:SetHidden(not HL.Minimap:IsHidden())
        HL:Print("minimap icon " .. (HL.Minimap:IsHidden() and "hidden." or "shown."))
    else
        HL:Print("commands: start | stop | show | detail | reset | resetpos | wipe | minimap | options")
    end
end
