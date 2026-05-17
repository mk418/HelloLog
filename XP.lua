local HL = HelloLog
local XP = {}
HL.XP = XP

local lastXP, lastLevel, lastMaxXP
local primed = false

local function escapePattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function patternify(template)
    local p = escapePattern(template)
    p = p:gsub("%%%%s", "(.+)")
    p = p:gsub("%%%%d", "(%%d+)")
    return p
end

-- Rested-bonus parentheticals from CHAT_MSG_COMBAT_XP_GAIN. The last
-- captured number in each pattern is the rested amount.
local RESTED_PATTERNS = {}
for _, key in ipairs({
    "COMBATLOG_XPGAIN_EXHAUSTION1",
    "COMBATLOG_XPGAIN_EXHAUSTION2",
    "COMBATLOG_XPGAIN_EXHAUSTION4",
    "COMBATLOG_XPGAIN_EXHAUSTION5",
}) do
    local s = _G[key]
    if s then RESTED_PATTERNS[#RESTED_PATTERNS + 1] = patternify(s) end
end

local function bucket()
    local sess = HL.Session:Current()
    if not sess then return nil end
    sess.xp = sess.xp or { total = 0, rested = 0, levelUps = {} }
    return sess.xp
end

local function recordDelta(delta)
    if delta <= 0 then return end
    if not HL.Session:IsRecording() then return end
    local xp = bucket()
    if not xp then return end
    xp.total = (xp.total or 0) + delta
    HL.UI:Refresh()
end

local function recordRested(amount)
    if not HL.Session:IsRecording() then return end
    local xp = bucket()
    if not xp then return end
    xp.rested = (xp.rested or 0) + amount
end

local function recordLevelUp(newLevel)
    if not HL.Session:IsRecording() then return end
    local xp = bucket()
    if not xp then return end
    xp.levelUps = xp.levelUps or {}
    xp.levelUps[#xp.levelUps + 1] = { time = time(), level = newLevel }
    HL.UI:Refresh()
end

local function snapshot()
    lastXP = UnitXP("player") or 0
    lastLevel = UnitLevel("player") or 1
    lastMaxXP = UnitXPMax("player") or 0
    primed = true
end

local function onXPUpdate()
    if not primed then
        snapshot()
        return
    end
    local curXP = UnitXP("player") or 0
    local curLevel = UnitLevel("player") or 1
    local curMaxXP = UnitXPMax("player") or 0

    local delta
    if curLevel == lastLevel then
        delta = curXP - lastXP
    else
        -- Level-up rollover: finish out the previous bar and add current XP.
        delta = (lastMaxXP - lastXP) + curXP
    end

    if delta and delta > 0 then
        recordDelta(delta)
    end

    lastXP = curXP
    lastLevel = curLevel
    lastMaxXP = curMaxXP
end

local function tryParseRested(msg)
    for _, p in ipairs(RESTED_PATTERNS) do
        local captures = { msg:match(p) }
        if #captures > 0 then
            local rested = tonumber(captures[#captures])
            if rested and rested > 0 then
                recordRested(rested)
                return
            end
        end
    end
end

function XP:Init()
    snapshot()
    HL:RegisterEvent("PLAYER_ENTERING_WORLD", snapshot)
    HL:RegisterEvent("PLAYER_XP_UPDATE", onXPUpdate)
    HL:RegisterEvent("PLAYER_LEVEL_UP", function(newLevel)
        recordLevelUp(tonumber(newLevel) or UnitLevel("player"))
    end)
    HL:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
        tryParseRested(msg)
    end)
end
