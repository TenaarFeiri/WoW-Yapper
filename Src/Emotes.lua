--[[
    This module pulls emotes from Blizzard's global emote lists and
    populates itself with them in the client's current language.
    When the user types a "/" in Yapper, they will be prompted to hit TAB
    which will then open up a searchable menu of emotes. As they continue to type,
    this list will narrow down to the correct emote.
    They can also be chosen with the mouse cursor, or arrow up/down + enter.
]]

local _, YapperTable = ...
local Emotes = {}
YapperTable.Emotes = Emotes

local MAX_ROWS = 8
local ROW_HEIGHT = 18

--- Initialises the module and populates the emote list.
function Emotes:Init()
    if self.Initialised then return end
    self.Initialised = true

    self.EmoteList = {}
    
    -- Loop through MAXEMOTEINDEX (defined by Blizzard in ChatEmoteConstants.lua)
    if MAXEMOTEINDEX then
        for i = 1, MAXEMOTEINDEX do
            local token = _G["EMOTE" .. i .. "_TOKEN"]
            local cmd = _G["EMOTE" .. i .. "_CMD1"]
            if token and cmd then
                table.insert(self.EmoteList, {
                    token = token,
                    cmd = cmd,
                    cmdLower = string.lower(cmd)
                })
            end
        end
        -- Sort alphabetically by command
        table.sort(self.EmoteList, function(a, b) return a.cmdLower < b.cmdLower end)
    end
    
    self:EnsureUI()
end

--- Ensures the UI is created and ready for use.
function Emotes:EnsureUI()
    if self.MenuFrame then return end
    
    local parent = YapperTable.EditBox and YapperTable.EditBox.Overlay or UIParent
    
    -- Catcher to hide menu when clicking outside
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(1)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() self:HideMenu() end)
    catcher:Hide()
    self.ClickCatcher = catcher

    -- Menu Frame
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.3, 0.6, 0.9, 1) -- Slightly blue to distinguish from spellcheck
    frame:Hide()
    self.MenuFrame = frame

    self.Rows = {}
    for i = 1, MAX_ROWS do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(200, ROW_HEIGHT)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - ((i - 1) * ROW_HEIGHT))
        btn:EnableMouse(true)

        -- Selection highlight
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        
        -- Active selection highlight (keyboard)
        local activeHl = btn:CreateTexture(nil, "ARTWORK")
        activeHl:SetAllPoints()
        activeHl:SetColorTexture(1, 1, 1, 0.08)
        activeHl:Hide()
        btn._activeHl = activeHl

        local fsCmd = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fsCmd:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn._fsCmd = fsCmd

        local idx = i
        btn:SetScript("OnEnter", function()
            self.ActiveIndex = idx
            self:RefreshSelection()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySelection(idx)
        end)

        self.Rows[i] = btn
    end

    -- Hint Frame
    local hint = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    hint:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    hint:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    hint:SetBackdropBorderColor(0.3, 0.6, 0.9, 1)
    hint:Hide()
    
    local hfs = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hfs:SetPoint("LEFT", hint, "LEFT", 6, 0)
    hfs:SetTextColor(0.8, 0.8, 0.8, 1)
    hfs:SetText("Tab: browse emotes")
    hint._fs = hfs
    self.HintFrame = hint
end

--- Returns true if the emote menu is open.
function Emotes:IsActive()
    return self.MenuFrame and self.MenuFrame:IsShown()
end

--- Shows the emote hint.
function Emotes:ShowHint(editBox)
    self:Init()
    if not self.HintFrame or self.HintFrame:IsShown() or self:IsActive() then return end
    
    self._anchorBox = editBox
    local w = self.HintFrame._fs:GetStringWidth() + 12
    self.HintFrame:SetSize(w, 20)
    self.HintFrame:ClearAllPoints()
    self.HintFrame:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)
    self.HintFrame:Show()
end

--- Hides the emote hint.
function Emotes:HideHint()
    if self.HintFrame then self.HintFrame:Hide() end
end

--- Opens the emote menu.
function Emotes:OpenMenu(editBox)
    self:Init()
    self:HideHint()
    self._anchorBox = editBox
    self.ActiveFilter = ""
    self.ActiveIndex = 1
    self:FilterAndShow()
end

--- Hides the emote menu.
function Emotes:HideMenu()
    if self.MenuFrame then self.MenuFrame:Hide() end
    if self.ClickCatcher then self.ClickCatcher:Hide() end
end

--- Prepares the search filter state from a raw slash command query.
--- Strips the leading "/" and updates the ActiveFilter before triggering a redraw.
--- @param query string The raw text from the EditBox (e.g. "/wa").
function Emotes:FilterMenu(query)
    if not self:IsActive() then return end
    self.ActiveFilter = (query and string.len(query) > 1) and string.lower(string.sub(query, 2)) or ""
    self.ActiveIndex = 1
    self:FilterAndShow()
end

--- Re-renders the emote menu UI based on the current ActiveFilter.
--- Handles the actual list filtering logic, row population, and frame resizing.
function Emotes:FilterAndShow()
    self.FilteredList = {}
    local query = self.ActiveFilter
    
    for _, emote in ipairs(self.EmoteList) do
        -- match without the slash
        local cmdMatch = string.sub(emote.cmdLower, 2)
        if query == "" or string.sub(cmdMatch, 1, string.len(query)) == query then
            table.insert(self.FilteredList, emote)
        end
    end
    
    if #self.FilteredList == 0 then
        self:HideMenu()
        return
    end

    local count = math.min(#self.FilteredList, MAX_ROWS)
    local width = 240
    
    for i = 1, MAX_ROWS do
        local row = self.Rows[i]
        if i <= count then
            local data = self.FilteredList[i]
            row._fsCmd:SetText(data.cmd)
            row:Show()
        else
            row:Hide()
        end
    end
    
    self.MenuFrame:SetSize(width, (count * ROW_HEIGHT) + 12)
    self.MenuFrame:ClearAllPoints()
    self.MenuFrame:SetPoint("BOTTOMLEFT", self._anchorBox, "TOPLEFT", 0, 4)
    self.MenuFrame:Show()
    self.ClickCatcher:Show()
    
    self:RefreshSelection()
end

--- Moves the selection in the emote menu.
--- @param delta number The delta to move the selection by.
function Emotes:MoveSelection(delta)
    local max = math.min(#self.FilteredList, MAX_ROWS)
    if max == 0 then return end
    
    self.ActiveIndex = self.ActiveIndex + delta
    if self.ActiveIndex < 1 then self.ActiveIndex = max end
    if self.ActiveIndex > max then self.ActiveIndex = 1 end
    
    self:RefreshSelection()
end

--- Highlights the currently selected row in the emote menu.
function Emotes:RefreshSelection()
    local max = math.min(#self.FilteredList, MAX_ROWS)
    for i = 1, max do
        if i == self.ActiveIndex then
            self.Rows[i]._activeHl:Show()
        else
            self.Rows[i]._activeHl:Hide()
        end
    end
end

--- Applies the selected emote to the edit box and hides the menu.
--- @param index number The index of the emote to apply.
function Emotes:ApplySelection(index)
    if not self._anchorBox then return end
    index = index or self.ActiveIndex
    local data = self.FilteredList[index]
    if not data then return end
    
    self._anchorBox:SetText(data.cmd)
    self._anchorBox:SetCursorPosition(string.len(data.cmd))
    self:HideMenu()
end
