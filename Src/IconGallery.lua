local _, YapperTable = ...
local IconGallery = {}
YapperTable.IconGallery = IconGallery

local RAID_ICONS = {
    { text = "star",     code = "rt1", index = 1, coords = { 0, 0.25, 0, 0.25 } },
    { text = "circle",   code = "rt2", index = 2, coords = { 0.25, 0.5, 0, 0.25 } },
    { text = "diamond",  code = "rt3", index = 3, coords = { 0.5, 0.75, 0, 0.25 } },
    { text = "triangle", code = "rt4", index = 4, coords = { 0.75, 1.0, 0, 0.25 } },
    { text = "moon",     code = "rt5", index = 5, coords = { 0, 0.25, 0.25, 0.5 } },
    { text = "square",   code = "rt6", index = 6, coords = { 0.25, 0.5, 0.25, 0.5 } },
    { text = "cross",    code = "rt7", index = 7, coords = { 0.5, 0.75, 0.25, 0.5 } },
    { text = "skull",    code = "rt8", index = 8, coords = { 0.75, 1.0, 0.25, 0.5 } },
}

local ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- Core Widget Management
function IconGallery:Init(parent)
    if self.Frame then return end

    local frame = CreateFrame("Frame", "YapperIconGallery", parent, "BackdropTemplate")
    frame:SetSize(120, 70)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:Hide()
    self.Frame = frame

    self.Cells = {}
    for i = 1, 8 do
        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(24, 24)
        
        local tex = cell:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(ICON_TEXTURE)
        local c = RAID_ICONS[i].coords
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
        cell.Texture = tex

        local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)
        
        local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
        label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
        label:SetText(i)
        cell.Label = label

        -- Calculate Grid Position (4 columns, 2 rows)
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + (col * 28), -6 - (row * 30))
        
        cell:SetScript("OnClick", function()
            self:Select(i)
        end)

        self.Cells[i] = cell
    end
end

function IconGallery:Show(editBox, query)
    self:Init(editBox.Overlay)
    self.EditBox = editBox
    self.Query = query or ""
    self.Active = true

    -- Position relative to cursor if possible, or just TOPLEFT of editbox
    local x = (editBox.GetCaretXOffset and editBox:GetCaretXOffset()) or 0
    local y = (editBox.GetCaretYOffset and editBox:GetCaretYOffset()) or 0
    
    self.Frame:ClearAllPoints()
    self.Frame:SetPoint("BOTTOMLEFT", editBox.OverlayEdit, "TOPLEFT", x, 4)
    self.Frame:Show()

    self:Filter(query)
end

function IconGallery:Hide()
    if self.Frame then self.Frame:Hide() end
    self.Active = false
    self.ActiveWord = nil
end

function IconGallery:Filter(query)
    if not query or query == "" then
        for i = 1, 8 do
            self.Cells[i]:SetAlpha(1)
            self.Cells[i]:Enable()
            self.Cells[i].Label:SetTextColor(1, 1, 1)
        end
        return
    end

    local q = query:lower()
    for i = 1, 8 do
        local data = RAID_ICONS[i]
        local match = data.text:find(q, 1, true) or data.code:find(q, 1, true)
        if match then
            self.Cells[i]:SetAlpha(1)
            self.Cells[i]:Enable()
            self.Cells[i].Label:SetTextColor(1, 1, 1)
        else
            self.Cells[i]:SetAlpha(0.2)
            self.Cells[i]:Disable()
            self.Cells[i].Label:SetTextColor(0.4, 0.4, 0.4)
        end
    end
end

function IconGallery:Select(index)
    local data = RAID_ICONS[index]
    if not data or not self.EditBox then return end

    local eb = self.EditBox.OverlayEdit
    local text = eb:GetText() or ""
    local pos = eb:GetCursorPosition()
    
    -- Find the '{' before the cursor to replace the query
    local pre = text:sub(1, pos)
    local startPos = pre:find("{[^}]*$")
    if startPos then
        local before = text:sub(1, startPos - 1)
        local after = text:sub(pos + 1)
        local tag = "{" .. data.text .. "}"
        eb:SetText(before .. tag .. " " .. after)
        eb:SetCursorPosition(startPos + #tag + 1)
    end

    self:Hide()
end

function IconGallery:HandleKeyDown(key)
    if not self.Active then return false end

    if key == "ESCAPE" then
        self:Hide()
        return true
    end

    local num = tonumber(key)
    if num and num >= 1 and num <= 8 then
        if self.Cells[num]:IsEnabled() then
            self:Select(num)
            return true
        end
    end

    if key == "ENTER" or key == "TAB" then
        -- Find first enabled cell
        for i = 1, 8 do
            if self.Cells[i]:IsEnabled() then
                self:Select(i)
                return true
            end
        end
    end

    return false
end
