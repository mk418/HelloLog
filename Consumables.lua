local HL = HelloLog
local Consumables = {}
HL.Consumables = Consumables

-- Bare global is a CVar-gated deprecation shim since 1.15.9.
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local ITEM_CLASS_CONSUMABLE = 0

local snapshot = {}
local busy = false

local function getContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

local function getContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return info.itemID, info.stackCount, info.hyperlink
    end
    if not GetContainerItemInfo then return nil end
    local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    return id, count, link
end

local function buildSnapshot()
    local snap = {}
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        for slot = 1, getContainerNumSlots(bag) do
            local id, count = getContainerItem(bag, slot)
            if id and count then
                snap[id] = (snap[id] or 0) + count
            end
        end
    end
    return snap
end

local function recordConsumable(itemID, count, link)
    local sess = HL.Session:Current()
    if not sess then return end
    sess.consumables = sess.consumables or {}
    local bucket = sess.consumables[itemID]
    if not bucket then
        bucket = { count = 0 }
        sess.consumables[itemID] = bucket
    end
    bucket.count = bucket.count + count
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link or itemID)
    if link    then bucket.link    = link end
    if name    then bucket.name    = name end
    if icon    then bucket.icon    = icon end
    if quality then bucket.quality = quality end
end

local function onBagUpdate()
    local current = buildSnapshot()
    if busy or not HL.Session:IsRecording() then
        snapshot = current
        return
    end
    local touched = false
    for itemID, oldCount in pairs(snapshot) do
        local newCount = current[itemID] or 0
        if newCount < oldCount then
            local used = oldCount - newCount
            local _, link, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemID)
            if classID == ITEM_CLASS_CONSUMABLE then
                recordConsumable(itemID, used, link)
                touched = true
            end
        end
    end
    snapshot = current
    if touched then HL.UI:Refresh() end
end

local function setBusy(b)
    busy = b
    if not b then snapshot = buildSnapshot() end
end

function Consumables:Init()
    HL:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        snapshot = buildSnapshot()
    end)
    HL:RegisterEvent("BAG_UPDATE_DELAYED", onBagUpdate)
    HL:RegisterEvent("MERCHANT_SHOW",   function() setBusy(true)  end)
    HL:RegisterEvent("MERCHANT_CLOSED", function() setBusy(false) end)
    HL:RegisterEvent("MAIL_SHOW",       function() setBusy(true)  end)
    HL:RegisterEvent("MAIL_CLOSED",     function() setBusy(false) end)
    HL:RegisterEvent("TRADE_SHOW",      function() setBusy(true)  end)
    HL:RegisterEvent("TRADE_CLOSED",    function() setBusy(false) end)
end
