--[[
    Spellcheck/UI.lua
    EditBox binding, text input event handlers, font measurement,
    hint frame, suggestion dropdown display and keyboard navigation,
    and suggestion application.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local SuggestionKey  = Spellcheck.SuggestionKey
local MAX_SUGGESTION_ROWS = Spellcheck._MAX_SUGGESTION_ROWS

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local string_sub = string.sub
local string_format = string.format
local table_insert  = table.insert

function Spellcheck:Bind(editBox, overlay)
    self.EditBox = editBox
    self.Overlay = overlay
    self:EnsureMeasureFontString()
    self:EnsureSuggestionFrame()
    self:EnsureHintFrame()
    self:ScheduleRefresh()
    -- Support right-click on the editbox to open/cycle suggestions.
    if editBox and editBox.HookScript then
        editBox:HookScript("OnMouseUp", function(box, button)
            if button == "RightButton" then
                self:UpdateActiveWord()
                if self:IsSuggestionEligible() then
                    self:OpenOrCycleSuggestions()
                end
            end
        end)
    end
    -- Make hint frame clickable to open suggestions as well.
    if self.HintFrame then
        self.HintFrame:EnableMouse(true)
        self.HintFrame:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and self:IsSuggestionEligible() then
                self:OpenOrCycleSuggestions()
            end
        end)
    end
end

function Spellcheck:PurgeOtherDictionaries(keepLocale)
    -- Identify and protect the base dictionary if the keepLocale depends on it.
    local keepBase = nil
    if self.Dictionaries and self.Dictionaries[keepLocale] then
        keepBase = self.Dictionaries[keepLocale].extends
    end

    if self.Dictionaries then
        for locale, dict in pairs(self.Dictionaries) do
            if locale ~= keepLocale and locale ~= keepBase then
                -- Scrub internal tables first to reduce capacity before nil-ing
                dict.words = { "." }
                dict.set = {}
                dict.index = {}
                dict.ngramIndex2 = {}
                dict.ngramIndex3 = {}

                self.Dictionaries[locale] = nil
            end
        end
    end
    if self._asyncLoaders then
        for locale, loader in pairs(self._asyncLoaders) do
            if locale ~= keepLocale and locale ~= keepBase then
                loader.cancelled = true
                self._asyncLoaders[locale] = nil
            end
        end
    end
end

--- Completely purge all dictionary data from memory.
function Spellcheck:UnloadAllDictionaries(purgeNow)
    if self.Dictionaries then
        for locale, dict in pairs(self.Dictionaries) do
            if type(dict) == "table" then
                -- Scrub internal tables to break references immediately
                dict.words = nil
                dict.set = nil
                dict.index = nil
                dict.ngramIndex2 = nil
                dict.ngramIndex3 = nil
            end
            self.Dictionaries[locale] = nil
        end
    end

    -- Cancel all background loading tasks
    if self._asyncLoaders then
        for locale, loader in pairs(self._asyncLoaders) do
            loader.cancelled = true
            self._asyncLoaders[locale] = nil
        end
    end

    -- Clear caches
    self.UserDictCache = {}
    
    -- Hidden internal suggestion state
    self._lastSuggestionsText = nil
    self._lastSuggestionsLocale = nil
    self.ActiveSuggestions = nil
    
    -- Cleanup UI state
    self:ClearUnderlines()
    if self.SuggestionFrame then self.SuggestionFrame:Hide() end
    if self.HintFrame then self.HintFrame:Hide() end

    if purgeNow then
        collectgarbage("collect")
    end
end

function Spellcheck:ApplyState(enabled, locale)
    if enabled == nil then enabled = self:IsEnabled() end
    if locale == nil then locale = self:GetLocale() end

    if enabled then
        if self.YALLM and self.YALLM.Init then
            self.YALLM:Init()
        end
        self:PurgeOtherDictionaries(locale)
        if not self:EnsureLocale(locale) then
            return false
        end
    else
        -- When disabled, we don't automatically unload (user might just be toggling).
        -- The explicit "Unload" is handled by the UI popup or manual call.
        self:ClearUnderlines()
        if self.SuggestionFrame then self.SuggestionFrame:Hide() end
    end
    self:ScheduleRefresh()
    return true
end

function Spellcheck:OnConfigChanged()
    self:ApplyState()
end

function Spellcheck:OnTextChanged(editBox, isUserInput)
    if editBox ~= self.EditBox then return end
    if isUserInput then
        self._textChangedFlag = true
        self._lastTypingTime = GetTime()

        -- Peek at the last character to detect word boundaries.
        -- If the user just hit space or punctuation, we fire immediately.
        local text = editBox:GetText() or ""
        local lastChar = string_sub(text, -1)
        if lastChar:match("[%s%.%,%!%?%:%;]") then
            self:ScheduleRefresh(0)
        else
            self:ScheduleRefresh(0.30) -- Relaxed 300ms "think pause" for active typing
        end
    else
        self:ScheduleRefresh()
    end
end

function Spellcheck:OnCursorChanged(editBox, x, y, w, h)
    if editBox ~= self.EditBox then return end
    if self._suppressCursorUpdate and self:IsSuggestionOpen() then
        return
    end

    -- Capture the visual cursor X that Blizzard gives us.
    -- We use this to derive the editbox's internal horizontal scroll.
    if type(x) == "number" then
        self._lastCursorVisX = x
    end

    -- Early-exit guard: if neither the cursor position nor the text has changed
    -- since the last call, skip all work. This prevents redundant processing
    -- during rapid OnCursorChanged fires (e.g. holding an arrow key).
    local curPos = editBox:GetCursorPosition() or 0
    local curText = editBox:GetText() or ""
    if curPos == self._lastOnCursorPos and curText == self._lastOnCursorText then
        return
    end
    self._lastOnCursorPos  = curPos
    self._lastOnCursorText = curText

    self:UpdateActiveWord()
    self:UpdateHint()

    -- Defer underline refresh to the next frame so we don't interfere
    -- with the EditBox's native cursor rendering during this callback.
    if not self._cursorRefreshPending then
        self._cursorRefreshPending = true
        C_Timer.After(0, function()
            self._cursorRefreshPending = nil
            self:UpdateUnderlines()
        end)
    end
end

function Spellcheck:OnOverlayHide()
    self:HideSuggestions()
    self:ClearUnderlines()
    self:HideHint()
end

function Spellcheck:ScheduleRefresh(delay)
    if not self:IsEnabled() then
        self:HideSuggestions()
        self:ClearUnderlines()
        self:HideHint()
        return
    end

    if self._debounceTimer and self._debounceTimer.Cancel then
        self._debounceTimer:Cancel()
    end

    if C_Timer and C_Timer.NewTimer then
        -- Default to 0.3s if no specific delay is requested (e.g. initial bind)
        self._debounceTimer = C_Timer.NewTimer(delay or 0.30, function()
            self:Rebuild()
            self._debounceTimer = nil
        end)
    else
        self:Rebuild()
    end
end

function Spellcheck:Rebuild()
    if not self.EditBox then return end
    if not self:IsEnabled() then
        self:HideSuggestions()
        self:ClearUnderlines()
        self:HideHint()
        return
    end

    self:UpdateUnderlines()
    self:UpdateActiveWord()
    self:UpdateHint()
end

function Spellcheck:EnsureMeasureFontString()
    if self.MeasureFS then return end
    -- Parent the measurement frame to the Overlay so it inherits the same
    -- effective scale as the EditBox. This ensures GetStringWidth() returns
    -- values in the same coordinate space as SetPoint offsets on the EditBox.
    -- We hide it immediately so SetText doesn't dirty the Overlay's layout.
    local parent = self.Overlay or UIParent
    local hiddenFrame = CreateFrame("Frame", nil, parent)
    hiddenFrame:SetSize(1, 1)
    hiddenFrame:Hide()
    local fs = hiddenFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    fs:SetJustifyV("TOP")
    self.MeasureFS = fs
end

function Spellcheck:EnsureSuggestionFrame()
    if self.SuggestionFrame or not self.Overlay then return end

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetAllPoints(UIParent)
    catcher:RegisterForClicks("AnyUp", "AnyDown")
    catcher:SetScript("OnClick", function()
        self:HideSuggestions()
    end)
    catcher:Hide()
    self.SuggestionClickCatcher = catcher

    local frame = CreateFrame("Frame", nil, self.Overlay, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
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

    local rows = {}
    for i = 1, MAX_SUGGESTION_ROWS do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(160, 18)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - ((i - 1) * 18))
        btn:EnableMouse(true)

        -- Highlight frame under the row to indicate selection. Use a
        -- small child frame with its own texture so it can be shown
        -- above the suggestion background reliably.
        local hlFrame = CreateFrame("Frame", nil, frame)
        hlFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        hlFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        hlFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
        local hlTex = hlFrame:CreateTexture(nil, "ARTWORK")
        hlTex:SetAllPoints(hlFrame)
        hlTex:SetColorTexture(1, 1, 1, 0.08)
        hlFrame:Hide()

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetText("-")

        btn._fs = fs
        btn._hl = hlFrame
        btn._index = i
        local idx = i
        btn:SetScript("OnEnter", function()
            self.ActiveIndex = idx
            self:RefreshSuggestionSelection()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySuggestion(idx)
        end)

        rows[i] = btn
    end

    self.SuggestionFrame = frame
    self.SuggestionRows = rows
end

function Spellcheck:SuggestionsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if SuggestionKey(a[i]) ~= SuggestionKey(b[i]) then return false end
    end
    return true
end

function Spellcheck:EnsureHintFrame()
    if self.HintFrame or not self.Overlay then return end
    local frame = CreateFrame("Frame", nil, self.Overlay, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", frame, "LEFT", 6, 0)
    fs:SetTextColor(0.8, 0.8, 0.8, 1)
    fs:SetText("Shift+Tab: spell suggestions")

    frame._fs = fs
    self.HintFrame = frame
end

function Spellcheck:CancelHintTimer()
    if self._hintTimer and self._hintTimer.Cancel then
        self._hintTimer:Cancel()
    end
    self._hintTimer = nil
    self._pendingHintWord = nil
    self._pendingHintCursor = nil
end

-- Delay (seconds) before showing the hint after user stops typing.
Spellcheck.HintDelay = 0.25

function Spellcheck:ScheduleHintShow()
    if not self.HintFrame or not self.EditBox then return end
    local cursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
    local word = self.ActiveWord
    -- If we already have a timer scheduled for the same word+cursor, leave it.
    if self._hintTimer and self._pendingHintWord == word and self._pendingHintCursor == cursor then
        return
    end
    self:CancelHintTimer()
    self._pendingHintWord = word
    self._pendingHintCursor = cursor
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:ScheduleHintShow word='" .. tostring(word) .. "' cursor=" .. tostring(cursor))
    end
    if C_Timer and C_Timer.NewTimer then
        self._hintTimer = C_Timer.NewTimer(self.HintDelay, function()
            -- If caret or word moved, abort showing.
            if not self.EditBox then return end
            local curCursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:HintTimer fired; curCursor=" ..
                    tostring(curCursor) .. " pending=" .. tostring(self._pendingHintCursor))
            end
            if curCursor ~= self._pendingHintCursor then
                if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                    self:Notify("Spellcheck:HintTimer abort due to cursor move")
                end
                return
            end
            if self.ActiveWord ~= self._pendingHintWord then
                if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                    self:Notify("Spellcheck:HintTimer abort due to word change")
                end
                return
            end
            self:ShowHint()
            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:HintTimer showing hint")
            end
            self._lastHintWord = self._pendingHintWord
            self._lastHintCursor = self._pendingHintCursor
            self._pendingHintWord = nil
            self._pendingHintCursor = nil
            self._hintTimer = nil
        end)
    else
        -- Fallback: immediate show
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:ScheduleHintShow immediate fallback show")
        end
        self:ShowHint()
        self._lastHintWord = self._pendingHintWord
        self._lastHintCursor = self._pendingHintCursor
        self._pendingHintWord = nil
        self._pendingHintCursor = nil
    end
end

function Spellcheck:ShowHint()
    if not self.HintFrame or not self.EditBox then return end

    local fontSize = self:ApplyOverlayFont(self.HintFrame._fs, 22)
    local hintHeight = math_max(20, fontSize + 8)
    local hintWidth = self.HintFrame._fs:GetStringWidth() + 12
    self.HintFrame:SetSize(hintWidth, hintHeight)

    -- Avoid re-showing (and retriggering fade) if already visible.
    if self.HintFrame:IsShown() then return end
    self.HintFrame:ClearAllPoints()
    self.HintFrame:SetPoint("TOPLEFT", self.EditBox, "BOTTOMLEFT", 0, -2)
    self.HintFrame:SetAlpha(0)
    self.HintFrame:Show()
    if UIFrameFadeIn then
        UIFrameFadeIn(self.HintFrame, 0.12, 0, 1)
    else
        self.HintFrame:SetAlpha(1)
    end
end

function Spellcheck:HideHint()
    if not self.HintFrame then return end
    self.HintFrame:Hide()
end

function Spellcheck:UpdateHint()
    if not self.EditBox then return end

    -- Only show the hint when a suggestion is eligible and the caret/word
    -- has changed since the last hint state. This reduces flicker caused by
    -- frequent OnUpdate/OnTextChanged refreshes.
    local cursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
    local word = self.ActiveWord

    if self:IsSuggestionEligible() then
        if self._lastHintWord ~= word or self._lastHintCursor ~= cursor then
            -- Schedule a delayed hint show so it doesn't flash while typing.
            self:ScheduleHintShow()
        end
    else
        if self.HintFrame and self.HintFrame:IsShown() then
            self:HideHint()
            self._lastHintWord = nil
            self._lastHintCursor = nil
        end
    end
end

function Spellcheck:IsSuggestionOpen()
    return self.SuggestionFrame and self.SuggestionFrame:IsShown()
end

function Spellcheck:IsSuggestionEligible()
    if not self:IsEnabled() then return false end
    if not self.ActiveWord then return false end
    if self.EditBox and not self.EditBox:HasFocus() then return false end
    return true
end

function Spellcheck:HandleKeyDown(key)
    if not self:IsEnabled() then return false end
    -- Use Shift+Tab to open or cycle suggestions when eligible.
    if key == "TAB" and IsShiftKeyDown() then
        if self:IsSuggestionEligible() then
            self:OpenOrCycleSuggestions()
            return true
        end
        return false
    end

    if self:IsSuggestionOpen() then
        if key == "UP" then
            self._suppressCursorUpdate = true
            if C_Timer and C_Timer.NewTimer then
                C_Timer.NewTimer(0, function()
                    self._suppressCursorUpdate = nil
                end)
            end
            self:MoveSelection(-1)
            return true
        end
        if key == "DOWN" then
            self._suppressCursorUpdate = true
            if C_Timer and C_Timer.NewTimer then
                C_Timer.NewTimer(0, function()
                    self._suppressCursorUpdate = nil
                end)
            end
            self:MoveSelection(1)
            return true
        end
        if key == "ENTER" or key == "NUMPADENTER" then
            -- Accept currently selected suggestion and prevent the enter
            -- from being handled as a send.
            local idx = self.ActiveIndex or 1
            self:ApplySuggestion(idx)
            return true
        end
        if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
            -- Set suppression before applying so OnChar won't append the digit.
            self._suppressNextChar = true
            self._suppressChar = key
            -- For non-replacement actions (add/ignore), keep the current
            -- text/cursor as the expected state so OnChar can restore it.
            if self.EditBox then
                self._expectedText = self.EditBox:GetText() or ""
                self._expectedCursor = self.EditBox:GetCursorPosition()
            end
            self:ApplySuggestion(tonumber(key))
            return true
        end
    end

    return false
end

function Spellcheck:MoveSelection(delta)
    local count = #self.ActiveSuggestions
    if count == 0 then return end
    local nextIdx = self.ActiveIndex + delta
    if nextIdx < 1 then nextIdx = count end
    if nextIdx > count then nextIdx = 1 end
    self.ActiveIndex = nextIdx
    self:RefreshSuggestionSelection()
end

function Spellcheck:RefreshSuggestionSelection()
    if not self.ActiveSuggestions then return end
    local count = #self.ActiveSuggestions
    if count == 0 then
        for _, row in ipairs(self.SuggestionRows) do row._hl:Hide() end
        return
    end
    if not self.ActiveIndex or self.ActiveIndex < 1 then self.ActiveIndex = 1 end
    if self.ActiveIndex > count then self.ActiveIndex = count end
    for i, row in ipairs(self.SuggestionRows) do
        if i == self.ActiveIndex then
            row._hl:Show()
        else
            row._hl:Hide()
        end
    end
end

function Spellcheck:OpenOrCycleSuggestions()
    if not self:IsSuggestionEligible() then
        self:HideSuggestions()
        return
    end

    if self:IsSuggestionOpen() then
        self:MoveSelection(1)
        return
    end

    local suggestions = self:GetSuggestions(self.ActiveWord)
    if type(suggestions) ~= "table" then suggestions = {} end
    local sugCount = #suggestions
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:OpenOrCycleSuggestions word='" ..
            tostring(self.ActiveWord) .. "' suggestions=" .. tostring(sugCount))
    end
    if sugCount == 0 then
        self:HideSuggestions()
        return
    end

    self.ActiveSuggestions = suggestions
    self.ActiveIndex = 1
    self._suggestionOffset = 0 -- Reset pagination offset for new word
    self:ShowSuggestions()
end

function Spellcheck:ShowSuggestions()
    if not self.SuggestionFrame then return end
    if not self.ActiveSuggestions then return end

    -- Snapshot ActiveSuggestions so ResolveImplicitTrace can record rejections
    -- if the user bypasses all suggestions and manually retypes the word.
    if self.ActiveWord and self.ActiveRange then
        self._implicitTrace = {
            word        = self.ActiveWord,
            startPos    = self.ActiveRange.startPos,
            endPos      = self.ActiveRange.endPos,
            suggestions = self.ActiveSuggestions,
        }
    end

    local total = #self.ActiveSuggestions
    local offset = self._suggestionOffset or 0

    -- Smart Pagination: If we have room to fit exactly 6 items without
    -- needing a "More" row, do so.
    local pageRows = MAX_SUGGESTION_ROWS - 1 -- Default: save row 6 for pagination
    if total <= MAX_SUGGESTION_ROWS and offset == 0 then
        pageRows = MAX_SUGGESTION_ROWS
    end

    local hasMore = total > (offset + pageRows)

    -- If the suggestion frame is already visible and the suggestions
    -- haven't changed, skip updating to avoid per-frame work and debug spam.
    -- Bypassed when offset changed so pagination refreshes.
    if self.SuggestionFrame:IsShown() and self._lastShownSuggestions and
        self:SuggestionsEqual(self.ActiveSuggestions, self._lastShownSuggestions) and
        self._lastShownOffset == offset then
        return
    end

    local editBox = self.EditBox
    local x = self:GetCaretXOffset()
    self.SuggestionFrame:ClearAllPoints()
    -- Anchor above the editbox so the suggestions appear on top of the overlay.
    self.SuggestionFrame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", x, 4)

    local fontSize = 10
    if editBox and editBox.GetFont then
        local _, sz = editBox:GetFont()
        if sz then fontSize = sz end
    end
    local rowHeight = math_max(18, fontSize + 4)

    local maxWidth = 160
    local visibleRows = 0

    for i = 1, MAX_SUGGESTION_ROWS do
        local row = self.SuggestionRows[i]
        self:ApplyOverlayFont(row._fs)
        row:ClearAllPoints()
        row:SetSize(maxWidth, rowHeight)
        row:SetPoint("TOPLEFT", self.SuggestionFrame, "TOPLEFT", 6, -6 - ((i - 1) * rowHeight))

        if i <= pageRows then
            -- Regular Suggestion
            local sugIndex = offset + i
            local entry = self.ActiveSuggestions[sugIndex]
            if entry then
                row._fs:SetText(self:FormatSuggestionLabel(entry, i))
                row:Show()
                visibleRows = i
                local w = row._fs:GetStringWidth() + 30
                if w > maxWidth then maxWidth = w end
            else
                row:Hide()
            end
        elseif i == MAX_SUGGESTION_ROWS then
            -- Pagination Row (Row 6)
            if hasMore or offset > 0 then
                row:Show()
                visibleRows = i
                if hasMore then
                    row._fs:SetText("|cffbbbbbb" .. i .. ". More Suggestions »|r")
                else
                    row._fs:SetText("|cffbbbbbb" .. i .. ". « Back to Top|r")
                end
                local w = row._fs:GetStringWidth() + 30
                if w > maxWidth then maxWidth = w end
            else
                row:Hide()
            end
        end
    end

    for i = 1, MAX_SUGGESTION_ROWS do
        self.SuggestionRows[i]:SetWidth(maxWidth)
    end

    self.SuggestionFrame:SetSize(maxWidth + 10, (visibleRows * rowHeight) + 12)
    self:RefreshSuggestionSelection()

    if self.SuggestionClickCatcher then
        self.SuggestionClickCatcher:Show()
    end
    self.SuggestionFrame:Show()
    self._lastShownSuggestions = self.ActiveSuggestions
    self._lastShownOffset = offset
end

function Spellcheck:NextSuggestionsPage()
    if not self.ActiveSuggestions then return end

    -- Record that the current suggestion page was skipped
    if self.YALLM and self.YALLM.RecordRejection and self.ActiveWord then
        local offset = self._suggestionOffset or 0
        local rejected = {}
        for i = offset + 1, math_min(offset + 5, #self.ActiveSuggestions) do
            table_insert(rejected, self.ActiveSuggestions[i])
        end
        self.YALLM:RecordRejection(self.ActiveWord, rejected)
    end

    local total = #self.ActiveSuggestions
    local newOffset = (self._suggestionOffset or 0) + 5
    if newOffset >= total then
        newOffset = 0 -- Wrap around
    end
    self._suggestionOffset = newOffset
    self:ShowSuggestions()
end

function Spellcheck:HideSuggestions()
    if self.SuggestionFrame then
        self.SuggestionFrame:Hide()
    end
    if self.SuggestionClickCatcher then
        self.SuggestionClickCatcher:Hide()
    end
    self.ActiveSuggestions = nil
    self.ActiveIndex = 1
    self._lastShownSuggestions = nil

    -- Prune old learning data when the suggestion UI closes
    if self.YALLM and self.YALLM.Prune then
        -- Deferred so the prune runs after the frame has hidden
        C_Timer.After(0, function()
            self.YALLM:Prune("freq", self.YALLM:GetFreqCap())
            self.YALLM:Prune("bias", self.YALLM:GetBiasCap())
        end)
    end
end

function Spellcheck:ApplySuggestion(index)
    if not self.ActiveSuggestions or not self.ActiveRange then return end

    if index == MAX_SUGGESTION_ROWS then
        local total = #self.ActiveSuggestions
        local offset = self._suggestionOffset or 0
        if total > (offset + 5) or offset > 0 then
            self:NextSuggestionsPage()
            return
        end
    end

    -- Clear implicit trace on explicit selection
    self._implicitTrace = nil

    local sugIndex = (self._suggestionOffset or 0) + index
    local entry = self.ActiveSuggestions[sugIndex]
    if not entry then return end

    -- Was YALLM actually helpful here?
    local isUseful = false
    if self.ActiveSuggestions[1] then
        -- Find the "Natural" #1 candidate by looking for the best baseScore.
        -- We ignore entries without a baseScore (like "Ignore word").
        local naturalRank1 = nil
        for i = 1, #self.ActiveSuggestions do
            local cand = self.ActiveSuggestions[i]
            if cand.baseScore then
                if not naturalRank1 or cand.baseScore < naturalRank1.baseScore then
                    naturalRank1 = cand
                end
            end
        end

        if naturalRank1 then
            -- It was useful if our selected entry pushed ahead of the natural #1.
            local selectedVal = entry.value or entry.word
            local naturalVal = naturalRank1.value or naturalRank1.word

            if selectedVal == naturalVal then
                -- This was already the natural #1 or at least no worse.
                isUseful = false
            elseif entry.baseScore and entry.baseScore > naturalRank1.baseScore then
                -- This was worse than #1 naturally, but YALLM saved it.
                isUseful = true
            end
        end
    end

    -- Selection Bias Tracking
    if self.YALLM and self.YALLM.RecordSelection then
        local text = self.EditBox:GetText() or ""
        local startPos, endPos = self.ActiveRange.startPos, self.ActiveRange.endPos
        local original = text:sub(startPos, endPos)
        self.YALLM:RecordSelection(original, entry.word, isUseful)
    end

    -- Mark that a suggestion was just applied so higher-level Enter
    -- handlers can swallow the following Enter (applied via keyboard).
    self._justAppliedSuggestion = true
    if C_Timer and C_Timer.NewTimer then
        C_Timer.NewTimer(0.05, function()
            self._justAppliedSuggestion = nil
        end)
    end

    if type(entry) == "table" and entry.kind == "add" then
        local locale = self:GetLocale()
        self:AddUserWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText = self.EditBox:GetText() or ""
            self._expectedCursor = self.EditBox:GetCursorPosition()
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate underline cache — user sets changed, not the text.
        self._lastUnderlinesText = nil
        self:ScheduleRefresh()
        return
    elseif type(entry) == "table" and entry.kind == "ignore" then
        local locale = self:GetLocale()
        self:IgnoreWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText = self.EditBox:GetText() or ""
            self._expectedCursor = self.EditBox:GetCursorPosition()
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate underline cache — user sets changed, not the text.
        self._lastUnderlinesText = nil
        self:ScheduleRefresh()
        return
    end

    local replacement = (type(entry) == "table") and (entry.value or entry.word) or entry
    if not replacement then return end

    local text = self.EditBox and self.EditBox:GetText() or ""
    local startPos = self.ActiveRange.startPos
    local endPos = self.ActiveRange.endPos
    if not startPos or not endPos then return end

    local before = text:sub(1, startPos - 1)
    local after = text:sub(endPos + 1)
    local newText = before .. replacement .. after

    -- Snapshot the pre-replacement text so we can seamlessly Undo (Ctrl+Z)
    -- spellchecker corrections even if the new word is the same length.
    if YapperTable and YapperTable.History and self.EditBox then
        YapperTable.History:AddSnapshot(self.EditBox, true)
    end

    self.EditBox:SetText(newText)
    local cursorPos = #before + #replacement
    self.EditBox:SetCursorPosition(cursorPos)
    -- Prevent the following character insertion (numeric hotkey) from
    -- being appended to the editbox; EditBox.OnTextChanged will remove it.
    self._suppressNextChar = true
    self._suppressChar = tostring(index)
    self._expectedText = newText
    self._expectedCursor = cursorPos
    self:HideSuggestions()
    self._textChangedFlag = true

    -- Record the accepted correction for adaptive learning
    if self.YALLM and self.YALLM.RecordSelection then
        local original = text:sub(startPos, endPos)
        self.YALLM:RecordSelection(original, replacement)
    end

    self:ScheduleRefresh()
end

