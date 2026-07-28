--[[
    Spellcheck/UI.lua
    EditBox binding, text input event handlers, font measurement,
    hint frame, suggestion dropdown display and keyboard navigation,
    and suggestion application.
]]

local _, YapperTable      = ...
local Spellcheck          = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local SuggestionKey       = Spellcheck.SuggestionKey
local MAX_SUGGESTION_ROWS = Spellcheck._MAX_SUGGESTION_ROWS
local IsDebugEnabled      = Spellcheck.IsDebugEnabled


-- Re-localise Lua globals.
local type                = type
local pairs               = pairs
local ipairs              = ipairs
local tostring            = tostring
local tonumber            = tonumber
local math_abs            = math.abs
local math_min            = math.min
local math_max            = math.max
local math_floor          = math.floor
local string_sub          = string.sub
local string_format       = string.format
local table_insert        = table.insert

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

--- Temporarily rebind spellcheck to the multiline editor.
--- Recolouring targets whichever EditBox is bound, so the only work here is
--- moving the suggestion/hint frames into the multiline container and
--- flagging multiline anchoring via MLScrollFrame.  Call UnbindMultiline()
--- on exit.
---@param editBox       Frame  The multiline EditBox.
---@param containerFrame Frame  The multiline container (for suggestion/hint parenting).
---@param scrollFrame   Frame  The ScrollFrame wrapping the EditBox (bind flag).
function Spellcheck:BindMultiline(editBox, containerFrame, scrollFrame)
    -- Save originals so we can restore them on exit.
    self._mlSavedEditBox     = self.EditBox
    self._mlSavedOverlay     = self.Overlay
    self._mlSavedScrollFrame = self.MLScrollFrame

    -- Clear any single-line underlines/hints before switching.
    self:OnOverlayHide()

    self.EditBox       = editBox
    self.Overlay       = containerFrame
    self.MLScrollFrame = scrollFrame

    -- Hook OnCursorChanged and OnMouseUp on the multiline EditBox so
    -- ActiveWord stays current as the cursor moves and right-click works.
    -- Both handlers guard on box == self.EditBox so they silently no-op
    -- after UnbindMultiline reassigns self.EditBox back to the overlay.
    if editBox and editBox.HookScript then
        editBox:HookScript("OnCursorChanged", function(box, x, y, w, h)
            if box ~= self.EditBox then return end
            self:OnCursorChanged(box, x, y, w, h)
        end)
        editBox:HookScript("OnMouseUp", function(box, button)
            if box ~= self.EditBox then return end
            if button == "RightButton" then
                self:UpdateActiveWord()
                if self:IsSuggestionEligible() then
                    self:OpenOrCycleSuggestions()
                end
            end
        end)
    end

    -- Reparent overlay-child frames to the multiline container so they
    -- remain visible when the single-line overlay is hidden.
    local function reparent(frame)
        if frame and containerFrame then
            frame:SetParent(containerFrame)
        end
    end
    reparent(self.SuggestionFrame)
    -- SetParent() resets the frame's strata to the new parent's strata (HIGH).
    -- Re-assert TOOLTIP so suggestion rows stay above the catcher (also TOOLTIP
    -- but at frame level 1, far below the buttons at 200+).
    if self.SuggestionFrame then
        self.SuggestionFrame:SetFrameStrata("TOOLTIP")
        self.SuggestionFrame:SetFrameLevel(200)
    end
    reparent(self.HintFrame)
    if self.HintFrame then
        self.HintFrame:SetFrameStrata("TOOLTIP")
    end

    self:ScheduleRefresh(0)
end

--- Restore spellcheck to the single-line overlay after multiline editing.
function Spellcheck:UnbindMultiline()
    if not self._mlSavedEditBox then return end -- not bound to multiline

    -- Clear any multiline underlines before switching back.
    self:OnOverlayHide()

    local oldOverlay         = self._mlSavedOverlay

    self.EditBox             = self._mlSavedEditBox
    self.Overlay             = oldOverlay
    self.MLScrollFrame       = self._mlSavedScrollFrame

    self._mlSavedEditBox     = nil
    self._mlSavedOverlay     = nil
    self._mlSavedScrollFrame = nil

    -- Reparent overlay-child frames back to the single-line overlay.
    local function reparent(frame)
        if frame and oldOverlay then
            frame:SetParent(oldOverlay)
        end
    end
    reparent(self.SuggestionFrame)
    -- Re-assert TOOLTIP strata after reparenting back to the overlay.
    if self.SuggestionFrame then
        self.SuggestionFrame:SetFrameStrata("TOOLTIP")
        self.SuggestionFrame:SetFrameLevel(200)
    end
    reparent(self.HintFrame)
    if self.HintFrame then
        self.HintFrame:SetFrameStrata("TOOLTIP")
    end
end

function Spellcheck:PurgeOtherDictionaries(keepLocale)
    -- Build the set of locales currently serving as bases for loaded
    -- delta dictionaries.
    local activeBases = {}
    if self.Dictionaries then
        for _, dict in pairs(self.Dictionaries) do
            if type(dict) == "table" and dict.extends then
                activeBases[dict.extends] = true
            end
        end
    end

    -- Identify and protect the base dictionary if the keepLocale depends on it.
    local keepBase = nil
    local keepLoaded = self.Dictionaries and self.Dictionaries[keepLocale]
    if keepLoaded then
        keepBase = self.Dictionaries[keepLocale].extends
    end

    -- If the target locale isn't loaded yet, protect currently-active bases
    -- until EnsureLocale() finishes the locale switch.
    local protectActiveBases = not keepLoaded

    if self.Dictionaries then
        for locale, dict in pairs(self.Dictionaries) do
            if locale ~= keepLocale
                and locale ~= keepBase
                and not (protectActiveBases and activeBases[locale])
            then
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
            if locale ~= keepLocale
                and locale ~= keepBase
                and not (protectActiveBases and activeBases[locale])
            then
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
    self:ClearSuggestionCache()
    self.UserDictCache = {}

    -- Hidden internal suggestion state
    self._lastSuggestionsText = nil
    self._lastSuggestionsLocale = nil
    self.ActiveSuggestions = nil

    -- Cleanup UI state
    YapperTable.Recolour:Clear(self.EditBox)
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
        if self.YAS and self.YAS.Init then
            self.YAS:Init()
        end
        if not self:EnsureLocale(locale, true) then
            -- If the addon is loaded but the locale is unavailable, it was purged.
            local addon = self:GetLocaleAddon(locale)
            local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
            if addon and isLoaded and isLoaded(addon)
                and not self:IsLocaleAvailable(locale) then
                if self.Notify then
                    self:Notify("Yapper: The dictionary for " ..
                    locale .. " was purged to save memory. You must /reload your UI to re-enable it.")
                end
            end
            return false
        end
    else
        -- When disabled, we don't automatically unload (user might just be toggling).
        -- The explicit "Unload" is handled by the UI popup or manual call.
        YapperTable.Recolour:Clear(self.EditBox)
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
        -- Read canonical text: display text may end in a "|r" reset, which
        -- would hide the real last character from this check.
        local text = YapperTable.Recolour.CanonicalText(editBox)
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

    -- Capture cursor height (= line height ≈ font size) and visual Y for
    -- multiline suggestion/hint anchoring (immune to overlay resizing done
    -- by addons like ElvUI).
    if type(y) == "number" then
        self._lastCursorVisY = y
    end
    if type(h) == "number" and h > 0 then
        self._lastCursorH = h
    end

    -- Early-exit guard: if neither the cursor position nor the text has changed
    -- since the last call, skip all work. This prevents redundant processing
    -- during rapid OnCursorChanged fires (e.g. holding an arrow key).
    -- Compared in canonical space so our own recolour injection doesn't
    -- register as a change.
    local curText, curPos = YapperTable.Recolour.CanonicalTextAndCursor(editBox)
    if curPos == self._lastOnCursorPos and curText == self._lastOnCursorText then
        return
    end
    self._lastOnCursorPos  = curPos
    self._lastOnCursorText = curText

    self:UpdateActiveWord()
    self:UpdateHint()

    -- No rendering work here: injected colour does not move with the caret,
    -- so cursor-only changes need no recolour pass. (The large-text scan
    -- window recenters on the next text-driven Apply.)
end

function Spellcheck:OnOverlayHide()
    self:HideSuggestions()
    YapperTable.Recolour:Clear(self.EditBox)
    self:HideHint()
end

function Spellcheck:ScheduleRefresh(delay)
    if not self:IsEnabled() then
        self:HideSuggestions()
        YapperTable.Recolour:Clear(self.EditBox)
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
        YapperTable.Recolour:Clear(self.EditBox)
        self:HideHint()
        return
    end

    YapperTable.Recolour:Apply(self.EditBox)
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

    -- The catcher sits at a deliberately LOW frame level so suggestion row
    -- buttons (which are set to a much higher level) always receive clicks
    -- first.  Without this, the catcher intercepts clicks that should go to
    -- the rows, silently swallowing them instead of letting them fire.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(1) -- must stay below the suggestion frame
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function()
        self:HideSuggestions()
    end)
    catcher:Hide()
    self.SuggestionClickCatcher = catcher

    local frame = CreateFrame("Frame", nil, self.Overlay, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200) -- well above catcher; buttons get 201+
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

        -- Keyboard-selection highlight (controlled by RefreshSuggestionSelection).
        local hlFrame = CreateFrame("Frame", nil, frame)
        hlFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        hlFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        hlFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
        local hlTex = hlFrame:CreateTexture(nil, "ARTWORK")
        hlTex:SetAllPoints(hlFrame)
        hlTex:SetColorTexture(1, 1, 1, 0.08)
        hlFrame:Hide()

        -- Hover highlight: shown on mouse-over, independent of keyboard selection.
        local hoverFrame = CreateFrame("Frame", nil, frame)
        hoverFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        hoverFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        hoverFrame:SetFrameLevel(btn:GetFrameLevel() + 6)
        local hoverTex = hoverFrame:CreateTexture(nil, "ARTWORK")
        hoverTex:SetAllPoints(hoverFrame)
        hoverTex:SetColorTexture(1, 1, 1, 0.15)
        hoverFrame:Hide()

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetText("-")

        btn._fs      = fs
        btn._hl      = hlFrame
        btn._hoverHL = hoverFrame
        btn._index   = i
        local idx    = i
        btn:SetScript("OnEnter", function()
            self.ActiveIndex = idx
            self:RefreshSuggestionSelection()
            btn._hoverHL:Show()
        end)
        btn:SetScript("OnLeave", function()
            btn._hoverHL:Hide()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySuggestion(idx)
        end)

        rows[i] = btn
    end

    self.SuggestionFrame = frame
    self.SuggestionRows = rows

    if YapperTable.Core and type(YapperTable.Core.RegisterFrame) == "function" then
        YapperTable.Core:RegisterFrame("Spellcheck", "SuggestionFrame", frame)
        YapperTable.Core:RegisterFrame("Spellcheck", "SuggestionClickCatcher", catcher)
    end
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

    if YapperTable.Core and type(YapperTable.Core.RegisterFrame) == "function" then
        YapperTable.Core:RegisterFrame("Spellcheck", "HintFrame", frame)
    end
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
    local cursor = YapperTable.Recolour.CanonicalCursor(self.EditBox)
    local word = self.ActiveWord
    -- If we already have a timer scheduled for the same word+cursor, leave it.
    if self._hintTimer and self._pendingHintWord == word and self._pendingHintCursor == cursor then
        return
    end
    self:CancelHintTimer()
    self._pendingHintWord = word
    self._pendingHintCursor = cursor
    if IsDebugEnabled() then
        self:Notify("Spellcheck:ScheduleHintShow word='" .. tostring(word) .. "' cursor=" .. tostring(cursor))
    end
    if C_Timer and C_Timer.NewTimer then
        self._hintTimer = C_Timer.NewTimer(self.HintDelay, function()
            -- If caret or word moved, abort showing.
            if not self.EditBox then return end
            local curCursor = YapperTable.Recolour.CanonicalCursor(self.EditBox)
            if IsDebugEnabled() then
                self:Notify("Spellcheck:HintTimer fired; curCursor=" ..
                    tostring(curCursor) .. " pending=" .. tostring(self._pendingHintCursor))
            end
            if curCursor ~= self._pendingHintCursor then
                if IsDebugEnabled() then
                    self:Notify("Spellcheck:HintTimer abort due to cursor move")
                end
                return
            end
            if self.ActiveWord ~= self._pendingHintWord then
                if IsDebugEnabled() then
                    self:Notify("Spellcheck:HintTimer abort due to word change")
                end
                return
            end
            self:ShowHint()
            if IsDebugEnabled() then
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
        if IsDebugEnabled() then
            self:Notify("Spellcheck:ScheduleHintShow immediate fallback show")
        end
        self:ShowHint()
        self._lastHintWord = self._pendingHintWord
        self._lastHintCursor = self._pendingHintCursor
        self._pendingHintWord = nil
        self._pendingHintCursor = nil
    end
end

--- Set manual pixel offsets for spellcheck tooltips.
---@param hintX number?
---@param hintY number?
---@param suggestX number?
---@param suggestY number?
function Spellcheck:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY)
    self._hintOffsetX = hintX or self._hintOffsetX
    self._hintOffsetY = hintY or self._hintOffsetY
    self._suggestOffsetX = suggestX or self._suggestOffsetX
    self._suggestOffsetY = suggestY or self._suggestOffsetY

    -- Refresh currently shown frames to reflect new offsets immediately.
    if self.HintFrame and self.HintFrame:IsShown() then
        self:ShowHint()
    end
    if self.SuggestionFrame and self.SuggestionFrame:IsShown() then
        self:ShowSuggestions()
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
    if self.MLScrollFrame
        and type(self._lastCursorVisX) == "number" and type(self._lastCursorVisY) == "number" then
        -- Multiline: anchor just under the visual caret line (see
        -- ShowSuggestions for why prefix measurement cannot be used here).
        local boxWidth = (self.EditBox and self.EditBox:GetWidth()) or 200
        local x = math_max(0, math_min(self._lastCursorVisX + (self._hintOffsetX or 0), boxWidth - 10))
        local y = self._lastCursorVisY - (self._lastCursorH or 0) + (self._hintOffsetY or -2)
        self.HintFrame:SetPoint("TOPLEFT", self.EditBox, "TOPLEFT", x, y)
    else
        self.HintFrame:SetPoint("TOPLEFT", self.EditBox, "BOTTOMLEFT", self._hintOffsetX or 0, self._hintOffsetY or -2)
    end
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
    local cursor = YapperTable.Recolour.CanonicalCursor(self.EditBox)
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
            local offset = self._suggestionOffset or 0
            local relativeIndex = (self.ActiveIndex or 1) - offset
            local row = self.SuggestionRows and self.SuggestionRows[relativeIndex]
            if row and row._isPagination then
                self:NextSuggestionsPage()
            else
                self:ApplySuggestion(relativeIndex)
            end
            return true
        end
        if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
            -- Set suppression before applying so OnChar won't append the digit.
            self._suppressNextChar = true
            self._suppressChar = key
            -- For non-replacement actions (add/ignore), keep the current
            -- text/cursor as the expected state so OnChar can restore it.
            if self.EditBox then
                self._expectedText, self._expectedCursor =
                    YapperTable.Recolour.CanonicalTextAndCursor(self.EditBox)
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

    local offset = self._suggestionOffset or 0
    local startRel = self.ActiveIndex - offset
    local nextRel = startRel

    for _ = 1, MAX_SUGGESTION_ROWS do
        nextRel = nextRel + delta
        if nextRel < 1 then nextRel = MAX_SUGGESTION_ROWS end
        if nextRel > MAX_SUGGESTION_ROWS then nextRel = 1 end

        local row = self.SuggestionRows[nextRel]
        if row and row:IsShown() then
            self.ActiveIndex = offset + nextRel
            self:RefreshSuggestionSelection()
            return
        end
    end
end

function Spellcheck:RefreshSuggestionSelection()
    if not self.ActiveSuggestions then return end
    local count = #self.ActiveSuggestions
    if count == 0 then
        for _, row in ipairs(self.SuggestionRows) do row._hl:Hide() end
        return
    end
    if not self.ActiveIndex or self.ActiveIndex < 1 then self.ActiveIndex = 1 end
    
    local offset = self._suggestionOffset or 0
    -- Allow ActiveIndex to reach the pagination row (offset + MAX_SUGGESTION_ROWS)
    local maxAllowed = math_max(count, offset + MAX_SUGGESTION_ROWS)
    if self.ActiveIndex > maxAllowed then self.ActiveIndex = maxAllowed end

    local relativeIndex = self.ActiveIndex - offset

    for i, row in ipairs(self.SuggestionRows) do
        if i == relativeIndex then
            row._hl:Show()

            if row:IsShown() and YapperTable.API then
                local text = row._fs:GetText() or ""
                -- Strip color codes for cleaner TTS
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                YapperTable.API:Fire("SPELLCHECK_SUGGESTION_HIGHLIGHTED", text, self.ActiveIndex, count)
            end
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
    if IsDebugEnabled() then
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
    -- Only snapshot once per word — don't overwrite mid-edit or the original typo is lost.
    if self.ActiveWord and self.ActiveRange and not self._implicitTrace then
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
    self.SuggestionFrame:ClearAllPoints()
    if self.MLScrollFrame
        and type(self._lastCursorVisX) == "number" and type(self._lastCursorVisY) == "number" then
        -- Multiline: anchor at the visual caret coordinates handed to
        -- OnCursorChanged. Prefix measurement (GetCaretXOffset) assumes a
        -- single line and cannot locate the caret on wrapped lines.
        local boxWidth = (editBox and editBox:GetWidth()) or 200
        local x = math_max(0, math_min(self._lastCursorVisX + (self._suggestOffsetX or 0), boxWidth - 10))
        local y = self._lastCursorVisY + (self._suggestOffsetY or 4)
        self.SuggestionFrame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", x, y)
    else
        local x = self:GetCaretXOffset()
        -- Anchor above the editbox so the suggestions appear on top of the overlay.
        self.SuggestionFrame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", x + (self._suggestOffsetX or 0),
            self._suggestOffsetY or 4)
    end

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
                row._isPagination = false
                row:Show()
                visibleRows = i
                local w = row._fs:GetStringWidth() + 30
                if w > maxWidth then maxWidth = w end
            else
                row._isPagination = false
                row:Hide()
            end
        elseif i == MAX_SUGGESTION_ROWS then
            -- Pagination Row (Row 6)
            if hasMore or offset > 0 then
                row._isPagination = true
                row:Show()
                visibleRows = i
                if hasMore then
                    -- TODO: Localization required for German and other locales.
                    row._fs:SetText("|cffbbbbbb" .. i .. ". More Suggestions »|r")
                else
                    row._fs:SetText("|cffbbbbbb" .. i .. ". « Back to Top|r")
                end
                local w = row._fs:GetStringWidth() + 30
                if w > maxWidth then maxWidth = w end
            else
                row._isPagination = false
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

    -- Notify external addons that suggestions are being shown.
    if self.ActiveWord and YapperTable.API then
        local words = {}
        for i, entry in ipairs(self.ActiveSuggestions) do
            words[i] = (type(entry) == "table") and (entry.word or entry.value) or entry
        end
        YapperTable.API:Fire("SPELLCHECK_SUGGESTION", self.ActiveWord, words)
    end
end

function Spellcheck:NextSuggestionsPage()
    if not self.ActiveSuggestions then return end

    -- Record that the current suggestion page was skipped
    if self.YAS and self.YAS.RecordRejection and self.ActiveWord then
        local offset = self._suggestionOffset or 0
        local rejected = {}
        for i = offset + 1, math_min(offset + 5, #self.ActiveSuggestions) do
            table_insert(rejected, self.ActiveSuggestions[i])
        end
        local locale = self:GetLocale()
        self.YAS:RecordRejection(self.ActiveWord, rejected, locale)
    end

    local total = #self.ActiveSuggestions
    local newOffset = (self._suggestionOffset or 0) + 5
    if newOffset >= total then
        newOffset = 0 -- Wrap around
    end
    self._suggestionOffset = newOffset
    self.ActiveIndex = newOffset + 1
    self._lastPageTurnFrame = GetTime()
    self._justAppliedSuggestion = GetTime()
    C_Timer.After(0.05, function() self._justAppliedSuggestion = nil end)
    self:ShowSuggestions()
end

function Spellcheck:HideSuggestions()
    if self.SuggestionFrame then
        self.SuggestionFrame:Hide()
    end
    if self.SuggestionClickCatcher then
        self.SuggestionClickCatcher:Hide()
    end
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_CLOSED")
    end
    self.ActiveSuggestions = nil
    self.ActiveIndex = 1
    self._lastShownSuggestions = nil

    -- Prune old learning data when the suggestion UI closes
    if self.YAS and self.YAS.Prune then
        -- Deferred so the prune runs after the frame has hidden
        C_Timer.After(0, function()
            self.YAS:Prune("freq", self.YAS:GetFreqCap())
            self.YAS:Prune("bias", self.YAS:GetBiasCap())
        end)
    end
end

function Spellcheck:ApplySuggestion(index)
    if not self.ActiveSuggestions or not self.ActiveRange then return end

    -- Ignore applications in the same frame as a page turn (prevents keyboard double-trigger)
    if self._lastPageTurnFrame and GetTime() == self._lastPageTurnFrame then
        return
    end

    -- Check if the targeted row is a pagination control (mouse click path).
    local row = self.SuggestionRows and self.SuggestionRows[index]
    if row and row._isPagination then
        self:NextSuggestionsPage()
        return
    end

    -- Clear implicit trace on explicit selection
    self._implicitTrace = nil

    local sugIndex = (self._suggestionOffset or 0) + index
    local entry = self.ActiveSuggestions[sugIndex]
    if not entry then return end

    -- Was YAS actually helpful here?
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
                -- This was worse than #1 naturally, but YAS saved it.
                isUseful = true
            end
        end
    end

    -- Selection Bias Tracking
    if self.YAS and self.YAS.RecordSelection then
        local locale = self:GetLocale()
        local selectedVal = entry.value or entry.word
        self.YAS:RecordSelection(original, selectedVal, isUseful, locale)
    end

    -- Mark that a suggestion was just applied so higher-level Enter
    -- handlers can swallow the following Enter (applied via keyboard).
    self._justAppliedSuggestion = GetTime()
    if C_Timer and C_Timer.NewTimer then
        C_Timer.NewTimer(0.05, function()
            self._justAppliedSuggestion = nil
        end)
    end

    if type(entry) == "table" and entry.kind == "add" then
        local locale = self:GetLocale()
        self:AddUserWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText, self._expectedCursor =
                YapperTable.Recolour.CanonicalTextAndCursor(self.EditBox)
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate the detection cache — user sets changed, not the text.
        YapperTable.Recolour:Invalidate()
        self:ScheduleRefresh()
        return
    elseif type(entry) == "table" and entry.kind == "ignore" then
        local locale = self:GetLocale()
        self:IgnoreWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText, self._expectedCursor =
                YapperTable.Recolour.CanonicalTextAndCursor(self.EditBox)
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate the detection cache — user sets changed, not the text.
        YapperTable.Recolour:Invalidate()
        self:ScheduleRefresh()
        return
    elseif type(entry) == "table" and entry.kind == "split" then
        -- Apply compound split as a direct text replacement.
        -- YAS recording is intentionally skipped: both halves are already
        -- valid dictionary words, so there is nothing for the learner to store.
        -- (The first RecordSelection call above receives entry.word = nil and
        -- safely no-ops via YAS's own empty-string guard.)
        local splitReplacement = entry.value
        if not splitReplacement then return end
        local splitText  = self.EditBox and YapperTable.Recolour.CanonicalText(self.EditBox) or ""
        local splitStart = self.ActiveRange.startPos
        local splitEnd   = self.ActiveRange.endPos
        if not splitStart or not splitEnd then return end
        local splitBefore = splitText:sub(1, splitStart - 1)
        local splitAfter  = splitText:sub(splitEnd + 1)
        local splitNew    = splitBefore .. splitReplacement .. splitAfter
        if YapperTable and YapperTable.History and self.EditBox then
            YapperTable.History:AddSnapshot(self.EditBox, true)
        end
        self.EditBox:SetText(splitNew)
        local splitCursor = #splitBefore + #splitReplacement
        self.EditBox:SetCursorPosition(splitCursor)
        local splitBoxRef = self.EditBox
        C_Timer.After(0, function()
            if splitBoxRef and splitBoxRef.SetFocus then splitBoxRef:SetFocus() end
        end)
        self._suppressNextChar = true
        self._suppressChar = tostring(index)
        self._expectedText = splitNew
        self._expectedCursor = splitCursor
        self:HideSuggestions()
        self._textChangedFlag = true
        if YapperTable.API then
            YapperTable.API:Fire("SPELLCHECK_APPLIED", splitText:sub(splitStart, splitEnd), splitReplacement)
        end
        self:ScheduleRefresh()
        return
    end

    local replacement = (type(entry) == "table") and (entry.value or entry.word) or entry
    if not replacement then return end

    local text = self.EditBox and YapperTable.Recolour.CanonicalText(self.EditBox) or ""
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

    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_TEXT_CHANGED", newText, true, self.EditBox)
    end
    -- Restore focus after one frame so all click-event processing finishes
    -- before the focus claim fires.  Without deferral the claim can be
    -- immediately stolen back by another frame's focus handler.
    local editBoxRef = self.EditBox
    C_Timer.After(0, function()
        if editBoxRef and editBoxRef.SetFocus then editBoxRef:SetFocus() end
    end)
    -- Prevent the following character insertion (numeric hotkey) from
    -- being appended to the editbox; EditBox.OnTextChanged will remove it.
    self._suppressNextChar = true
    self._suppressChar = tostring(index)
    self._expectedText = newText
    self._expectedCursor = cursorPos
    self:HideSuggestions()
    self._textChangedFlag = true

    -- Record the accepted correction for adaptive learning
    if self.YAS and self.YAS.RecordSelection then
        local original = text:sub(startPos, endPos)
        self.YAS:RecordSelection(original, replacement, 0.5, self:GetLocale())
    end

    -- Notify external addons that a spellcheck correction was applied.
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_APPLIED", text:sub(startPos, endPos), replacement)
    end

    self:ScheduleRefresh()
end
function Spellcheck:GetCaretXOffset()
    local editBox = self.EditBox
    if not editBox then return 0 end

    -- Canonical read: measurement must use the escape-free prefix or the
    -- anchor drifts right by the injected colour-code bytes.
    local text, cursor = YapperTable.Recolour.CanonicalTextAndCursor(editBox)
    local prefix = text:sub(1, cursor)

    local leftInset = 0
    if editBox.GetTextInsets then
        leftInset = select(1, editBox:GetTextInsets()) or 0
    end

    -- MeasureFS is now parented to the Overlay (same scale as the EditBox),
    -- so GetStringWidth() is already in the correct coordinate space.
    local width = self:MeasureText(prefix)
    local scroll = self:GetScrollOffset()

    local x = leftInset + width - scroll

    -- Clamp to the visible text area of the EditBox to prevent the tooltip
    -- from flying off-screen or detaching during heavy horizontal scrolling.
    local boxWidth = editBox:GetWidth() or 200
    return math_max(leftInset, math_min(x, boxWidth - 10))
end

function Spellcheck:ApplyOverlayFont(fontString, maxSize)
    local editBox = self.EditBox
    if not editBox or not editBox.GetFont then return 10 end
    local face, size, flags = editBox:GetFont()
    if face and size then
        if maxSize and size > maxSize then size = maxSize end
        local curFace, curSize, curFlags = fontString:GetFont()
        if curFace ~= face or curSize ~= size or curFlags ~= flags then
            fontString:SetFont(face, size, flags or "")
        end
    end
    return size or 10
end

function Spellcheck:MeasureText(text)
    if not self.MeasureFS then return 0 end
    local editBox = self.EditBox
    if editBox and editBox.GetFont then
        local face, size, flags = editBox:GetFont()
        if face and size then
            local curFace, curSize, curFlags = self.MeasureFS:GetFont()
            if curFace ~= face or curSize ~= size or curFlags ~= flags then
                self.MeasureFS:SetFont(face, size, flags or "")
            end
        end
        -- Also synchronize character spacing if the EditBox uses it (e.g. custom skins)
        if editBox.GetSpacing and self.MeasureFS.SetSpacing then
            local spacing = editBox:GetSpacing() or 0
            if (self.MeasureFS:GetSpacing() or 0) ~= spacing then
                self.MeasureFS:SetSpacing(spacing)
            end
        end
    end
    self.MeasureFS:SetText(text or "")
    return self.MeasureFS:GetStringWidth() or 0
end

-- Derive the horizontal scroll offset of a single-line EditBox.
-- WoW doesn't expose GetHorizontalScroll() for EditBoxes; we use the
-- visual cursor X that Blizzard passes to OnCursorChanged instead.
function Spellcheck:GetScrollOffset()
    if not self.EditBox or not self._lastCursorVisX then return 0 end
    -- Canonical cursor: cache key and prefix slicing both operate in
    -- escape-free space.
    local cursor = YapperTable.Recolour.CanonicalCursor(self.EditBox)
    if cursor == 0 then
        self._lastScrollCursor = 0
        self._lastScrollValue  = 0
        return 0
    end
    -- Cache by cursor position: MeasureText is expensive (SetText + GetStringWidth).
    -- The scroll offset can only change when the cursor moves, so skip re-measuring
    -- when the cursor hasn't changed since the last call.
    if self._lastScrollCursor == cursor then
        return self._lastScrollValue or 0
    end
    local text = YapperTable.Recolour.CanonicalText(self.EditBox)
    local prefix = text:sub(1, cursor)
    local absoluteX = self:MeasureText(prefix)
    local leftInset = 0
    if self.EditBox.GetTextInsets then
        leftInset = select(1, self.EditBox:GetTextInsets()) or 0
    end
    local offset           = (leftInset + absoluteX) - self._lastCursorVisX
    offset                 = offset > 0 and offset or 0
    self._lastScrollCursor = cursor
    self._lastScrollValue  = offset
    return offset
end
