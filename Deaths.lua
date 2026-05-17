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
-- PLAYER_DEAD can fire more than once for the same death (notably after
-- a /reload while still a corpse). Gate recording on a single alive->dead
-- transition; re-arm only when the player is actually alive again.
local dead = false

local function isHostileNPC(flags)
    if not flags then return false end
    return bit.band(flags, OBJECT_TYPE_NPC) ~= 0
        and bit.band(flags, REACTION_HOSTILE) ~= 0
end

-- A death drops 10% durability on every equipped item that has any.
-- The classic-era repair-cost-per-item at zero durability tracks the
-- item's vendor sell price closely enough for a useful approximation,
-- so we cost a death at 10% of the summed sell prices of equipped
-- gear. Stored alongside the death so we can recompute later if
-- GetItemInfo was cold-cache at death time.
local function snapshotEquipment()
    local eq = {}
    for slot = 1, 19 do
        local _, maxDur = GetInventoryItemDurability(slot)
        if maxDur and maxDur > 0 then
            local link = GetInventoryItemLink("player", slot)
            if link then
                eq[#eq + 1] = { link = link }
            end
        end
    end
    return eq
end

local function computeRepairCost(equipment)
    local total = 0
    if not equipment then return 0 end
    for _, item in ipairs(equipment) do
        local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(item.link)
        if sellPrice and sellPrice > 0 then
            total = total + math.floor(sellPrice * 0.10)
        end
    end
    return total
end

function Deaths:DeathRepairCost(death)
    if not death then return 0 end
    if (death.repairCost or 0) == 0 and death.equipment then
        death.repairCost = computeRepairCost(death.equipment)
    end
    return death.repairCost or 0
end

function Deaths:TotalRepairCost(sess)
    if not sess or not sess.deaths then return 0 end
    local total = 0
    for _, d in ipairs(sess.deaths) do
        total = total + self:DeathRepairCost(d)
    end
    return total
end

local function recordDeath()
    if dead then return end
    dead = true
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess then return end
    sess.deaths = sess.deaths or {}
    local zone = GetRealZoneText()
    if not zone or zone == "" then zone = "Unknown" end
    local equipment = snapshotEquipment()
    sess.deaths[#sess.deaths + 1] = {
        time = time(),
        zone = zone,
        killer = lastAttacker,
        equipment = equipment,
        repairCost = computeRepairCost(equipment),
    }
    lastAttacker = nil
    HL.UI:Refresh()
end

function Deaths:Init()
    playerGUID = UnitGUID("player")
    HL:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        playerGUID = UnitGUID("player")
        dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or false
    end)
    HL:RegisterEvent("PLAYER_ALIVE", function()
        lastAttacker = nil
        dead = false
    end)
    HL:RegisterEvent("PLAYER_UNGHOST", function()
        dead = false
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
