--[[
    Spellcheck.lua
    Lightweight spellcheck for the overlay editbox.

    Uses packaged dictionary tables registered at load time.
]]

local _, YapperTable = ...

local Spellcheck = {}
YapperTable.Spellcheck = Spellcheck

Spellcheck.Dictionaries = {}
Spellcheck.KnownLocales = {
    "enUS",
    "enGB",
    "frFR",
    "deDE",
    "esES",
    "esMX",
    "itIT",
    "ptBR",
    "ruRU",
}
Spellcheck.LocaleAddons = {
    frFR = "Yapper_Dict_frFR",
    deDE = "Yapper_Dict_deDE",
    esES = "Yapper_Dict_esES",
    esMX = "Yapper_Dict_esMX",
    itIT = "Yapper_Dict_itIT",
    ptBR = "Yapper_Dict_ptBR",
    ruRU = "Yapper_Dict_ruRU",
}
Spellcheck.EditBox = nil
Spellcheck.Overlay = nil
Spellcheck.MeasureFS = nil
Spellcheck.UnderlinePool = {}
Spellcheck.Underlines = {}
Spellcheck.SuggestionFrame = nil
Spellcheck.SuggestionRows = {}
Spellcheck.ActiveSuggestions = nil
Spellcheck.ActiveIndex = 1
Spellcheck.ActiveWord = nil
Spellcheck.ActiveRange = nil
Spellcheck.HintFrame = nil
Spellcheck._debounceTimer = nil
Spellcheck.UserDictCache = {}
Spellcheck._pendingLocaleLoads = {}
Spellcheck._debugLoadedLocales = {}

local MAX_SUGGESTION_ROWS = 6
local SCORE_WEIGHTS = {
    lenDiff = 0.25,
    prefix = 0.15,
    letterBag = 0.20,
    bigram = 0.16,
    longerPenalty = 0.12,
}

local function Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

local function NormalizeWord(word)
    if type(word) ~= "string" then return "" end
    return (word:gsub("%u", string.lower))
end

local function SuggestionKey(entry)
    if type(entry) == "string" then
        return "word:" .. entry
    end
    if type(entry) == "table" then
        local kind = entry.kind or "word"
        local value = entry.value or entry.word or ""
        return kind .. ":" .. value
    end
    return tostring(entry)
end

local function IsWordByte(byte)
    if byte >= 128 then
        return true
    end
    if byte == 39 then -- apostrophe
        return true
    end
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

local function IsWordStartByte(byte)
    if byte >= 128 then
        return true
    end
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

function Spellcheck:RegisterDictionary(locale, data)
    if type(locale) ~= "string" or locale == "" or type(data) ~= "table" then
        return
    end

    local words = data.words or {}
    local existing = self.Dictionaries[locale]
    local set = existing and existing.set or {}
    local index = existing and existing.index or {}
    local outWords = existing and existing.words or {}

    for _, word in ipairs(words) do
        if type(word) == "string" and word ~= "" then
            local w = NormalizeWord(word)
            if not set[w] then
                set[w] = true
                outWords[#outWords + 1] = word
                local key = w:sub(1, 1)
                if key ~= "" then
                    index[key] = index[key] or {}
                    index[key][#index[key] + 1] = w
                end
            end
        end
    end

    self.Dictionaries[locale] = {
        locale = locale,
        words = outWords,
        set = set,
        index = index,
    }

    if YapperTable and YapperTable.Config
        and YapperTable.Config.System
        and YapperTable.Config.System.DEBUG
        and not self._debugLoadedLocales[locale] then
        self._debugLoadedLocales[locale] = true
        if C_Timer and C_Timer.NewTimer then
            C_Timer.NewTimer(0.2, function()
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                    DEFAULT_CHAT_FRAME:AddMessage("Yapper: dictionary registered for " .. tostring(locale))
                end
            end)
        elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("Yapper: dictionary registered for " .. tostring(locale))
        end
    end

    local cfg = self:GetConfig()
    if cfg and cfg.Locale == locale and self:IsEnabled() then
        -- Coalesce multiple rapid registrations for the same locale
        -- (chunked dictionaries) so we don't schedule a rebuild for
        -- every chunk. Schedule a single short-timer refresh instead.
        self._pendingLocaleRefreshTimers = self._pendingLocaleRefreshTimers or {}
        if C_Timer and C_Timer.NewTimer then
            if not self._pendingLocaleRefreshTimers[locale] then
                self._pendingLocaleRefreshTimers[locale] = C_Timer.NewTimer(0.08, function()
                    self._pendingLocaleRefreshTimers[locale] = nil
                    if self:IsEnabled() then
                        self:ScheduleRefresh()
                    end
                end)
            end
        else
            self:ScheduleRefresh()
        end
    end
end

function Spellcheck:GetAvailableLocales()
    local out = {}
    for locale in pairs(self.Dictionaries) do
        out[#out + 1] = locale
    end
    table.sort(out)
    return out
end

function Spellcheck:GetKnownLocales()
    local out = {}
    local seen = {}
    for i = 1, #self.KnownLocales do
        local locale = self.KnownLocales[i]
        out[#out + 1] = locale
        seen[locale] = true
    end
    for locale in pairs(self.LocaleAddons) do
        if not seen[locale] then
            out[#out + 1] = locale
            seen[locale] = true
        end
    end
    table.sort(out)
    return out
end

function Spellcheck:IsLocaleAvailable(locale)
    return self.Dictionaries[locale] ~= nil
end

function Spellcheck:GetLocaleAddon(locale)
    return self.LocaleAddons[locale]
end

function Spellcheck:HasLocaleAddon(locale)
    local addon = self:GetLocaleAddon(locale)
    if not addon then return false end
    if C_AddOns and C_AddOns.GetAddOnInfo then
        return C_AddOns.GetAddOnInfo(addon) ~= nil
    end
    if GetAddOnInfo then
        return GetAddOnInfo(addon) ~= nil
    end
    return false
end

function Spellcheck:CanLoadLocale(locale)
    local addon = self:GetLocaleAddon(locale)
    if not addon then
        return self:IsLocaleAvailable(locale)
    end
    if IsAddOnLoaded and IsAddOnLoaded(addon) then
        return true
    end
    return self:HasLocaleAddon(locale)
end

function Spellcheck:Notify(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

function Spellcheck:EnsureLocale(locale)
    if self:IsLocaleAvailable(locale) then
        return true
    end

    local addon = self:GetLocaleAddon(locale)
    if addon and not self:HasLocaleAddon(locale) then
        return false
    end
    if addon then
        if C_AddOns and C_AddOns.LoadAddOn then
            local loaded, reason = C_AddOns.LoadAddOn(addon)
            if loaded == false then
                if self.Notify then
                    self:Notify("Yapper: failed to load " .. addon .. " (" .. tostring(reason) .. ").")
                end
                return false
            end
        elseif LoadAddOn then
            local loaded = LoadAddOn(addon)
            if loaded == false then
                return false
            end
        end
    end

    -- If the addon exists and load was attempted, allow the locale
    -- to remain selected and rely on dictionary registration to follow.
    if addon then
        self:ScheduleLocaleRefresh(locale)
        return true
    end
    return self:IsLocaleAvailable(locale)
end

function Spellcheck:ScheduleLocaleRefresh(locale)
    if self._pendingLocaleLoads[locale] then return end
    self._pendingLocaleLoads[locale] = true
    if C_Timer and C_Timer.NewTicker then
        local tries = 0
        C_Timer.NewTicker(0.2, function(ticker)
            tries = tries + 1
            if self:IsLocaleAvailable(locale) then
                self._pendingLocaleLoads[locale] = nil
                ticker:Cancel()
                if self:IsEnabled() then
                    self:ScheduleRefresh()
                end
                return
            end
            if tries >= 10 then
                self._pendingLocaleLoads[locale] = nil
                ticker:Cancel()
            end
        end)
    else
        self._pendingLocaleLoads[locale] = nil
    end
end

function Spellcheck:GetConfig()
    return (YapperTable.Config and YapperTable.Config.Spellcheck) or {}
end

function Spellcheck:IsEnabled()
    local cfg = self:GetConfig()
    return cfg.Enabled ~= false
end

function Spellcheck:GetLocale()
    local cfg = self:GetConfig()
    if type(cfg.Locale) == "string" and cfg.Locale ~= "" then
        if self:EnsureLocale(cfg.Locale) then
            return cfg.Locale
        end
        local fallback = self:GetFallbackLocale()
        if cfg.Locale ~= fallback then
            cfg.Locale = fallback
        end
        return fallback
    end
    if GetLocale then
        return GetLocale()
    end
    return "enUS"
end

function Spellcheck:GetFallbackLocale()
    local region = GetCurrentRegion and GetCurrentRegion() or nil
    if region == 3 then
        return "enGB"
    end
    return "enUS"
end

function Spellcheck:GetDictionary()
    local locale = self:GetLocale()
    if not self.Dictionaries[locale] then
        self:EnsureLocale(locale)
    end
    return self.Dictionaries[locale]
end

function Spellcheck:GetUserDictStore()
    if type(_G.YapperDB) ~= "table" then return nil end
    if type(_G.YapperDB.Spellcheck) ~= "table" then _G.YapperDB.Spellcheck = {} end
    if type(_G.YapperDB.Spellcheck.Dict) ~= "table" then _G.YapperDB.Spellcheck.Dict = {} end
    return _G.YapperDB.Spellcheck.Dict
end

function Spellcheck:GetUserDict(locale)
    local store = self:GetUserDictStore()
    if not store then return nil end
    if type(store[locale]) ~= "table" then
        store[locale] = { AddedWords = {}, IgnoredWords = {} }
    end
    if type(store[locale].AddedWords) ~= "table" then store[locale].AddedWords = {} end
    if type(store[locale].IgnoredWords) ~= "table" then store[locale].IgnoredWords = {} end
    return store[locale]
end

function Spellcheck:TouchUserDict(dict)
    dict._rev = (dict._rev or 0) + 1
end

function Spellcheck:BuildWordSet(list)
    local set = {}
    for _, w in ipairs(list or {}) do
        if type(w) == "string" and w ~= "" then
            local norm = NormalizeWord(w)
            set[norm] = true
        end
    end
    return set
end

function Spellcheck:GetUserSets(locale)
    local dict = self:GetUserDict(locale)
    if not dict then return nil, nil end
    local cache = self.UserDictCache[locale]
    if not cache or cache._rev ~= (dict._rev or 0) then
        self.UserDictCache[locale] = {
            added = self:BuildWordSet(dict.AddedWords),
            ignored = self:BuildWordSet(dict.IgnoredWords),
            _rev = dict._rev or 0,
        }
        cache = self.UserDictCache[locale]
    end
    return cache.added, cache.ignored
end

function Spellcheck:AddUserWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local norm = NormalizeWord(word)
    for _, w in ipairs(dict.AddedWords) do
        if NormalizeWord(w) == norm then
            return
        end
    end
    dict.AddedWords[#dict.AddedWords + 1] = word
    for i = #dict.IgnoredWords, 1, -1 do
        if NormalizeWord(dict.IgnoredWords[i]) == norm then
            table.remove(dict.IgnoredWords, i)
        end
    end
    self:TouchUserDict(dict)
    self:ApplyUserAddedWords(locale)
end

function Spellcheck:IgnoreWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local norm = NormalizeWord(word)
    for _, w in ipairs(dict.IgnoredWords) do
        if NormalizeWord(w) == norm then
            return
        end
    end
    dict.IgnoredWords[#dict.IgnoredWords + 1] = word
    for i = #dict.AddedWords, 1, -1 do
        if NormalizeWord(dict.AddedWords[i]) == norm then
            table.remove(dict.AddedWords, i)
        end
    end
    self:TouchUserDict(dict)
end

function Spellcheck:ApplyUserAddedWords(locale)
    -- User-added words are handled via user sets (added/ignored).
    -- Avoid mutating the base dictionary sets so manual edits can
    -- remove words cleanly without stale entries.
    self:GetUserSets(locale)
end

function Spellcheck:GetMaxSuggestions()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxSuggestions) or 4, 1, 4)
end

function Spellcheck:GetMaxCandidates()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxCandidates) or 800, 50, 5000)
end

function Spellcheck:GetReshuffleAttempts()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.ReshuffleAttempts) or 3, 0, 20)
end

function Spellcheck:GetMaxWrongLetters()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxWrongLetters) or 4, 0, 20)
end

function Spellcheck:GetMinWordLength()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MinWordLength) or 2, 1, 10)
end

function Spellcheck:GetUnderlineStyle()
    local cfg = self:GetConfig()
    if cfg.UnderlineStyle == "highlight" then
        return "highlight"
    end
    return "line"
end

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
            if button == "RightButton" and self:IsSuggestionEligible() then
                self:OpenOrCycleSuggestions()
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

function Spellcheck:OnConfigChanged()
    self:ScheduleRefresh()
end

function Spellcheck:OnTextChanged(editBox, isUserInput)
    if editBox ~= self.EditBox then return end
    if isUserInput then
        -- Mark that the text changed due to user input so suggestion
        -- selection can run once for this change (not on caret moves).
        self._textChangedFlag = true
    end
    self:ScheduleRefresh()
end

function Spellcheck:OnCursorChanged(editBox)
    if editBox ~= self.EditBox then return end
    if self._suppressCursorUpdate and self:IsSuggestionOpen() then
        return
    end
    self:UpdateActiveWord()
    self:UpdateHint()
end

function Spellcheck:OnOverlayHide()
    self:HideSuggestions()
    self:ClearUnderlines()
    self:HideHint()
end

function Spellcheck:ScheduleRefresh()
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
        self._debounceTimer = C_Timer.NewTimer(0.12, function()
            self:Rebuild()
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
    if self.MeasureFS or not self.Overlay then return end
    local fs = self.Overlay:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    fs:Hide()
    self.MeasureFS = fs
end

function Spellcheck:EnsureSuggestionFrame()
    if self.SuggestionFrame or not self.Overlay then return end

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
    local frame = CreateFrame("Frame", nil, self.Overlay)
    frame:SetSize(220, 14)
    frame:Hide()

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", frame, "LEFT", 0, 0)
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
                self:Notify("Spellcheck:HintTimer fired; curCursor=" .. tostring(curCursor) .. " pending=" .. tostring(self._pendingHintCursor))
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
        self:Notify("Spellcheck:OpenOrCycleSuggestions word='" .. tostring(self.ActiveWord) .. "' suggestions=" .. tostring(sugCount))
    end
    if sugCount == 0 then
        self:HideSuggestions()
        return
    end

    self.ActiveSuggestions = suggestions
    self.ActiveIndex = 1
    self:ShowSuggestions()
end

function Spellcheck:ShowSuggestions()
    if not self.SuggestionFrame then return end
    if not self.ActiveSuggestions then return end

    -- If the suggestion frame is already visible and the suggestions
    -- haven't changed, skip updating to avoid per-frame work and debug spam.
    if self.SuggestionFrame:IsShown() and self._lastShownSuggestions and self:SuggestionsEqual(self.ActiveSuggestions, self._lastShownSuggestions) then
        return
    end

    local editBox = self.EditBox
    local x = self:GetCaretXOffset()
    self.SuggestionFrame:ClearAllPoints()
    -- Anchor above the editbox so the suggestions appear on top of the overlay.
    self.SuggestionFrame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", x, 4)

    local maxWidth = 160
    for i = 1, #self.SuggestionRows do
        local row = self.SuggestionRows[i]
        local entry = self.ActiveSuggestions[i]
        if entry then
            row._fs:SetText(self:FormatSuggestionLabel(entry, i))
            row:Show()
            local w = row._fs:GetStringWidth() + 30
            if w > maxWidth then maxWidth = w end
        else
            row:Hide()
        end
    end

    local visibleCount = math.min(#self.ActiveSuggestions, #self.SuggestionRows)
    self.SuggestionFrame:SetSize(maxWidth + 10, (visibleCount * 18) + 12)
    self:RefreshSuggestionSelection()
    self.SuggestionFrame:Show()
    self._lastShownSuggestions = self.ActiveSuggestions
end

function Spellcheck:HideSuggestions()
    if self.SuggestionFrame then
        self.SuggestionFrame:Hide()
    end
    self.ActiveSuggestions = nil
    self.ActiveIndex = 1
    self._lastShownSuggestions = nil
end

function Spellcheck:ApplySuggestion(index)
    if not self.ActiveSuggestions or not self.ActiveRange then return end
    local entry = self.ActiveSuggestions[index]
    if not entry then return end

    if type(entry) == "table" and entry.kind == "add" then
        local locale = self:GetLocale()
        self:AddUserWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText = self.EditBox:GetText() or ""
            self._expectedCursor = self.EditBox:GetCursorPosition()
        end
        self:HideSuggestions()
        self._textChangedFlag = true
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

    self.EditBox:SetText(newText)
    local cursorPos = #before + #replacement
    self.EditBox:SetCursorPosition(cursorPos)
    -- Prevent the following character insertion (numeric hotkey) from
    -- being appended to the editbox; EditBox.OnTextChanged will remove it.
    self._suppressNextChar = true
    self._suppressChar = tostring(index)
    self._expectedText = newText
    self._expectedCursor = cursorPos
    -- Mark that a suggestion was just applied so higher-level Enter
    -- handlers can swallow the following Enter (applied via keyboard).
    self._justAppliedSuggestion = true
    if C_Timer and C_Timer.NewTimer then
        C_Timer.NewTimer(0.05, function()
            self._justAppliedSuggestion = nil
        end)
    end
    self:HideSuggestions()
    self._textChangedFlag = true
    self:ScheduleRefresh()
end

function Spellcheck:GetCaretXOffset()
    local editBox = self.EditBox
    local text = editBox and editBox:GetText() or ""
    local cursor = editBox and editBox:GetCursorPosition() or #text
    local prefix = text:sub(1, cursor)
    local leftInset = 0
    if editBox and editBox.GetTextInsets then
        leftInset = select(1, editBox:GetTextInsets()) or 0
    end
    local width = self:MeasureText(prefix)
    return leftInset + width
end

function Spellcheck:MeasureText(text)
    if not self.MeasureFS then return 0 end
    local editBox = self.EditBox
    if editBox and editBox.GetFont then
        local face, size, flags = editBox:GetFont()
        if face and size then
            self.MeasureFS:SetFont(face, size, flags or "")
        end
    end
    self.MeasureFS:SetText(text or "")
    return self.MeasureFS:GetStringWidth() or 0
end

function Spellcheck:UpdateUnderlines()
    if not self.EditBox then return end

    -- Avoid repeated expensive work if the edit text and active
    -- dictionary haven't changed since the last underline pass. This
    -- prevents frequent Measure/GetStringWidth calls and large
    -- dictionary scans when nothing relevant has changed (e.g. an
    -- unrelated tooltip opened, or many dictionaries loaded).
    local dict = self:GetDictionary()
    if not dict then return end

    local text = self.EditBox:GetText() or ""
    if text == "" then
        -- Clear any previous cache when empty.
        self._lastUnderlinesText = nil
        self._lastUnderlinesDict = nil
        self:ClearUnderlines()
        return
    end

    if self._lastUnderlinesText == text and self._lastUnderlinesDict == dict then
        return
    end

    self._lastUnderlinesText = text
    self._lastUnderlinesDict = dict

    self:ClearUnderlines()

    local words = self:CollectMisspellings(text, dict)
    for _, item in ipairs(words) do
        self:DrawUnderline(item.startPos, item.endPos, text)
    end
end

function Spellcheck:DrawUnderline(startPos, endPos, text)
    if not self.EditBox or not self.Overlay then return end

    local leftInset = 0
    if self.EditBox.GetTextInsets then
        leftInset = select(1, self.EditBox:GetTextInsets()) or 0
    end

    local prefix = text:sub(1, startPos - 1)
    local word = text:sub(startPos, endPos)
    local x = leftInset + self:MeasureText(prefix)
    local w = self:MeasureText(word)

    local tex = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()

    if style == "highlight" then
        local height = (self.EditBox:GetHeight() or 20) - 6
        -- Brighter highlight for better visibility (increased alpha
        -- and slightly adjusted tint).
        tex:SetColorTexture(1, 0.18, 0.18, 0.36)
        tex:SetSize(w, height)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.EditBox, "TOPLEFT", x, -3)
    else
        tex:SetColorTexture(1, 0.2, 0.2, 0.9)
        tex:SetSize(w, 2)
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", self.EditBox, "BOTTOMLEFT", x, 2)
    end

    tex:Show()
    self.Underlines[#self.Underlines + 1] = tex
end

function Spellcheck:AcquireUnderline()
    local tex = table.remove(self.UnderlinePool)
    if tex then
        return tex
    end
    tex = self.Overlay:CreateTexture(nil, "OVERLAY")
    return tex
end

function Spellcheck:ClearUnderlines()
    for i = 1, #self.Underlines do
        local tex = self.Underlines[i]
        tex:Hide()
        self.UnderlinePool[#self.UnderlinePool + 1] = tex
    end
    self.Underlines = {}
end

function Spellcheck:CollectMisspellings(text, dict)
    local out = {}
    local minLen = self:GetMinWordLength()
    local ignoreRanges = self:GetIgnoredRanges(text)
    local _, ignoredSet = self:GetUserSets(self:GetLocale())
    local addedSet = select(1, self:GetUserSets(self:GetLocale()))

    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end

        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            local norm = NormalizeWord(word)
            if not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen)
                and not (ignoredSet and ignoredSet[norm])
                and not (addedSet and addedSet[norm])
                and not dict.set[norm]
                and not dict.set[word] then
                out[#out + 1] = { startPos = s, endPos = e, word = word }
            end
        else
            idx = idx + 1
        end
    end

    return out
end

function Spellcheck:ShouldCheckWord(word, minLen)
    if #word < minLen then return false end
    if word:find("%d") then return false end
    if word:find("[A-Za-z]") and word == word:upper() then return false end
    return true
end

function Spellcheck:GetIgnoredRanges(text)
    local ranges = {}
    local idx = 1
    while true do
        local s, e = text:find("|H.-|h.-|h", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|c%x%x%x%x%x%x%x%x.-|r", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|T.-|t", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|A.-|a", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    return ranges
end

function Spellcheck:IsRangeIgnored(startPos, endPos, ranges)
    for _, range in ipairs(ranges) do
        if startPos <= range.endPos and endPos >= range.startPos then
            return true
        end
    end
    return false
end

function Spellcheck:UpdateActiveWord()
    if not self.EditBox then return end

    local text = self.EditBox:GetText() or ""
    local cursor = self.EditBox:GetCursorPosition() or #text
    local dict = self:GetDictionary()
    local prevWord = self.ActiveWord
    local prevSuggestions = self.ActiveSuggestions
    local prevIndex = self.ActiveIndex

    if not dict or text == "" then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    local wordInfo = self:GetWordAtCursor(text, cursor)
    if not wordInfo then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    local norm = NormalizeWord(wordInfo.word)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    if dict.set[norm] or dict.set[wordInfo.word] or (addedSet and addedSet[norm]) then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end
    if ignoredSet and ignoredSet[norm] then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    self.ActiveWord = wordInfo.word
    self.ActiveRange = { startPos = wordInfo.startPos, endPos = wordInfo.endPos }

    if self:IsSuggestionOpen() then
        local currentText = text or ""
        local locale = self:GetLocale()
        local userCache = self.UserDictCache[locale]
        local userRev = userCache and userCache._rev or nil

        local needCompute = false
        if self._textChangedFlag then
            needCompute = true
        elseif not self._lastSuggestionsText or self._lastSuggestionsText ~= currentText
            or self._lastSuggestionsLocale ~= locale
            or self._lastSuggestionsUserRev ~= userRev then
            needCompute = true
        end

        local suggestions = nil
        if needCompute then
            suggestions = self:GetSuggestions(self.ActiveWord)
            self._lastSuggestionsText = currentText
            self._lastSuggestionsLocale = locale
            self._lastSuggestionsUserRev = userRev
            self._textChangedFlag = false
        else
            suggestions = self.ActiveSuggestions or {}
        end

        if #suggestions == 0 then
            self:HideSuggestions()
        else
            self.ActiveSuggestions = suggestions
            if prevWord == self.ActiveWord and self:SuggestionsEqual(prevSuggestions, suggestions) then
                self.ActiveIndex = prevIndex or 1
            else
                self.ActiveIndex = 1
            end
            self:ShowSuggestions()
        end
    end
end

function Spellcheck:GetWordAtCursor(text, cursor)
    local caret = cursor + 1
    local ignoreRanges = self:GetIgnoredRanges(text)
    local minLen = self:GetMinWordLength()
    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end
        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            if caret >= s and caret <= (e + 1)
                and not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen) then
                return { word = word, startPos = s, endPos = e }
            end
        else
            idx = idx + 1
        end
    end
    return nil
end

function Spellcheck:GetSuggestions(word)
    local dict = self:GetDictionary()
    if not dict then
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions no dictionary for locale")
        end
        return {}
    end

    local locale = self:GetLocale()
    local userCache = self.UserDictCache[locale]
    local userRev = userCache and userCache._rev or nil

    local maxCount = self:GetMaxSuggestions()
    local lower = NormalizeWord(word)

    -- Suggestion cache: reuse recent result when the input word,
    -- dictionary and user-added/ignored lists haven't changed.
    self._suggestionCache = self._suggestionCache or {}
    local sc = self._suggestionCache
    local maxCandidates = (type(self.GetMaxCandidates) == "function") and self:GetMaxCandidates() or 200
    if sc.word == lower and sc.dict == dict and sc.userRev == userRev and sc.locale == locale and sc.maxCandidates == maxCandidates then
        return sc.result or {}
    end
    local first = lower:sub(1, 1)
    local candidates = dict.index[first] or {}
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions word='" .. tostring(word) .. "' lower='" .. tostring(lower) .. "' locale='" .. tostring(locale) .. "' candidates=" .. tostring(#candidates))
    end
    local _, ignoredSet = self:GetUserSets(self:GetLocale())
    local out = {}

    local maxDist = (#lower <= 4) and 2 or 3
    local maxLenDiff = maxDist + 1

    local function CommonPrefixLen(a, b)
        local len = math.min(#a, #b)
        local count = 0
        for i = 1, len do
            if a:sub(i, i) ~= b:sub(i, i) then break end
            count = count + 1
        end
        return count
    end

    local function LetterBagScore(a, b)
        -- Estimate how close two words are as anagrams by comparing
        -- letter frequencies. Lower is better.
        local bag = {}
        for i = 1, #a do
            local ch = a:sub(i, i)
            bag[ch] = (bag[ch] or 0) + 1
        end
        for i = 1, #b do
            local ch = b:sub(i, i)
            if bag[ch] then
                bag[ch] = bag[ch] - 1
            else
                bag[ch] = -1
            end
        end
        local score = 0
        for _, v in pairs(bag) do
            if v ~= 0 then
                score = score + math.abs(v)
            end
        end
        return score
    end

    local function BigramOverlap(a, b)
        -- Count shared bigrams (2-char sequences). Higher is better.
        if #a < 2 or #b < 2 then return 0 end
        local sa = {}
        for i = 1, #a - 1 do
            local g = a:sub(i, i+1)
            sa[g] = (sa[g] or 0) + 1
        end
        local count = 0
        for i = 1, #b - 1 do
            local g = b:sub(i, i+1)
            if sa[g] and sa[g] > 0 then
                count = count + 1
                sa[g] = sa[g] - 1
            end
        end
        return count
    end

    local function tryAdd(candidate, dist)
        local candidateLen = #candidate
        local lenDiff = math.abs(candidateLen - #lower)
        local prefix = CommonPrefixLen(lower, candidate)
        local bagScore = LetterBagScore(lower, candidate)
        local bigramScore = BigramOverlap(lower, candidate)
        local maxWrong = self:GetMaxWrongLetters() or 4

        local longerPenalty = 0
        if candidateLen > #lower then
            local over = (candidateLen - #lower)
            local factor = 1 + ((bagScore / math.max(1, maxWrong)) * 0.5)
            longerPenalty = over * SCORE_WEIGHTS.longerPenalty * factor
        end

        local score = dist
            + (lenDiff * SCORE_WEIGHTS.lenDiff)
            + longerPenalty
            - (prefix * SCORE_WEIGHTS.prefix)
            + (bagScore * SCORE_WEIGHTS.letterBag)
            - (bigramScore * SCORE_WEIGHTS.bigram)

        -- Prefer exact-length candidates when their letter-bag distance is within allowed wrong letters.
        if candidateLen == #lower then
            if bagScore <= maxWrong then
                score = score - (SCORE_WEIGHTS.lenDiff * 1.5)
            else
                score = score + ((bagScore - maxWrong) * 0.5)
            end
        end
        out[#out + 1] = { word = candidate, dist = dist, score = score, bag = bagScore }
    end

    -- Prioritise candidates that share more prefix characters with the
    -- query to improve accuracy for short mistyped words (e.g. "hepl"→"help").
    -- Also allow a larger effective cap for short inputs while keeping a
    -- conservative cap for long inputs.
    local dynamicCap = maxCandidates
    if #lower <= 4 then
        dynamicCap = math.min(maxCandidates * 4, 5000)
    end

    local checks = 0
    local function tryCandidates(list)
        for _, candidate in ipairs(list) do
            if #out >= 60 then return true end
            if seenCandidates[candidate] then
                -- already processed this candidate via another bucket/variant
            else
                seenCandidates[candidate] = true
                checks = checks + 1
                if checks > dynamicCap then return true end
                if ignoredSet and ignoredSet[candidate] then
                    -- skip ignored
                else
                    local lenDiff = math.abs(#candidate - #lower)
                    if lenDiff <= maxLenDiff then
                        local dist = self:EditDistance(lower, candidate, maxDist)
                        if dist and dist <= maxDist then
                            tryAdd(candidate, dist)
                        end
                    end
                end
            end
        end
        return false
    end

    -- Bucket candidates: exact 2-char prefix, 1-char prefix, others.
    local pref2 = {}
    local pref1 = {}
    local other = {}
    local p2 = lower:sub(1,2) or ""
    local p1 = lower:sub(1,1) or ""
    for _, c in ipairs(candidates) do
        if c:sub(1,2) == p2 and p2 ~= "" then
            pref2[#pref2+1] = c
        elseif c:sub(1,1) == p1 then
            pref1[#pref1+1] = c
        else
            other[#other+1] = c
        end
    end

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify(string.format("Spellcheck:GetSuggestions buckets p2=%d p1=%d other=%d dynamicCap=%d maxDist=%d maxLenDiff=%d", #pref2, #pref1, #other, dynamicCap, maxDist, maxLenDiff))
    end

    local seenCandidates = {}
    local aborted = false
    aborted = tryCandidates(pref2)
    if aborted then
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions aborted after pref2; checks=" .. tostring(checks) .. " out=" .. tostring(#out))
        end
    end
    if not aborted then
        aborted = tryCandidates(pref1)
        if aborted and YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions aborted after pref1; checks=" .. tostring(checks) .. " out=" .. tostring(#out))
        end
    end
    if not aborted then
        tryCandidates(other)
    end

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions finished checks=" .. tostring(checks) .. " candidatesFound=" .. tostring(#out))
    end

    -- If we haven't filled the suggestion list, attempt a small number
    -- of reshuffles/variants of the input to catch anagram-like typos.
    if not aborted and #out < maxCount and checks < dynamicCap then
        local attempts = self:GetReshuffleAttempts() or 0
        if attempts > 0 then
            local function reverseString(s)
                local t = {}
                for i = #s, 1, -1 do t[#t+1] = s:sub(i,i) end
                return table.concat(t)
            end
            local function sortedString(s)
                local t = {}
                for i = 1, #s do t[#t+1] = s:sub(i,i) end
                table.sort(t)
                return table.concat(t)
            end

            local variants = {}
            local vseen = {}
            local maxWrong = self:GetMaxWrongLetters() or 4
            local function addVariantIfAcceptable(v)
                if not v or v == lower then return end
                if vseen[v] or #variants >= attempts then return end
                local bagScore = LetterBagScore(lower, v)
                -- Use a conservative threshold (allow up to maxWrong*2 bag distance)
                if bagScore and bagScore <= (maxWrong * 2) then
                    vseen[v] = true
                    variants[#variants+1] = v
                end
            end

            -- Prioritise realistic typos: adjacent transpositions, single deletions, single replacements
            -- 1) adjacent transpositions
            for i = 1, (#lower - 1) do
                if #variants >= attempts then break end
                local chars = {}
                for k = 1, #lower do chars[k] = lower:sub(k,k) end
                chars[i], chars[i+1] = chars[i+1], chars[i]
                addVariantIfAcceptable(table.concat(chars))
            end

            -- 2) single deletions
            for i = 1, #lower do
                if #variants >= attempts then break end
                local chars = {}
                for k = 1, #lower do if k ~= i then chars[#chars+1] = lower:sub(k,k) end end
                addVariantIfAcceptable(table.concat(chars))
            end

            -- 3) single replacements using likely letters (dict.first-letters + original letters)
            local alph = {}
            for k in pairs(dict.index) do alph[#alph+1] = k end
            -- include letters from the input as likely replacements
            for i = 1, #lower do alph[#alph+1] = lower:sub(i,i) end
            -- dedupe alph
            local alphSeen = {}
            local alphaList = {}
            for _, ch in ipairs(alph) do
                if not alphSeen[ch] then alphSeen[ch] = true; alphaList[#alphaList+1] = ch end
            end
            for i = 1, #lower do
                if #variants >= attempts then break end
                for _, ch in ipairs(alphaList) do
                    if #variants >= attempts then break end
                    local chars = {}
                    for k = 1, #lower do chars[k] = lower:sub(k,k) end
                    chars[i] = ch
                    addVariantIfAcceptable(table.concat(chars))
                end
            end

            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:GetSuggestions trying variants=" .. tostring(#variants))
            end

            for _, var in ipairs(variants) do
                if checks > dynamicCap then break end
                local firstV = var:sub(1,1) or ""
                local candlist = dict.index[firstV] or {}
                if #candlist > 0 then
                    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                        self:Notify("Spellcheck:GetSuggestions variant='" .. tostring(var) .. "' candidates=" .. tostring(#candlist))
                    end
                    local abortVar = tryCandidates(candlist)
                    if abortVar then break end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.score == b.score then
            if a.dist == b.dist then
                return a.word < b.word
            end
            return a.dist < b.dist
        end
        return a.score < b.score
    end)

    local final = {}
    for i = 1, math.min(maxCount, #out) do
        final[i] = { kind = "word", value = out[i].word }
    end

    -- Add optional actions at the end of the list.
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    if word and word ~= "" then
        local norm = NormalizeWord(word)
        if not (addedSet and addedSet[norm]) then
            final[#final + 1] = { kind = "add", value = word }
        end
        if not (ignoredSet and ignoredSet[norm]) then
            final[#final + 1] = { kind = "ignore", value = word }
        end
    end

    -- Update suggestion cache
    sc.word = lower
    sc.dict = dict
    sc.userRev = userRev
    sc.locale = locale
    sc.maxCandidates = maxCandidates
    sc.result = final

    return final
end

function Spellcheck:EditDistance(a, b, maxDist)
    if a == b then return 0 end
    local lenA = #a
    local lenB = #b
    if math.abs(lenA - lenB) > maxDist then return nil end

    local prevPrev = {}
    local prev = {}
    for j = 0, lenB do prev[j] = j end

    for i = 1, lenA do
        local cur = { [0] = i }
        local minRow = cur[0]
        local ai = a:sub(i, i)

        for j = 1, lenB do
            local bj = b:sub(j, j)
            local cost = (ai == bj) and 0 or 1
            local val = math.min(
                prev[j] + 1,
                cur[j - 1] + 1,
                prev[j - 1] + cost
            )
            if i > 1 and j > 1 then
                local aiPrev = a:sub(i - 1, i - 1)
                local bjPrev = b:sub(j - 1, j - 1)
                if ai == bjPrev and aiPrev == bj then
                    val = math.min(val, (prevPrev[j - 2] or 0) + 1)
                end
            end
            cur[j] = val
            if val < minRow then minRow = val end
        end

        if minRow > maxDist then return nil end
        prevPrev = prev
        prev = cur
    end

    return prev[lenB]
end

function Spellcheck:FormatSuggestionLabel(entry, index)
    if type(entry) == "string" then
        return index .. ". " .. entry
    end
    if type(entry) ~= "table" then
        return index .. ". -"
    end
    if entry.kind == "add" then
        return index .. ". Add \"" .. (entry.value or "") .. "\" to dictionary"
    end
    if entry.kind == "ignore" then
        return index .. ". Ignore \"" .. (entry.value or "") .. "\""
    end
    return index .. ". " .. (entry.value or entry.word or "")
end

return Spellcheck
