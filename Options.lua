local HL = HelloLog
local Options = {}
HL.Options = Options

local categoryID

local function BuildLegacy(panel)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HelloLog")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Per-zone session log of loot, gold, kills, and reputation.")

    local check = CreateFrame("CheckButton", "HelloLogOptionsMinimapCheck", panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    _G[check:GetName() .. "Text"]:SetText("Show minimap icon")
    check:SetChecked(not HL.Minimap:IsHidden())
    check:SetScript("OnClick", function(self)
        HL.Minimap:SetHidden(not self:GetChecked())
    end)

    panel.refresh = function()
        check:SetChecked(not HL.Minimap:IsHidden())
    end
end

function Options:Init()
    local panel = CreateFrame("Frame", "HelloLogOptionsPanel")
    panel.name = "HelloLog"
    BuildLegacy(panel)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "HelloLog")
        category.ID = "HelloLog"
        Settings.RegisterAddOnCategory(category)
        categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        categoryID = panel.name
    end

    self.panel = panel
end

function Options:Open()
    if Settings and Settings.OpenToCategory and categoryID then
        Settings.OpenToCategory(categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
