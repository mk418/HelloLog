local HL = HelloLog
local UI = {}
HL.UI = UI

local frame

local COMPACT_WIDTH = 420
local EXPANDED_WIDTH = 560
local PANEL_WIDTH = COMPACT_WIDTH
local PAD_LEFT = 10
local PAD_RIGHT = 10
local STATE_LINE_Y = -32
local STATS_LINE_Y = -58
local VENDOR_LINE_Y = -76
local REP_LINE_Y = -94
local CONTENT_TOP_OFFSET = 114
local BOTTOM_PAD = 12
local COMPACT_EMPTY_HEIGHT = CONTENT_TOP_OFFSET + BOTTOM_PAD + 4
local EXPANDED_HEIGHT = 480
local ICON_SIZE = 28
local ICON_SPACING = 4
local ICONS_PER_ROW = math.floor((PANEL_WIDTH - PAD_LEFT - PAD_RIGHT + ICON_SPACING) / (ICON_SIZE + ICON_SPACING))

local function UIStore()
    HelloLogDB = HelloLogDB or {}
    HelloLogDB.ui = HelloLogDB.ui or {}
    return HelloLogDB.ui
end

local function RestorePosition()
    frame:ClearAllPoints()
    local p = UIStore().point
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
    end
end

local function SavePosition()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local uiRight = UIParent:GetRight()
    local uiTop = UIParent:GetTop()
    if not (right and top and uiRight and uiTop) then return end
    UIStore().point = {
        point = "TOPRIGHT",
        relPoint = "TOPRIGHT",
        x = right - uiRight,
        y = top - uiTop,
    }
end

local function formatMoney(copper)
    return GetCoinTextureString(copper or 0)
end

local function formatPerHour(amount, seconds)
    if not seconds or seconds < 30 then return nil end
    local rate = amount * 3600 / seconds
    if math.abs(rate) >= 100 then
        return string.format("%+d/hr", math.floor(rate + (rate >= 0 and 0.5 or -0.5)))
    end
    return string.format("%+.1f/hr", rate)
end

local function formatDuration(seconds)
    seconds = math.floor(seconds or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
    return string.format("%dm %02ds", m, s)
end

local QUALITY_FALLBACK = { r = 1, g = 1, b = 1 }

local function qualityColor(q)
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        return ITEM_QUALITY_COLORS[q]
    end
    return QUALITY_FALLBACK
end

local function createIconButton(index)
    local btn = CreateFrame("Button", "HelloLogIcon" .. index, frame)
    btn:SetSize(ICON_SIZE, ICON_SIZE)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetPoint("TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.border:SetColorTexture(0, 0, 0, 0.6)
    btn.border:SetDrawLayer("BACKGROUND")

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.count:SetJustifyH("RIGHT")

    btn:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

local function getIconButton(index)
    frame.icons = frame.icons or {}
    local btn = frame.icons[index]
    if not btn then
        btn = createIconButton(index)
        frame.icons[index] = btn
    end
    return btn
end

local function collectItems(sess)
    local list = {}
    for itemID, bucket in pairs(sess.items) do
        list[#list + 1] = {
            itemID = itemID,
            count = bucket.count or 0,
            name = bucket.name,
            icon = bucket.icon,
            quality = bucket.quality or 1,
            link = bucket.link,
        }
    end
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.count ~= b.count then return a.count > b.count end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function hideIcons()
    if not frame.icons then return end
    for _, btn in ipairs(frame.icons) do
        btn:Hide()
    end
end

local function layoutIcons(items)
    local total = #items
    for i = 1, total do
        local data = items[i]
        local btn = getIconButton(i)
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        local col = (i - 1) % ICONS_PER_ROW
        local x = PAD_LEFT + col * (ICON_SIZE + ICON_SPACING)
        local y = -(CONTENT_TOP_OFFSET + row * (ICON_SIZE + ICON_SPACING))
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)

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
        btn:Show()
    end

    if frame.icons then
        for i = total + 1, #frame.icons do
            frame.icons[i]:Hide()
            frame.icons[i].link = nil
        end
    end

    local rows = total > 0 and math.ceil(total / ICONS_PER_ROW) or 0
    local height = CONTENT_TOP_OFFSET + rows * (ICON_SIZE + ICON_SPACING) + BOTTOM_PAD
    if rows == 0 then height = COMPACT_EMPTY_HEIGHT end
    frame:SetHeight(height)
end

function UI:IsExpanded()
    return UIStore().expanded == true
end

function UI:SetExpanded(expanded)
    UIStore().expanded = expanded and true or nil
    if expanded then
        if HL.Session:IsRecording() then
            HL.Detail:ShowLive()
        end
        frame.detailButton:SetText("Hide details")
        hideIcons()
        frame:SetWidth(EXPANDED_WIDTH)
        frame:SetHeight(EXPANDED_HEIGHT)
        if frame.detailBody then frame.detailBody:Show() end
    else
        frame.detailButton:SetText("Details")
        if frame.detailBody then frame.detailBody:Hide() end
        frame:SetWidth(COMPACT_WIDTH)
    end
    self:Refresh()
end

function UI:ToggleExpanded()
    self:SetExpanded(not self:IsExpanded())
end

function UI:ToggleRecording()
    if HL.Session:IsRecording() then
        HL.Session:Stop()
    else
        HL.Session:Start()
    end
end

function UI:Init()
    frame = CreateFrame("Frame", "HelloLogPanel", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(PANEL_WIDTH, COMPACT_EMPTY_HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    -- Sit just above the minimap (which also lives on MEDIUM) so the
    -- minimap doesn't draw over us, while staying low enough that addon
    -- windows like ThreatClassic2 or HelloStock render on top.
    local mmLevel = (Minimap and Minimap:GetFrameLevel()) or 1
    frame:SetFrameLevel(mmLevel + 1)
    frame:SetUserPlaced(false)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then UI:ToggleExpanded() end
    end)

    RestorePosition()
    SavePosition()
    frame.TitleText:SetText("HelloLog")

    frame.recordButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.recordButton:SetSize(72, 22)
    frame.recordButton:SetPoint("TOPLEFT", PAD_LEFT, STATE_LINE_Y)
    frame.recordButton:SetText("Record")
    frame.recordButton:SetScript("OnClick", function() UI:ToggleRecording() end)

    frame.stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.stopButton:SetSize(54, 22)
    frame.stopButton:SetPoint("LEFT", frame.recordButton, "RIGHT", 4, 0)
    frame.stopButton:SetText("Stop")
    frame.stopButton:SetScript("OnClick", function() HL.Session:Close() end)

    frame.detailButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.detailButton:SetSize(80, 22)
    frame.detailButton:SetPoint("TOPRIGHT", -8, STATE_LINE_Y)
    frame.detailButton:SetText("Details")
    frame.detailButton:SetScript("OnClick", function() UI:ToggleExpanded() end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.stopButton, "RIGHT", 8, 0)
    frame.title:SetPoint("RIGHT", frame.detailButton, "LEFT", -8, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    frame.stats = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.stats:SetPoint("TOPLEFT", PAD_LEFT + 4, STATS_LINE_Y)
    frame.stats:SetPoint("TOPRIGHT", -PAD_RIGHT, STATS_LINE_Y)
    frame.stats:SetJustifyH("LEFT")
    frame.stats:SetWordWrap(false)

    frame.vendorLine = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.vendorLine:SetPoint("TOPLEFT", PAD_LEFT + 4, VENDOR_LINE_Y)
    frame.vendorLine:SetPoint("TOPRIGHT", -PAD_RIGHT, VENDOR_LINE_Y)
    frame.vendorLine:SetJustifyH("LEFT")
    frame.vendorLine:SetWordWrap(false)
    frame.vendorLine:Hide()

    frame.repLine = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.repLine:SetPoint("TOPLEFT", PAD_LEFT, REP_LINE_Y)
    frame.repLine:SetPoint("TOPRIGHT", -PAD_RIGHT, REP_LINE_Y)
    frame.repLine:SetJustifyH("LEFT")
    frame.repLine:SetWordWrap(false)

    local body = HL.Detail:Build(frame, PANEL_WIDTH - PAD_LEFT - PAD_RIGHT)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_LEFT, -CONTENT_TOP_OFFSET)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_RIGHT, BOTTOM_PAD)
    body:Hide()
    frame.detailBody = body

    frame:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 1 then return end
        self._t = 0
        if HL.Session:IsRecording() then
            HL.Session:Tick()
            UI:Refresh()
        end
    end)

    if self:IsExpanded() then
        self:SetExpanded(true)
    else
        self:Refresh()
    end

    if UIStore().shown then
        frame:Show()
    else
        frame:Hide()
    end
end

function UI:IsShown()
    return frame and frame:IsShown()
end

function UI:Show()
    if not frame then return end
    UIStore().shown = true
    frame:Show()
end

function UI:Hide()
    if not frame then return end
    UIStore().shown = nil
    frame:Hide()
end

function UI:Toggle()
    if not frame then return end
    if frame:IsShown() then self:Hide() else self:Show() end
end

function UI:ResetPosition()
    if not frame then return end
    UIStore().point = nil
    RestorePosition()
    frame:SetUserPlaced(false)
end

function UI:Refresh()
    if not frame then return end
    local sess = HL.Session:Current()
    local recording = HL.Session:IsRecording()

    if sess then
        frame.title:SetText(sess.zone)
        local elapsed = HL.Session:ElapsedSeconds() or 0
        local parts = { formatDuration(elapsed) }
        local totalKills = 0
        for _, per in pairs(sess.perMob or {}) do
            totalKills = totalKills + (per.kills or 0)
        end
        if totalKills > 0 then
            local hr = formatPerHour(totalKills, elapsed)
            if hr then
                parts[#parts + 1] = string.format("%d kills |cFF999999(%s)|r", totalKills, hr)
            else
                parts[#parts + 1] = string.format("%d kills", totalKills)
            end
        end
        local deaths = sess.deaths and #sess.deaths or 0
        if deaths > 0 then
            parts[#parts + 1] = string.format("|cFFFF6666%d deaths|r", deaths)
        end
        parts[#parts + 1] = formatMoney(sess.money)
        frame.stats:SetText(table.concat(parts, "   |cFF666666\194\183|r   "))

        local itemsValue = HL.Loot:ItemsValue(sess)
        if itemsValue.vendorTotal > 0 then
            local text = "|cFFFFCC00Items value|r " .. formatMoney(itemsValue.vendorTotal)
            if HL.Loot:HasAuctionator() and itemsValue.ahTotal and itemsValue.ahTotal > 0 then
                text = text .. " |cFF888888(AH " .. formatMoney(itemsValue.ahTotal) .. ")|r"
            end
            frame.vendorLine:SetText(text)
            frame.vendorLine:Show()
        else
            frame.vendorLine:SetText("")
            frame.vendorLine:Hide()
        end

        local factions = {}
        for name, b in pairs(sess.factions or {}) do
            local delta = b.delta or 0
            if delta ~= 0 then
                factions[#factions + 1] = { name = name, delta = delta }
            end
        end
        table.sort(factions, function(a, b)
            return math.abs(a.delta) > math.abs(b.delta)
        end)
        if #factions == 0 then
            frame.repLine:SetText("")
            frame.repLine:Hide()
        else
            local seconds = HL.Session:ElapsedSeconds() or 0
            local parts = {}
            for _, f in ipairs(factions) do
                local color = f.delta > 0 and "|cFF66FF66" or "|cFFFF6666"
                local sign = f.delta > 0 and "+" or ""
                local hr = formatPerHour(f.delta, seconds)
                local hrSuffix = hr and (" |cFF999999(" .. hr .. ")|r") or ""
                parts[#parts + 1] = string.format("%s %s%s%d|r%s", f.name, color, sign, f.delta, hrSuffix)
            end
            frame.repLine:SetText(table.concat(parts, "   "))
            frame.repLine:Show()
        end
    else
        frame.title:SetText("|cFF999999Press record to begin.|r")
        frame.stats:SetText("")
        frame.vendorLine:SetText("")
        frame.vendorLine:Hide()
        frame.repLine:SetText("")
        frame.repLine:Hide()
    end

    if recording then
        frame.recordButton:SetText("Pause")
    elseif sess then
        frame.recordButton:SetText("Resume")
    else
        frame.recordButton:SetText("Record")
    end
    frame.stopButton:SetEnabled(sess ~= nil)

    if self:IsExpanded() then
        HL.Detail:Refresh()
    elseif sess then
        layoutIcons(collectItems(sess))
    else
        layoutIcons({})
    end
end
