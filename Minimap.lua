local HL = HelloLog
local Minimap = {}
HL.Minimap = Minimap

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Book_11"
local DEFAULT_ANGLE = 225

local button

local function Store()
    HelloLogDB = HelloLogDB or {}
    HelloLogDB.minimap = HelloLogDB.minimap or {}
    return HelloLogDB.minimap
end

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(Store().angle or DEFAULT_ANGLE)
    local r = _G.Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate(self)
    local mx, my = GetCursorPosition()
    local scale = _G.Minimap:GetEffectiveScale()
    local cx, cy = _G.Minimap:GetCenter()
    if not cx then return end
    mx = mx / scale - cx
    my = my / scale - cy
    Store().angle = math.deg(math.atan2(my, mx)) % 360
    UpdatePosition()
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("HelloLog")
    GameTooltip:AddLine("|cFFCCCCCCLeft-click:|r toggle window", 1, 1, 1)
    GameTooltip:AddLine("|cFFCCCCCCRight-click:|r options", 1, 1, 1)
    GameTooltip:AddLine("|cFFCCCCCCDrag:|r move icon", 1, 1, 1)
    GameTooltip:Show()
end

local function OnClick(self, mouseButton)
    if mouseButton == "RightButton" then
        HL.Options:Open()
    else
        HL.UI:Toggle()
    end
end

function Minimap:Init()
    button = CreateFrame("Button", "HelloLogMinimapButton", _G.Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button.border = border

    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdatePosition()
    self:ApplyVisibility()
end

function Minimap:IsHidden()
    return Store().hide == true
end

function Minimap:SetHidden(hide)
    Store().hide = hide and true or nil
    self:ApplyVisibility()
end

function Minimap:ApplyVisibility()
    if not button then return end
    if self:IsHidden() then button:Hide() else button:Show() end
end
