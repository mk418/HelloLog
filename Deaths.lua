local HL = HelloLog
local Deaths = {}
HL.Deaths = Deaths

local OBJECT_TYPE_NPC  = COMBATLOG_OBJECT_TYPE_NPC      or 0x00000800
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040

local INCOMING_DAMAGE = {
    SWING_DAMAGE          = true,
    RANGE_DAMAGE          = true,
    SPELL_DAMAGE          = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true,
    ENVIRONMENTAL_DAMAGE  = true,
}

local lastAttacker
local playerGUID

local function isHostileNPC(flags)
    if not flags then return false end
    return bit.band(flags, OBJECT_TYPE_NPC) ~= 0
        and bit.band(flags, REACTION_HOSTILE) ~= 0
end

local function recordDeath()
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess then return end
    sess.deaths = sess.deaths or {}
    local zone = GetRealZoneText()
    if not zone or zone == "" then zone = "Unknown" end
    sess.deaths[#sess.deaths + 1] = {
        time = time(),
        zone = zone,
        killer = lastAttacker,
    }
    lastAttacker = nil
    HL.UI:Refresh()
end

function Deaths:Init()
    playerGUID = UnitGUID("player")
    HL:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        playerGUID = UnitGUID("player")
    end)
    HL:RegisterEvent("PLAYER_ALIVE", function()
        lastAttacker = nil
    end)
    HL:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
        local _, subevent, _, _, sourceName, sourceFlags, _, destGUID = CombatLogGetCurrentEventInfo()
        if not subevent or destGUID ~= playerGUID then return end
        if INCOMING_DAMAGE[subevent] and sourceName and isHostileNPC(sourceFlags) then
            lastAttacker = sourceName
        end
    end)
    HL:RegisterEvent("PLAYER_DEAD", recordDeath)
end
