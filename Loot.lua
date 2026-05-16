local HL = HelloLog
local Loot = {}
HL.Loot = Loot

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

function Loot:VendorBreakdown(sess)
    local total, byQuality = 0, {}
    if not sess or not sess.items then return total, byQuality end
    for _, bucket in pairs(sess.items) do
        local q = bucket.quality or 1
        if q <= 2 then
            local price = ensureSellPrice(bucket)
            if price and price > 0 then
                local value = price * (bucket.count or 0)
                byQuality[q] = (byQuality[q] or 0) + value
                total = total + value
            end
        end
    end
    return total, byQuality
end

function Loot:VendorValue(sess)
    local total = self:VendorBreakdown(sess)
    return total
end

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
end
