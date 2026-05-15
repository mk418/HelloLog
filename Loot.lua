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

    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link)

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
