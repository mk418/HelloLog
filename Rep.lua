local HL = HelloLog
local Rep = {}
HL.Rep = Rep

local function escapePattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function patternify(template)
    local p = escapePattern(template)
    p = p:gsub("%%%%s", "(.+)")
    p = p:gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local INCREASED = patternify(FACTION_STANDING_INCREASED or "Your %s reputation has increased by %d.")
local DECREASED = patternify(FACTION_STANDING_DECREASED or "Your %s reputation has decreased by %d.")

local function recordRep(faction, delta)
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess then return end
    sess.factions = sess.factions or {}
    local bucket = sess.factions[faction]
    if not bucket then
        bucket = { delta = 0 }
        sess.factions[faction] = bucket
    end
    bucket.delta = bucket.delta + delta
    HL.UI:Refresh()
end

local function tryParse(msg)
    local faction, amount = msg:match(INCREASED)
    if faction and amount then
        recordRep(faction, tonumber(amount))
        return
    end
    faction, amount = msg:match(DECREASED)
    if faction and amount then
        recordRep(faction, -tonumber(amount))
        return
    end
end

function Rep:Init()
    HL:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
        tryParse(msg)
    end)
end
