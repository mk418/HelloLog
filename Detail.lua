local HL = HelloLog
local Detail = {}
HL.Detail = Detail

local container, scroll, scrollChild, empty
local mobRows = {}
local repHeader
local repRows = {}
local itemHeader
local itemRows = {}
local zoneHeader
local zoneRows = {}
local deathHeader
local deathRows = {}
local vendorHeader
local vendorRows = {}
local consumableHeader
local consumableRows = {}
local historyRows = {}
local viewButton
local sessionSummary
local viewMode = "live"
local viewIndex
local lastViewKey
local REP_ROW_HEIGHT = 14
local ITEM_ROW_HEIGHT = 14
local ZONE_ROW_HEIGHT = 14
local DEATH_ROW_HEIGHT = 14
local VENDOR_ROW_HEIGHT = 14
local CONSUMABLE_ROW_HEIGHT = 14
local HISTORY_ROW_HEIGHT = 18
local SECTION_GAP = 10
local SESSION_SUMMARY_GAP = 8
local TOP_BUTTON_HEIGHT = 24

local ICON_SIZE = 26
local ICON_SPACING = 4
local ROW_GAP = 8
local NAME_HEIGHT = 16
local NAME_TO_ICONS = 4
local SCROLLBAR_GUTTER = 22

local function qualityColor(q)
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        return ITEM_QUALITY_COLORS[q]
    end
    return { r = 1, g = 1, b = 1 }
end

local function newItemIcon(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetPoint("TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.border:SetDrawLayer("BACKGROUND")

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)

    btn:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        if self.rateText then
            GameTooltip:AddLine(self.rateText, 0.7, 0.85, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function newMobRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.summary:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.icons = {}
    return row
end

local function getMobRow(i)
    local row = mobRows[i]
    if not row then
        row = newMobRow(scrollChild)
        mobRows[i] = row
    end
    return row
end

local function getIconFromRow(row, i)
    local btn = row.icons[i]
    if not btn then
        btn = newItemIcon(row)
        row.icons[i] = btn
    end
    return btn
end

local function collectMobs(sess)
    local list = {}
    for name, per in pairs(sess.perMob or {}) do
        local items = {}
        local total = 0
        for itemID, count in pairs(per.items or {}) do
            local bucket = sess.items[itemID]
            items[#items + 1] = {
                itemID = itemID,
                count = count,
                icon = bucket and bucket.icon,
                name = bucket and bucket.name,
                quality = bucket and (bucket.quality or 1) or 1,
                link = bucket and bucket.link,
            }
            total = total + count
        end
        table.sort(items, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            if a.count ~= b.count then return a.count > b.count end
            return (a.name or "") < (b.name or "")
        end)
        list[#list + 1] = {
            name = name,
            items = items,
            total = total,
            kills = per.kills or 0,
        }
    end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return list
end

local function collectFactions(sess)
    local list = {}
    for name, b in pairs(sess.factions or {}) do
        local delta = b.delta or 0
        if delta ~= 0 then
            list[#list + 1] = { name = name, delta = delta }
        end
    end
    table.sort(list, function(a, b)
        return math.abs(a.delta) > math.abs(b.delta)
    end)
    return list
end

local function getRepRow(i)
    local row = repRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        repRows[i] = row
    end
    return row
end

local function hideRepRows(from)
    for i = from, #repRows do
        repRows[i]:Hide()
    end
end

local function formatPerHour(amount, seconds)
    if not seconds or seconds < 30 then return nil end
    local rate = amount * 3600 / seconds
    if math.abs(rate) >= 100 then
        return string.format("%+d/hr", math.floor(rate + (rate >= 0 and 0.5 or -0.5)))
    end
    return string.format("%+.1f/hr", rate)
end

local function layoutRep(factions, yStart, seconds)
    if #factions == 0 then
        if repHeader then repHeader:Hide() end
        hideRepRows(1)
        return yStart
    end

    if not repHeader then
        repHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        repHeader:SetJustifyH("LEFT")
        repHeader:SetText("|cFFFFCC00Reputation|r")
    end
    repHeader:ClearAllPoints()
    repHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    repHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    for i, f in ipairs(factions) do
        local row = getRepRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
        local color = f.delta > 0 and "|cFF66FF66" or "|cFFFF6666"
        local sign = f.delta > 0 and "+" or ""
        local hr = formatPerHour(f.delta, seconds)
        local hrSuffix = hr and string.format("   |cFF999999(%s)|r", hr) or ""
        row:SetText(string.format("%s   %s%s%d|r%s", f.name, color, sign, f.delta, hrSuffix))
        row:Show()
        y = y + REP_ROW_HEIGHT
    end
    hideRepRows(#factions + 1)
    return y + SECTION_GAP
end

local function collectItemTotals(sess)
    local list = {}
    for _, bucket in pairs(sess.items or {}) do
        local count = bucket.count or 0
        if count > 0 then
            list[#list + 1] = {
                count = count,
                name = bucket.name or "?",
                quality = bucket.quality or 1,
                link = bucket.link,
                sellPrice = HL.Loot:SellPrice(bucket),
                ahPrice = HL.Loot:AHPrice(bucket),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list
end

local function qualityHex(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    return "|cFFFFFFFF"
end

local function getItemRow(i)
    local row = itemRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        itemRows[i] = row
    end
    return row
end

local function hideItemRows(from)
    for i = from, #itemRows do itemRows[i]:Hide() end
end

local function layoutItems(items, yStart, seconds)
    if #items == 0 then
        if itemHeader then itemHeader:Hide() end
        hideItemRows(1)
        return yStart
    end

    if not itemHeader then
        itemHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemHeader:SetJustifyH("LEFT")
        itemHeader:SetText("|cFFFFCC00Items|r")
    end
    itemHeader:ClearAllPoints()
    itemHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    itemHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    for i, it in ipairs(items) do
        local row = getItemRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
        local hr = formatPerHour(it.count, seconds)
        local hrSuffix = hr and string.format("   |cFF999999(%s)|r", hr) or ""
        local valueText = ""
        if it.sellPrice and it.sellPrice > 0 then
            valueText = "   " .. GetCoinTextureString(it.sellPrice * it.count)
        end
        local ahText = ""
        if HL.Loot:HasAuctionator() and it.ahPrice and it.ahPrice > 0 then
            ahText = "   |cFF888888(" .. GetCoinTextureString(it.ahPrice * it.count) .. ")|r"
        end
        row:SetText(string.format("%s%s|r   \195\151%d%s%s%s",
            qualityHex(it.quality), it.name, it.count, hrSuffix, valueText, ahText))
        row:Show()
        y = y + ITEM_ROW_HEIGHT
    end
    hideItemRows(#items + 1)
    return y + SECTION_GAP
end

local function collectZoneVisits(sess, endTimeFallback)
    local entries = sess.zoneChanges or {}
    if #entries == 0 then return {} end
    local fallback = endTimeFallback or time()
    local list = {}
    for i, e in ipairs(entries) do
        local endTime = (i < #entries) and entries[i + 1].time or fallback
        list[#list + 1] = {
            time = e.time,
            zone = e.zone,
            duration = math.max(0, endTime - e.time),
            last = (i == #entries),
        }
    end
    return list
end

local function getZoneRow(i)
    local row = zoneRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        zoneRows[i] = row
    end
    return row
end

local function hideZoneRows(from)
    for i = from, #zoneRows do zoneRows[i]:Hide() end
end

local function formatVisitDuration(seconds)
    if seconds >= 3600 then
        return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%ds", seconds)
    end
end

local function layoutZones(visits, yStart)
    if #visits == 0 then
        if zoneHeader then zoneHeader:Hide() end
        hideZoneRows(1)
        return yStart
    end

    if not zoneHeader then
        zoneHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zoneHeader:SetJustifyH("LEFT")
        zoneHeader:SetText("|cFFFFCC00Zones visited|r")
    end
    zoneHeader:ClearAllPoints()
    zoneHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    zoneHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    for i, v in ipairs(visits) do
        local row = getZoneRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
        row:SetText(string.format(
            "%s   %s   |cFF999999(%s)|r",
            date("%H:%M", v.time),
            v.zone,
            formatVisitDuration(v.duration)
        ))
        row:Show()
        y = y + ZONE_ROW_HEIGHT
    end
    hideZoneRows(#visits + 1)
    return y + SECTION_GAP
end

local function getDeathRow(i)
    local row = deathRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        deathRows[i] = row
    end
    return row
end

local function hideDeathRows(from)
    for i = from, #deathRows do deathRows[i]:Hide() end
end

local function layoutDeaths(deaths, yStart)
    if #deaths == 0 then
        if deathHeader then deathHeader:Hide() end
        hideDeathRows(1)
        return yStart
    end

    if not deathHeader then
        deathHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        deathHeader:SetJustifyH("LEFT")
    end
    local totalRepair = 0
    for _, d in ipairs(deaths) do
        totalRepair = totalRepair + HL.Deaths:DeathRepairCost(d)
    end
    local headerSuffix = totalRepair > 0
        and string.format("   |cFF888888(~%s repair)|r", GetCoinTextureString(totalRepair))
        or ""
    deathHeader:SetText(string.format(
        "|cFFFF6666Deaths|r   |cFF999999(%d)|r%s", #deaths, headerSuffix))
    deathHeader:ClearAllPoints()
    deathHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    deathHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    for i, d in ipairs(deaths) do
        local row = getDeathRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
        local killer = d.killer and string.format("   |cFFFF9999%s|r", d.killer) or ""
        local cost = HL.Deaths:DeathRepairCost(d)
        local costSuffix = cost > 0
            and string.format("   |cFF888888~%s|r", GetCoinTextureString(cost))
            or ""
        row:SetText(string.format(
            "%s   %s%s%s",
            date("%H:%M", d.time or 0),
            d.zone or "?",
            killer,
            costSuffix
        ))
        row:Show()
        y = y + DEATH_ROW_HEIGHT
    end
    hideDeathRows(#deaths + 1)
    return y + SECTION_GAP
end

local function getVendorRow(i)
    local row = vendorRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        vendorRows[i] = row
    end
    return row
end

local function hideVendorRows(from)
    for i = from, #vendorRows do vendorRows[i]:Hide() end
end

local function layoutVendor(itemsValue, yStart)
    local total = (itemsValue and itemsValue.vendorTotal) or 0
    local ahTotal = (itemsValue and itemsValue.ahTotal) or 0
    local hasAH = HL.Loot:HasAuctionator()
    if total <= 0 and (not hasAH or ahTotal <= 0) then
        if vendorHeader then vendorHeader:Hide() end
        hideVendorRows(1)
        return yStart
    end

    if not vendorHeader then
        vendorHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vendorHeader:SetJustifyH("LEFT")
    end
    local headerPieces = { "|cFFFFCC00Items value|r" }
    if total > 0 then
        headerPieces[#headerPieces + 1] = "|cFFFFFFFF" .. GetCoinTextureString(total) .. "|r"
    end
    if hasAH and ahTotal > 0 then
        headerPieces[#headerPieces + 1] = "|cFF888888(AH " .. GetCoinTextureString(ahTotal) .. ")|r"
    end
    vendorHeader:SetText(table.concat(headerPieces, "   "))
    vendorHeader:ClearAllPoints()
    vendorHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    vendorHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    local idx = 0
    for _, q in ipairs({ 0, 1, 2, 3, 4 }) do
        local entry = itemsValue.byQuality[q]
        if entry and (entry.vendor > 0 or (hasAH and (entry.ah or 0) > 0)) then
            idx = idx + 1
            local row = getVendorRow(idx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
            local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
            local rowPieces = {}
            if entry.vendor > 0 then
                rowPieces[#rowPieces + 1] = GetCoinTextureString(entry.vendor)
            end
            if hasAH and entry.ah and entry.ah > 0 then
                rowPieces[#rowPieces + 1] = "|cFF888888(" .. GetCoinTextureString(entry.ah) .. ")|r"
            end
            row:SetText(string.format("%s%s|r   %s",
                qualityHex(q), label, table.concat(rowPieces, "   ")))
            row:Show()
            y = y + VENDOR_ROW_HEIGHT
        end
    end
    hideVendorRows(idx + 1)
    return y + SECTION_GAP
end

local function collectConsumables(sess)
    local list = {}
    for _, bucket in pairs(sess.consumables or {}) do
        local count = bucket.count or 0
        if count > 0 then
            list[#list + 1] = {
                count = count,
                name = bucket.name or "?",
                quality = bucket.quality or 1,
                link = bucket.link,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function getConsumableRow(i)
    local row = consumableRows[i]
    if not row then
        row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row:SetJustifyH("LEFT")
        consumableRows[i] = row
    end
    return row
end

local function hideConsumableRows(from)
    for i = from, #consumableRows do consumableRows[i]:Hide() end
end

local function layoutConsumables(consumables, yStart, seconds)
    if #consumables == 0 then
        if consumableHeader then consumableHeader:Hide() end
        hideConsumableRows(1)
        return yStart
    end

    if not consumableHeader then
        consumableHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        consumableHeader:SetJustifyH("LEFT")
    end
    local total = 0
    for _, c in ipairs(consumables) do total = total + c.count end
    consumableHeader:SetText(string.format(
        "|cFFFFCC00Consumables|r   |cFF999999(%d)|r", total))
    consumableHeader:ClearAllPoints()
    consumableHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yStart)
    consumableHeader:Show()
    local y = yStart + NAME_HEIGHT + 2

    for i, c in ipairs(consumables) do
        local row = getConsumableRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, -y)
        local hr = formatPerHour(c.count, seconds)
        local hrSuffix = hr and string.format("   |cFF999999(%s)|r", hr) or ""
        row:SetText(string.format("%s%s|r   \195\151%d%s",
            qualityHex(c.quality), c.name, c.count, hrSuffix))
        row:Show()
        y = y + CONSUMABLE_ROW_HEIGHT
    end
    hideConsumableRows(#consumables + 1)
    return y + SECTION_GAP
end

local function layoutRows(mobs, yStart, seconds)
    local innerWidth = scrollChild:GetWidth()
    if innerWidth < 1 then innerWidth = 1 end
    local iconsPerRow = math.floor((innerWidth + ICON_SPACING) / (ICON_SIZE + ICON_SPACING))
    if iconsPerRow < 1 then iconsPerRow = 1 end

    local yCursor = yStart or 0
    for i, mob in ipairs(mobs) do
        local row = getMobRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yCursor)
        row:SetWidth(innerWidth)

        row.name:SetText(string.format("|cFFFFCC00%s|r", mob.name))
        local kills = mob.kills or 0
        local parts = {}
        if kills > 0 then
            parts[#parts + 1] = string.format("\195\151%d kills", kills)
            local hr = formatPerHour(kills, seconds)
            if hr then parts[#parts + 1] = string.format("(%s)", hr) end
        end
        if mob.total > 0 then
            parts[#parts + 1] = string.format("%s%d items",
                kills > 0 and "\194\183 " or "",
                mob.total)
        end
        row.summary:SetText(table.concat(parts, " "))

        local iconCount = #mob.items
        local iconRows = iconCount > 0 and math.ceil(iconCount / iconsPerRow) or 0
        local rowHeight = NAME_HEIGHT
        if iconRows > 0 then
            rowHeight = rowHeight + NAME_TO_ICONS + iconRows * (ICON_SIZE + ICON_SPACING)
        end
        row:SetHeight(rowHeight)

        for j = 1, iconCount do
            local data = mob.items[j]
            local btn = getIconFromRow(row, j)
            local col = (j - 1) % iconsPerRow
            local rr = math.floor((j - 1) / iconsPerRow)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", row, "TOPLEFT",
                col * (ICON_SIZE + ICON_SPACING),
                -(NAME_HEIGHT + NAME_TO_ICONS + rr * (ICON_SIZE + ICON_SPACING)))

            if data.icon then
                btn.icon:SetTexture(data.icon)
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            local c = qualityColor(data.quality)
            btn.border:SetColorTexture(c.r, c.g, c.b, 0.9)

            if data.count and data.count > 1 then
                btn.count:SetText(data.count)
            else
                btn.count:SetText("")
            end

            btn.link = data.link
            local rate = formatPerHour(data.count or 0, seconds)
            btn.rateText = rate and ("From this mob: " .. rate) or nil
            btn:Show()
        end
        for j = iconCount + 1, #row.icons do
            row.icons[j]:Hide()
            row.icons[j].link = nil
        end

        row:Show()
        yCursor = yCursor + rowHeight + ROW_GAP
    end

    for i = #mobs + 1, #mobRows do
        mobRows[i]:Hide()
    end

    scrollChild:SetHeight(math.max(1, yCursor))
end

StaticPopupDialogs["HELLOLOG_DELETE_HISTORY"] = {
    text = "Delete recording?\n\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local idx = self.data and self.data.index
        if not idx then return end
        HL.Session:DeleteHistory(idx)
        if viewMode == "historyDetail" then
            viewMode = "historyList"
            viewIndex = nil
        end
        HL.Detail:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function getHistoryRow(i)
    local row = historyRows[i]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(HISTORY_ROW_HEIGHT)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -22, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.08)

        row.deleteBtn = CreateFrame("Button", nil, row)
        row.deleteBtn:SetSize(16, HISTORY_ROW_HEIGHT)
        row.deleteBtn:SetPoint("RIGHT", -2, 0)
        row.deleteBtn.label = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.deleteBtn.label:SetPoint("CENTER")
        row.deleteBtn.label:SetText("|cFF999999\195\151|r")
        row.deleteBtn:SetScript("OnEnter", function(self)
            self.label:SetText("|cFFFF6666\195\151|r")
        end)
        row.deleteBtn:SetScript("OnLeave", function(self)
            self.label:SetText("|cFF999999\195\151|r")
        end)

        historyRows[i] = row
    end
    return row
end

local function hideHistoryRows(from)
    for i = from, #historyRows do
        historyRows[i]:Hide()
        historyRows[i]:SetScript("OnClick", nil)
        if historyRows[i].deleteBtn then
            historyRows[i].deleteBtn:SetScript("OnClick", nil)
        end
    end
end

local function sessionItemCount(sess)
    local n = 0
    for _, b in pairs(sess.items or {}) do n = n + (b.count or 0) end
    return n
end

local function sortedHistory()
    local entries = HL.db.history or {}
    local list = {}
    for i, e in ipairs(entries) do
        list[#list + 1] = { sess = e, index = i }
    end
    table.sort(list, function(a, b)
        return (a.sess.closedAt or 0) > (b.sess.closedAt or 0)
    end)
    return list
end

local function layoutHistoryList()
    local sorted = sortedHistory()
    if #sorted == 0 then
        empty:SetText("No past sessions yet. End a session with Stop to archive it.")
        empty:Show()
        hideHistoryRows(1)
        scrollChild:SetHeight(1)
        return
    end
    empty:Hide()

    local rowWidth = scrollChild:GetWidth()
    local y = 0
    for i, entry in ipairs(sorted) do
        local row = getHistoryRow(i)
        local sess = entry.sess
        local idx = entry.index
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        row:SetWidth(rowWidth)

        local closed = sess.closedAt or sess.createdAt or 0
        local dur = sess.secondsActive or 0
        local durStr = string.format("%dm %02ds", math.floor(dur / 60), dur % 60)
        if dur >= 3600 then
            durStr = string.format("%dh %02dm", math.floor(dur / 3600), math.floor((dur % 3600) / 60))
        end
        row.text:SetText(string.format(
            "%s   |cFFFFCC00%s|r   %s   %d items   %s",
            date("%Y-%m-%d %H:%M", closed),
            sess.zone or "?",
            durStr,
            sessionItemCount(sess),
            GetCoinTextureString(sess.money or 0)
        ))
        row:SetScript("OnClick", function()
            viewMode = "historyDetail"
            viewIndex = idx
            Detail:Refresh()
        end)
        local label = string.format("%s   %s",
            date("%Y-%m-%d %H:%M", closed), sess.zone or "?")
        row.deleteBtn:SetScript("OnClick", function()
            local dlg = StaticPopup_Show("HELLOLOG_DELETE_HISTORY", label)
            if dlg then dlg.data = { index = idx } end
        end)
        row:Show()
        y = y + HISTORY_ROW_HEIGHT
    end
    hideHistoryRows(#sorted + 1)
    scrollChild:SetHeight(math.max(1, y))
end

local function formatHMS(seconds)
    seconds = math.floor(seconds or 0)
    if seconds >= 3600 then
        return string.format("%dh %02dm %02ds", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
    end
    return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
end

local function totalKillsOf(sess)
    local n = 0
    for _, per in pairs(sess.perMob or {}) do
        n = n + (per.kills or 0)
    end
    return n
end

local function renderSummary(sess, seconds)
    if not sessionSummary then return end
    local parts = {}
    if sess.closedAt then
        parts[#parts + 1] = date("%Y-%m-%d", sess.closedAt)
    end
    parts[#parts + 1] = string.format("|cFFFFCC00%s|r", sess.zone or "?")
    parts[#parts + 1] = formatHMS(seconds)
    local kills = totalKillsOf(sess)
    if kills > 0 then parts[#parts + 1] = string.format("%d kills", kills) end
    local deaths = sess.deaths and #sess.deaths or 0
    if deaths > 0 then
        parts[#parts + 1] = string.format("|cFFFF6666%d deaths|r", deaths)
    end
    parts[#parts + 1] = GetCoinTextureString(sess.money or 0)
    sessionSummary:SetText(table.concat(parts, "   |cFF666666\194\183|r   "))
    sessionSummary:Show()
end

local function hideSummary()
    if sessionSummary then sessionSummary:Hide() end
end

local function renderSessionLayout(sess, seconds, endTimeFallback)
    renderSummary(sess, seconds)
    local factions = collectFactions(sess)
    local items = collectItemTotals(sess)
    local mobs = collectMobs(sess)
    local visits = collectZoneVisits(sess, endTimeFallback)
    local deaths = sess.deaths or {}
    local consumables = collectConsumables(sess)
    if #factions == 0 and #items == 0 and #mobs == 0 and #visits == 0
        and #deaths == 0 and #consumables == 0 then
        empty:SetText("No data recorded.")
        empty:Show()
    else
        empty:Hide()
    end
    local itemsValue = HL.Loot:ItemsValue(sess)
    local y = layoutRep(factions, 0, seconds)
    y = layoutZones(visits, y)
    y = layoutDeaths(deaths, y)
    y = layoutVendor(itemsValue, y)
    y = layoutItems(items, y, seconds)
    y = layoutConsumables(consumables, y, seconds)
    layoutRows(mobs, y, seconds)
end

local function clearSessionLayout()
    hideSummary()
    layoutRep({}, 0, 0)
    layoutZones({}, 0)
    layoutDeaths({}, 0)
    layoutVendor(nil, 0)
    layoutItems({}, 0, 0)
    layoutConsumables({}, 0, 0)
    layoutRows({}, 0, 0)
end

function Detail:Build(parent, containerWidth)
    container = CreateFrame("Frame", nil, parent)

    viewButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    viewButton:SetSize(120, 20)
    viewButton:SetPoint("TOPRIGHT", 0, 0)
    viewButton:SetText("Show history")
    viewButton:SetScript("OnClick", function()
        if viewMode == "live" then
            viewMode = "historyList"
        elseif viewMode == "historyList" then
            viewMode = "live"
        else
            viewMode = "historyList"
        end
        viewIndex = nil
        Detail:Refresh()
    end)

    sessionSummary = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sessionSummary:SetPoint("TOPLEFT", 0, -TOP_BUTTON_HEIGHT)
    sessionSummary:SetPoint("TOPRIGHT", -SCROLLBAR_GUTTER, -TOP_BUTTON_HEIGHT)
    sessionSummary:SetJustifyH("LEFT")
    sessionSummary:SetWordWrap(false)
    sessionSummary:Hide()

    scroll = CreateFrame("ScrollFrame", "HelloLogDetailScroll", container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -(TOP_BUTTON_HEIGHT + SESSION_SUMMARY_GAP + 14))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_GUTTER, 0)

    local innerWidth = math.max(1, (containerWidth or 1) - SCROLLBAR_GUTTER)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(innerWidth, 1)
    scroll:SetScrollChild(scrollChild)

    empty = container:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:Hide()

    self.container = container
    return container
end

function Detail:ShowHistoryEntry(index)
    viewMode = "historyDetail"
    viewIndex = index
    self:Refresh()
end

function Detail:ShowLive()
    viewMode = "live"
    viewIndex = nil
end

function Detail:Refresh()
    if not container or not container:IsShown() then return end

    if viewMode == "live" and not HL.Session:Current() then
        viewMode = "historyList"
        viewIndex = nil
    end

    local containerW = container:GetWidth()
    if containerW and containerW > 0 then
        scrollChild:SetWidth(math.max(1, containerW - SCROLLBAR_GUTTER))
    end

    local viewKey = viewMode .. ":" .. tostring(viewIndex)
    local viewChanged = viewKey ~= lastViewKey
    lastViewKey = viewKey
    if viewChanged and scroll and scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(0)
    end

    if viewMode == "historyList" then
        if HL.Session:Current() then
            viewButton:SetText("Show current")
            viewButton:Show()
        else
            viewButton:Hide()
        end
        clearSessionLayout()
        layoutHistoryList()
        return
    elseif viewMode == "historyDetail" then
        viewButton:SetText("\194\171 Back")
        viewButton:Show()
        hideHistoryRows(1)
        local entries = HL.db.history or {}
        local sess = entries[viewIndex]
        if not sess then
            empty:SetText("Session not found.")
            empty:Show()
            clearSessionLayout()
            return
        end
        renderSessionLayout(sess, sess.secondsActive or 0, sess.closedAt)
        return
    end

    viewButton:SetText("Show history")
    viewButton:Show()
    hideHistoryRows(1)
    local sess = HL.Session:Current()
    if not sess then
        empty:SetText("No active session.")
        empty:Show()
        clearSessionLayout()
        return
    end
    renderSessionLayout(sess, HL.Session:ElapsedSeconds() or 0)
end
