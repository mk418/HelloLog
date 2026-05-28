local HL = HelloLog
local Kills = {}
HL.Kills = Kills

-- Affiliation: MINE | PARTY | RAID = 0x07
local GROUP_AFFILIATION_MASK = 0x00000007
local OBJECT_TYPE_NPC        = COMBATLOG_OBJECT_TYPE_NPC      or 0x00000800
-- Many farmable mobs (beasts, low-level humanoids) are flagged NEUTRAL until
-- they aggro. A wand crit or Firebolt that one-shots a neutral mob arrives
-- with REACTION_NEUTRAL, so HOSTILE-only matching dropped those kills.
local ATTACKABLE_REACTION_MASK = bit.bor(
    COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040,
    COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x00000020)

-- destGUIDs we (or any groupmate) have damaged in the current combat-log
-- range. Used to attribute UNIT_DIED back to the group, since UNIT_DIED
-- carries no source. Cleared on use to avoid unbounded growth in long fights.
local damaged = {}

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE          = true,
    RANGE_DAMAGE          = true,
    SPELL_DAMAGE          = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true,
    DAMAGE_SHIELD         = true,
    DAMAGE_SPLIT          = true,
}

local function isGroupSource(flags)
    if not flags then return false end
    return bit.band(flags, GROUP_AFFILIATION_MASK) ~= 0
end

local function isAttackableNPC(flags)
    if not flags then return false end
    return bit.band(flags, OBJECT_TYPE_NPC) ~= 0
        and bit.band(flags, ATTACKABLE_REACTION_MASK) ~= 0
end

local function recordKill(name)
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess then return end
    sess.perMob = sess.perMob or {}
    local per = sess.perMob[name]
    if not per then
        per = { items = {}, kills = 0 }
        sess.perMob[name] = per
    end
    per.kills = (per.kills or 0) + 1
    HL.UI:Refresh()
end

function Kills:Init()
    HL:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
        local _, subevent, _, _, _, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
        if not subevent or not destGUID then return end

        if DAMAGE_SUBEVENTS[subevent] then
            if isGroupSource(sourceFlags) and isAttackableNPC(destFlags) then
                damaged[destGUID] = true
            end
            return
        end

        if subevent == "UNIT_DIED" then
            if damaged[destGUID] and destName then
                damaged[destGUID] = nil
                recordKill(destName)
            end
        end
    end)
end
