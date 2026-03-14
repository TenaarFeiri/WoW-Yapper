--[[
    Spellcheck.lua
    Lightweight spellcheck for the overlay editbox.

    Uses packaged dictionary tables registered at load time.
]]

local _, YapperTable = ...

local Spellcheck = {}
YapperTable.Spellcheck = Spellcheck

Spellcheck.Dictionaries = {}
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

local function Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

local function NormalizeWord(word)
    if type(word) ~= "string" then return "" end
    return (word:gsub("%u", string.lower))
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
    local set = {}
    local index = {}

    for _, word in ipairs(words) do
        if type(word) == "string" and word ~= "" then
            local w = NormalizeWord(word)
            set[w] = true
            local key = w:sub(1, 1)
            if key ~= "" then
                index[key] = index[key] or {}
                index[key][#index[key] + 1] = w
            end
        end
    end

    self.Dictionaries[locale] = {
        locale = locale,
        words = words,
        set = set,
        index = index,
    }
end

function Spellcheck:GetAvailableLocales()
    local out = {}
    for locale in pairs(self.Dictionaries) do
        out[#out + 1] = locale
    end
    table.sort(out)
    return out
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
        return cfg.Locale
    end
    if GetLocale then
        return GetLocale()
    end
    return "enUS"
end

function Spellcheck:GetDictionary()
    return self.Dictionaries[self:GetLocale()]
end

function Spellcheck:GetMaxSuggestions()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxSuggestions) or 4, 1, 4)
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
end

function Spellcheck:OnConfigChanged()
    self:ScheduleRefresh()
end

function Spellcheck:OnTextChanged(editBox)
    if editBox ~= self.EditBox then return end
    self:ScheduleRefresh()
end

function Spellcheck:OnCursorChanged(editBox)
    if editBox ~= self.EditBox then return end
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
    frame:SetFrameStrata("DIALOG")
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
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(160, 18)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - ((i - 1) * 18))

        local hl = btn:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(btn)
        hl:SetColorTexture(1, 1, 1, 0.08)
        hl:Hide()

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetText("-")

        btn._fs = fs
        btn._hl = hl
        btn._index = i
        btn:SetScript("OnEnter", function()
            self.ActiveIndex = i
            self:RefreshSuggestionSelection()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySuggestion(i)
        end)

        rows[i] = btn
    end

    self.SuggestionFrame = frame
    self.SuggestionRows = rows
end

function Spellcheck:EnsureHintFrame()
    if self.HintFrame or not self.Overlay then return end
    local frame = CreateFrame("Frame", nil, self.Overlay)
    frame:SetSize(220, 14)
    frame:Hide()

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", frame, "LEFT", 0, 0)
    fs:SetTextColor(0.8, 0.8, 0.8, 1)
    fs:SetText("Alt+Tab: spell suggestions")

    frame._fs = fs
    self.HintFrame = frame
end

function Spellcheck:ShowHint()
    if not self.HintFrame or not self.EditBox then return end
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
    if self:IsSuggestionEligible() then
        self:ShowHint()
    else
        self:HideHint()
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

    if key == "TAB" and IsAltKeyDown() then
        if self:IsSuggestionEligible() then
            self:OpenOrCycleSuggestions()
            return true
        end
        return false
    end

    if self:IsSuggestionOpen() then
        if key == "UP" then
            self:MoveSelection(-1)
            return true
        end
        if key == "DOWN" then
            self:MoveSelection(1)
            return true
        end
        if key == "1" or key == "2" or key == "3" or key == "4" then
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
    if #suggestions == 0 then
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

    local editBox = self.EditBox
    local x = self:GetCaretXOffset()
    self.SuggestionFrame:ClearAllPoints()
    self.SuggestionFrame:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", x, -4)

    local maxWidth = 160
    for i = 1, #self.SuggestionRows do
        local row = self.SuggestionRows[i]
        local word = self.ActiveSuggestions[i]
        if word then
            row._fs:SetText(i .. ". " .. word)
            row:Show()
            local w = row._fs:GetStringWidth() + 30
            if w > maxWidth then maxWidth = w end
        else
            row:Hide()
        end
    end

    self.SuggestionFrame:SetSize(maxWidth + 10, (#self.ActiveSuggestions * 18) + 12)
    self:RefreshSuggestionSelection()
    self.SuggestionFrame:Show()
end

function Spellcheck:HideSuggestions()
    if self.SuggestionFrame then
        self.SuggestionFrame:Hide()
    end
    self.ActiveSuggestions = nil
    self.ActiveIndex = 1
end

function Spellcheck:ApplySuggestion(index)
    if not self.ActiveSuggestions or not self.ActiveRange then return end
    local replacement = self.ActiveSuggestions[index]
    if not replacement then return end

    local text = self.EditBox and self.EditBox:GetText() or ""
    local startPos = self.ActiveRange.startPos
    local endPos = self.ActiveRange.endPos
    if not startPos or not endPos then return end

    local before = text:sub(1, startPos - 1)
    local after = text:sub(endPos + 1)
    local newText = before .. replacement .. after

    self.EditBox:SetText(newText)
    self.EditBox:SetCursorPosition(#before + #replacement)
    self:HideSuggestions()
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
    self:ClearUnderlines()

    local dict = self:GetDictionary()
    if not dict then return end

    local text = self.EditBox:GetText() or ""
    if text == "" then return end

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
        tex:SetColorTexture(1, 0, 0, 0.15)
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
    if dict.set[norm] or dict.set[wordInfo.word] then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    self.ActiveWord = wordInfo.word
    self.ActiveRange = { startPos = wordInfo.startPos, endPos = wordInfo.endPos }

    if self:IsSuggestionOpen() then
        local suggestions = self:GetSuggestions(self.ActiveWord)
        if #suggestions == 0 then
            self:HideSuggestions()
        else
            self.ActiveSuggestions = suggestions
            self.ActiveIndex = 1
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
    if not dict then return {} end

    local maxCount = self:GetMaxSuggestions()
    local lower = NormalizeWord(word)
    local first = lower:sub(1, 1)
    local candidates = dict.index[first] or {}
    local out = {}

    local function tryAdd(candidate, dist)
        out[#out + 1] = { word = candidate, dist = dist }
    end

    for _, candidate in ipairs(candidates) do
        if #out >= 20 then break end
        local lenDiff = math.abs(#candidate - #lower)
        if lenDiff <= 2 then
            local dist = self:EditDistance(lower, candidate, 2)
            if dist and dist <= 2 then
                tryAdd(candidate, dist)
            end
        end
    end

    table.sort(out, function(a, b)
        if a.dist == b.dist then
            return a.word < b.word
        end
        return a.dist < b.dist
    end)

    local final = {}
    for i = 1, math.min(maxCount, #out) do
        final[i] = out[i].word
    end

    return final
end

function Spellcheck:EditDistance(a, b, maxDist)
    if a == b then return 0 end
    local lenA = #a
    local lenB = #b
    if math.abs(lenA - lenB) > maxDist then return nil end

    local prev = {}
    for j = 0, lenB do prev[j] = j end

    for i = 1, lenA do
        local cur = { [0] = i }
        local minRow = cur[0]
        local ai = a:sub(i, i)

        for j = 1, lenB do
            local cost = (ai == b:sub(j, j)) and 0 or 1
            local val = math.min(
                prev[j] + 1,
                cur[j - 1] + 1,
                prev[j - 1] + cost
            )
            cur[j] = val
            if val < minRow then minRow = val end
        end

        if minRow > maxDist then return nil end
        prev = cur
    end

    return prev[lenB]
end

return Spellcheck
