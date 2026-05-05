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

local math_min = math.min
local math_max = math.max
local strsub = string.sub
local strfind = string.find
local strlen = string.len
local strlower = string.lower
local table_insert = table.insert
local table_sort = table.sort
local wipe = wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local ipairs = ipairs

local MAX_ROWS = 6

--- Populates the emote list. Only called when the menu is actually opened.
function Emotes:InitEmoteList()
    if self.EmoteListInitialised then return end
    self.EmoteListInitialised = true

    self.EmoteList = {}
    
    -- Loop through MAXEMOTEINDEX (defined by Blizzard in ChatEmoteConstants.lua)
    if MAXEMOTEINDEX then
        for i = 1, MAXEMOTEINDEX do
            local token = _G["EMOTE" .. i .. "_TOKEN"]
            local cmd = _G["EMOTE" .. i .. "_CMD1"]
            if token and cmd then
                local lower = strlower(cmd)
                table_insert(self.EmoteList, {
                    token = token,
                    cmd = cmd,
                    cmdLower = lower,
                    cmdSearch = strsub(lower, 2)
                })
            end
        end
        -- Sort alphabetically by command
        table_sort(self.EmoteList, function(a, b) return a.cmdLower < b.cmdLower end)
    end
end

--- Ensures the emote menu UI is created.
function Emotes:EnsureMenuUI()
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
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()
    self.MenuFrame = frame

    self.Rows = {}
    for i = 1, MAX_ROWS do
        local btn = CreateFrame("Button", nil, frame)
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
            self.ActiveIndex = (self.ActiveOffset or 0) + idx
            self:RefreshSelection()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySelection(idx, false)
        end)
        
        btn:EnableMouseWheel(true)
        btn:SetScript("OnMouseWheel", function(f, delta)
            local handler = frame:GetScript("OnMouseWheel")
            if handler then handler(frame, delta) end
        end)

        self.Rows[i] = btn
    end

    local scrollBar = CreateFrame("Slider", nil, frame)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(8)
    scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 6)
    scrollBar:SetValueStep(1)
    if scrollBar.SetObeyStepOnDrag then scrollBar:SetObeyStepOnDrag(true) end
    
    local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    thumb:SetSize(8, 24)
    scrollBar:SetThumbTexture(thumb)
    
    local sbg = scrollBar:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0, 0, 0, 0.3)
    
    scrollBar:SetScript("OnValueChanged", function(s, value)
        if s.isUpdating then return end
        self.ActiveOffset = math.floor(value + 0.5)
        self:FilterAndShow()
    end)
    self.ScrollBar = scrollBar
    
    scrollBar:SetScript("OnMouseWheel", function(s, delta)
        -- Route mouse wheel on scrollbar to the main frame's handler
        local handler = frame:GetScript("OnMouseWheel")
        if handler then handler(frame, delta) end
    end)
    
    local function RefocusEditBox()
        if self._anchorBox then
            -- Use timer to ensure WoW's native slider focus grab is finished
            C_Timer.After(0, function()
                if self._anchorBox then self._anchorBox:SetFocus() end
            end)
        end
    end
    
    scrollBar:HookScript("OnMouseDown", RefocusEditBox)
    scrollBar:HookScript("OnMouseUp", RefocusEditBox)
    
    frame:EnableMouseWheel(true)
    scrollBar:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(f, delta)
        local total = #self.FilteredList
        local maxOffset = math_max(0, total - MAX_ROWS)
        if maxOffset == 0 then return end
        
        self.ActiveOffset = self.ActiveOffset - delta
        if self.ActiveOffset < 0 then self.ActiveOffset = 0 end
        if self.ActiveOffset > maxOffset then self.ActiveOffset = maxOffset end
        
        self:FilterAndShow()
        RefocusEditBox()
    end)
end

function Emotes:EnsureHintUI()
    if self.HintFrame then return end
    
    local parent = YapperTable.EditBox and YapperTable.EditBox.Overlay or UIParent
    local hint = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    hint:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    hint:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    hint:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    hint:Hide()
    
    local hfs = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hfs:SetPoint("LEFT", hint, "LEFT", 6, 0)
    hfs:SetTextColor(0.8, 0.8, 0.8, 1)
    hfs:SetText("Tab: browse emotes")
    if YapperTable.Spellcheck and type(YapperTable.Spellcheck.ApplyOverlayFont) == "function" then
        YapperTable.Spellcheck:ApplyOverlayFont(hfs)
    end
    hint._fs = hfs
    self.HintFrame = hint
end

--- Returns true if the emote menu is open.
function Emotes:IsActive()
    return self.MenuFrame and self.MenuFrame:IsShown()
end

--- Shows the emote hint.
function Emotes:ShowHint(editBox)
    self:EnsureHintUI()
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
    self:InitEmoteList()
    self:EnsureMenuUI()
    self:HideHint()
    self._anchorBox = editBox
    self.ActiveFilter = ""
    self.ActiveIndex = 1
    self.ActiveOffset = 0
    
    local fontSize = 10
    if editBox.GetFont then
        local _, sz = editBox:GetFont()
        if sz then fontSize = sz end
    end
    self.CachedFontSize = fontSize
    
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
    self.ActiveFilter = (query and strlen(query) > 1) and strlower(strsub(query, 2)) or ""
    self.ActiveIndex = 1
    self.ActiveOffset = 0
    self:FilterAndShow()
end

--- Re-renders the emote menu UI based on the current ActiveFilter.
--- Handles the actual list filtering logic, row population, and frame resizing.
function Emotes:FilterAndShow()
    self.FilteredList = self.FilteredList or {}
    wipe(self.FilteredList)
    local query = self.ActiveFilter
    local qLen = strlen(query)
    
    for _, emote in ipairs(self.EmoteList) do
        local cmdMatch = emote.cmdSearch
        if qLen == 0 or strfind(cmdMatch, query, 1, true) == 1 then
            table_insert(self.FilteredList, emote)
        end
    end
    
    local total = #self.FilteredList
    if total == 0 then
        self:HideMenu()
        return
    end

    self.ActiveOffset = self.ActiveOffset or 0
    if self.ActiveOffset > total - MAX_ROWS then
        self.ActiveOffset = math_max(0, total - MAX_ROWS)
    end
    if self.ActiveIndex > total then
        self.ActiveIndex = 1
        self.ActiveOffset = 0
    end

    local fontSize = self.CachedFontSize or 10
    local rowHeight = math_max(18, fontSize + 4)

    local count = math_min(total, MAX_ROWS)
    local width = 240
    local maxOffset = math_max(0, total - MAX_ROWS)
    
    if maxOffset > 0 then
        self.ScrollBar:SetMinMaxValues(0, maxOffset)
        self.ScrollBar.isUpdating = true
        self.ScrollBar:SetValue(self.ActiveOffset)
        self.ScrollBar.isUpdating = false
        self.ScrollBar:Show()
    else
        self.ScrollBar:Hide()
    end
    
    local rowWidth = (maxOffset > 0) and (width - 20) or (width - 12)
    
    for i = 1, MAX_ROWS do
        local row = self.Rows[i]
        local dataIdx = self.ActiveOffset + i
        if dataIdx <= total and i <= count then
            local data = self.FilteredList[dataIdx]
            row._fsCmd:SetText(data.cmd)
            row:SetSize(rowWidth, rowHeight)
            row:SetPoint("TOPLEFT", self.MenuFrame, "TOPLEFT", 6, -6 - ((i - 1) * rowHeight))
            
            if YapperTable.Spellcheck and type(YapperTable.Spellcheck.ApplyOverlayFont) == "function" then
                YapperTable.Spellcheck:ApplyOverlayFont(row._fsCmd)
            end
            
            row:Show()
        else
            row:Hide()
        end
    end
    
    self.MenuFrame:SetSize(width, (count * rowHeight) + 12)
    self.MenuFrame:ClearAllPoints()
    self.MenuFrame:SetPoint("BOTTOMLEFT", self._anchorBox, "TOPLEFT", 0, 4)
    self.MenuFrame:Show()
    self.ClickCatcher:Show()
    
    self:RefreshSelection()
end

--- Moves the selection in the emote menu.
--- @param delta number The delta to move the selection by.
function Emotes:MoveSelection(delta)
    local total = #self.FilteredList
    if total == 0 then return end
    
    self.ActiveIndex = self.ActiveIndex + delta
    
    if self.ActiveIndex < 1 then
        self.ActiveIndex = total
        self.ActiveOffset = math_max(0, total - MAX_ROWS)
    elseif self.ActiveIndex > total then
        self.ActiveIndex = 1
        self.ActiveOffset = 0
    else
        if self.ActiveIndex <= self.ActiveOffset then
            self.ActiveOffset = self.ActiveIndex - 1
        elseif self.ActiveIndex > self.ActiveOffset + MAX_ROWS then
            self.ActiveOffset = self.ActiveIndex - MAX_ROWS
        end
    end
    
    self:FilterAndShow()
end

--- Highlights the currently selected row in the emote menu.
function Emotes:RefreshSelection()
    local max = math_min(#self.FilteredList, MAX_ROWS)
    for i = 1, max do
        local dataIdx = self.ActiveOffset + i
        if dataIdx == self.ActiveIndex then
            self.Rows[i]._activeHl:Show()
        else
            self.Rows[i]._activeHl:Hide()
        end
    end
end

--- Applies the selected emote to the edit box and hides the menu.
--- @param index number The index of the emote to apply.
--- @param isEnter boolean True if triggered via the Enter key.
function Emotes:ApplySelection(index, isEnter)
    if not self._anchorBox then return end
    
    local dataIdx = index
    if not dataIdx then
        dataIdx = self.ActiveIndex
    else
        dataIdx = self.ActiveOffset + index
    end
    
    local data = self.FilteredList[dataIdx]
    if not data then return end
    
    local autoSend = false
    if YapperTable.Config and YapperTable.Config.EditBox then
        autoSend = YapperTable.Config.EditBox.EmoteAutoSend == true
    end
    
    self:HideMenu()
    
    if autoSend then
        self._anchorBox:SetText(data.cmd)
        self._anchorBox:SetCursorPosition(strlen(data.cmd))
        
        local enterFunc = self._anchorBox:GetScript("OnEnterPressed")
        if enterFunc then
            enterFunc(self._anchorBox)
        end
    else
        self._anchorBox:SetText(data.cmd .. " ")
        self._anchorBox:SetCursorPosition(strlen(data.cmd) + 1)
        self._anchorBox:SetFocus()
        if isEnter and YapperTable.State then
            YapperTable.State:SetFlag("SuppressNextEnter", true)
        end
    end
end
