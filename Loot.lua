local HL = HelloLog
local Loot = {}
HL.Loot = Loot

-- Bare global is a CVar-gated deprecation shim since 1.15.9.
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local function escapePattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function patternify(template)
    local p = escapePattern(template)
    p = p:gsub("%%%%s", "(.+)")
    p = p:gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local SELF_SINGLE   = patternify(LOOT_ITEM_SELF          or "You receive loot: %s.")
local SELF_MULTIPLE = patternify(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
local SELF_CREATED  = patternify(LOOT_ITEM_CREATED_SELF  or "You create: %s.")
local SELF_CREATED_MULTI = patternify(LOOT_ITEM_CREATED_SELF_MULTIPLE or "You create: %sx%d.")
local SELF_PUSHED   = patternify(LOOT_ITEM_PUSHED_SELF   or "You receive item: %s.")
local SELF_PUSHED_MULTI = patternify(LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d.")

local function recordItem(link, count)
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess then return end

    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    local name, _, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfo(link)

    local bucket = sess.items[itemID]
    if not bucket then
        bucket = { count = 0 }
        sess.items[itemID] = bucket
    end
    bucket.count = bucket.count + (count or 1)
    if name    then bucket.name    = name end
    if icon    then bucket.icon    = icon end
    if quality then bucket.quality = quality end
    if link    then bucket.link    = link end
    if sellPrice and sellPrice > 0 then bucket.sellPrice = sellPrice end

    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        local mob = UnitName("target")
        if mob then
            local per = sess.perMob[mob]
            if not per then
                per = { items = {}, kills = 0 }
                sess.perMob[mob] = per
            end
            per.items[itemID] = (per.items[itemID] or 0) + (count or 1)
        end
    end

    HL.UI:Refresh()
end

local function tryParseLoot(msg)
    local link, count

    link, count = msg:match(SELF_MULTIPLE)
    if link and count then recordItem(link, tonumber(count)); return end

    link = msg:match(SELF_SINGLE)
    if link then recordItem(link, 1); return end

    link, count = msg:match(SELF_PUSHED_MULTI)
    if link and count then recordItem(link, tonumber(count)); return end

    link = msg:match(SELF_PUSHED)
    if link then recordItem(link, 1); return end

    link, count = msg:match(SELF_CREATED_MULTI)
    if link and count then recordItem(link, tonumber(count)); return end

    link = msg:match(SELF_CREATED)
    if link then recordItem(link, 1); return end
end

-- Backfills sellPrice on a bucket the first time it's displayed; the
-- value isn't always available the moment loot is parsed because
-- GetItemInfo can be cold-cache on a fresh login.
local function ensureSellPrice(bucket)
    if bucket.sellPrice or not bucket.link then return bucket.sellPrice end
    local _, _, _, _, _, _, _, _, _, _, sp = GetItemInfo(bucket.link)
    if sp and sp > 0 then bucket.sellPrice = sp end
    return bucket.sellPrice
end

function Loot:SellPrice(bucket)
    return ensureSellPrice(bucket)
end

function Loot:HasAuctionator()
    return Auctionator ~= nil
        and Auctionator.API ~= nil
        and Auctionator.API.v1 ~= nil
end

-- Auctionator (Vanilla/Classic) exposes a stable public API at
-- Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link). Returns
-- nil when Auctionator isn't installed or has no scan data for the item.
local function ahPriceForBucket(bucket)
    if not Loot:HasAuctionator() then
        return nil
    end
    local api = Auctionator.API.v1
    if api.GetAuctionPriceByItemLink and bucket.link then
        local p = api.GetAuctionPriceByItemLink("HelloLog", bucket.link)
        if p and p > 0 then return p end
    end
    if api.GetAuctionPriceByItemID and bucket.link then
        local id = tonumber(bucket.link:match("item:(%d+)"))
        if id then
            local p = api.GetAuctionPriceByItemID("HelloLog", id)
            if p and p > 0 then return p end
        end
    end
    return nil
end

function Loot:AHPrice(bucket)
    return ahPriceForBucket(bucket)
end

function Loot:ItemsValue(sess)
    local result = { vendorTotal = 0, ahTotal = 0, byQuality = {} }
    if not sess or not sess.items then return result end
    for _, bucket in pairs(sess.items) do
        local q = bucket.quality or 1
        if q <= 4 then
            local count = bucket.count or 0
            local row = result.byQuality[q] or { vendor = 0, ah = 0 }
            local sp = ensureSellPrice(bucket)
            if sp and sp > 0 then
                local v = sp * count
                row.vendor = row.vendor + v
                result.vendorTotal = result.vendorTotal + v
            end
            local ah = ahPriceForBucket(bucket)
            if ah and ah > 0 then
                local v = ah * count
                row.ah = row.ah + v
                result.ahTotal = result.ahTotal + v
            end
            result.byQuality[q] = row
        end
    end
    return result
end

-- Snapshot the player's bags (aggregated count per itemID across bags).
-- Used by trade and disenchant tracking to detect which session-loot
-- items have left the player's possession.
local function bagSnapshot()
    local snap = {}
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = (C_Container and C_Container.GetContainerNumSlots
                and C_Container.GetContainerNumSlots(bag))
            or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local id, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then id, count = info.itemID, info.stackCount end
            elseif GetContainerItemInfo then
                local _, c, _, _, _, _, link = GetContainerItemInfo(bag, slot)
                if link then
                    id = tonumber(link:match("item:(%d+)"))
                    count = c
                end
            end
            if id and count then
                snap[id] = (snap[id] or 0) + count
            end
        end
    end
    return snap
end

local function decrementPerMob(sess, itemID, amount)
    local remaining = amount
    for _, per in pairs(sess.perMob or {}) do
        if remaining <= 0 then break end
        local count = per.items and per.items[itemID]
        if count and count > 0 then
            local sub = math.min(remaining, count)
            per.items[itemID] = count - sub
            remaining = remaining - sub
        end
    end
end

local function applyOutgoingDelta(preSnapshot)
    if not preSnapshot then return end
    if not HL.Session:IsRecording() then return end
    local sess = HL.Session:Current()
    if not sess or not sess.items then return end
    local current = bagSnapshot()
    local touched = false
    for itemID, oldCount in pairs(preSnapshot) do
        local newCount = current[itemID] or 0
        if newCount < oldCount then
            local lost = oldCount - newCount
            local bucket = sess.items[itemID]
            if bucket and (bucket.count or 0) > 0 then
                local sub = math.min(lost, bucket.count)
                bucket.count = bucket.count - sub
                decrementPerMob(sess, itemID, sub)
                touched = true
            end
        end
    end
    if touched then HL.UI:Refresh() end
end

local pendingTrade
local pendingDisenchant
local DISENCHANT_SPELL_ID = 13262

local lastMoney

function Loot:Init()
    HL:RegisterEvent("CHAT_MSG_LOOT", function(msg)
        tryParseLoot(msg)
    end)

    HL:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        lastMoney = GetMoney()
    end)

    HL:RegisterEvent("PLAYER_MONEY", function()
        local now = GetMoney()
        if lastMoney == nil then
            lastMoney = now
            return
        end
        local delta = now - lastMoney
        lastMoney = now
        if delta > 0 and HL.Session:IsRecording() then
            local sess = HL.Session:Current()
            if sess then
                sess.money = (sess.money or 0) + delta
                HL.UI:Refresh()
            end
        end
    end)

    HL:RegisterEvent("TRADE_SHOW", function()
        pendingTrade = bagSnapshot()
    end)
    HL:RegisterEvent("TRADE_REQUEST_CANCEL", function()
        pendingTrade = nil
    end)
    HL:RegisterEvent("TRADE_CLOSED", function()
        if not pendingTrade then return end
        local pre = pendingTrade
        pendingTrade = nil
        -- Bags lag a hair behind TRADE_CLOSED, so wait a tick before diffing.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() applyOutgoingDelta(pre) end)
        else
            applyOutgoingDelta(pre)
        end
    end)

    HL:RegisterEvent("UNIT_SPELLCAST_SENT", function(unit, _, _, spellID)
        if unit ~= "player" then return end
        if spellID == DISENCHANT_SPELL_ID then
            pendingDisenchant = bagSnapshot()
        end
    end)
    HL:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if unit ~= "player" then return end
        if spellID == DISENCHANT_SPELL_ID and pendingDisenchant then
            local pre = pendingDisenchant
            pendingDisenchant = nil
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, function() applyOutgoingDelta(pre) end)
            else
                applyOutgoingDelta(pre)
            end
        end
    end)
    local function clearDisenchant(unit, _, spellID)
        if unit ~= "player" then return end
        if spellID == DISENCHANT_SPELL_ID then pendingDisenchant = nil end
    end
    HL:RegisterEvent("UNIT_SPELLCAST_FAILED",      clearDisenchant)
    HL:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", clearDisenchant)
end
