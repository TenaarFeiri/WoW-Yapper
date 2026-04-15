--[[
    Spellcheck/Underline.lua
    Single-line and multi-line underline rendering, texture pooling,
    font measurement for wrapped text, and scroll-offset handling.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local IsWordByte = Spellcheck.IsWordByte

-- Re-localise Lua globals.
local type       = type
local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local math_abs   = math.abs
local string_sub = string.sub
local string_byte = string.byte

function Spellcheck:GetCaretXOffset()
    local editBox = self.EditBox
    if not editBox then return 0 end

    local text = editBox:GetText() or ""
    local cursor = editBox:GetCursorPosition() or #text
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
    local cursor = self.EditBox:GetCursorPosition() or 0
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
    local text = self.EditBox:GetText() or ""
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

-- Maximum number of characters to scan around the cursor for misspellings.
-- Configurable for devs; larger values scan more text but cost more CPU per rebuild.
local SCAN_RADIUS = 1000

local SCAN_RECENTER_MARGIN = 200

function Spellcheck:UpdateUnderlines()
    if not self.EditBox then return end

    local dict = self:GetDictionary()
    if not dict then return end

    local text = self.EditBox:GetText() or ""
    if text == "" then
        self._lastUnderlinesText = nil
        self._lastUnderlinesDict = nil
        self._lastScrollOffset = nil
        self._scanWindowStart = nil
        self._scanWindowEnd = nil
        self:ClearUnderlines()
        return
    end

    local textLen = #text
    local cursor = self.EditBox:GetCursorPosition() or textLen
    local scrollOffset = self:GetScrollOffset()

    -- For short texts, scan everything (no window overhead).
    if textLen <= SCAN_RADIUS * 2 then
        local textSame = (self._lastUnderlinesText == text and self._lastUnderlinesDict == dict)
        local diff = math_abs((self._lastScrollOffset or 0) - scrollOffset)
        local scrollSame = (diff < 0.5)

        if textSame then
            -- If the text is the same, just redraw the underlines (handles scroll & resize reflow)
            self:RedrawUnderlines()
            return
        end

        self._lastUnderlinesText = text
        self._lastUnderlinesDict = dict
        self._lastScrollOffset = scrollOffset
        self._scanWindowStart = nil
        self._scanWindowEnd = nil

        local words = self:CollectMisspellings(text, dict)
        self._lastMisspellings = words
        self:RedrawUnderlines()
        return
    end

    -- Large text: use a scan window centered on the cursor.
    local needRescan = false
    if not self._scanWindowStart or not self._scanWindowEnd then
        needRescan = true
    elseif self._lastUnderlinesText ~= text or self._lastUnderlinesDict ~= dict then
        needRescan = true
    else
        if cursor - self._scanWindowStart < SCAN_RECENTER_MARGIN
            or self._scanWindowEnd - cursor < SCAN_RECENTER_MARGIN then
            needRescan = true
        end
    end

    if not needRescan then
        -- Text hasn't changed or window hasn't shifted; just redraw based on new UI metrics
        self:RedrawUnderlines()
        return
    end

    self._lastUnderlinesText = text
    self._lastUnderlinesDict = dict
    self._lastScrollOffset = scrollOffset

    -- Build the window centered on the cursor, clamped to text bounds
    local rawStart = math_max(1, cursor - SCAN_RADIUS)
    local rawEnd = math_min(textLen, cursor + SCAN_RADIUS)

    -- Snap start forward to the next word boundary (skip partial word)
    if rawStart > 1 then
        while rawStart <= rawEnd do
            local b = string_byte(text, rawStart)
            if not b or not IsWordByte(b) then break end
            rawStart = rawStart + 1
        end
    end

    -- Snap end backward to the previous word boundary (skip partial word)
    if rawEnd < textLen then
        while rawEnd >= rawStart do
            local b = string_byte(text, rawEnd)
            if not b or not IsWordByte(b) then break end
            rawEnd = rawEnd - 1
        end
    end

    self._scanWindowStart = rawStart
    self._scanWindowEnd = rawEnd

    local windowText = string_sub(text, rawStart, rawEnd)
    local words = self:CollectMisspellings(windowText, dict)

    -- Convert window-local positions to full-text positions and cache.
    local fullPosWords = {}
    for _, item in ipairs(words) do
        fullPosWords[#fullPosWords + 1] = {
            startPos = item.startPos + rawStart - 1,
            endPos = item.endPos + rawStart - 1,
        }
    end
    self._lastMisspellings = fullPosWords
    self:RedrawUnderlines()
end

function Spellcheck:RedrawUnderlines()
    if not self.EditBox or not self._lastMisspellings then return end

    if self.EditBox.IsMultiLine and self.EditBox:IsMultiLine() then
        self:RedrawUnderlines_ML()
        return
    end

    local text = self.EditBox:GetText() or ""
    local scrollOffset = self:GetScrollOffset()
    self._lastScrollOffset = scrollOffset

    self:ClearUnderlines()
    for _, item in ipairs(self._lastMisspellings) do
        self:DrawUnderline(item.startPos, item.endPos, text, scrollOffset)
    end
end

function Spellcheck:DrawUnderline(startPos, endPos, text, scrollOffset)
    if not self.EditBox or not self.Overlay then return end

    local leftInset = 0
    local rightInset = 0
    if self.EditBox.GetTextInsets then
        leftInset, rightInset = self.EditBox:GetTextInsets()
        leftInset  = leftInset  or 0
        rightInset = rightInset or 0
    end

    local prefix = string_sub(text, 1, startPos - 1)
    local word   = string_sub(text, startPos, endPos)
    local x = leftInset + self:MeasureText(prefix) - (scrollOffset or 0)
    local w = self:MeasureText(word)

    -- Clamp to the visible text area so underlines don't escape the EditBox.
    local visibleWidth = (self.EditBox:GetWidth() or 200) - leftInset - rightInset

    if (x + w) <= 0 or x >= visibleWidth then return end
    if x < 0 then
        w = w + x
        x = 0
    end
    if (x + w) > visibleWidth then
        w = visibleWidth - x
    end
    if w <= 0 then return end

    -- Compute offsets from the UnderlineLayer (covers the Overlay) to the EditBox
    -- text baseline.  Anchoring here avoids touching the EditBox layout, which
    -- would reset the cursor blink timer on every keystroke.
    local ebLeft   = self.EditBox:GetLeft()   or 0
    local ovLeft   = self.Overlay:GetLeft()   or 0
    local ebBottom = self.EditBox:GetBottom() or 0
    local ovTop    = self.Overlay:GetTop()    or 0
    local ebTop    = self.EditBox:GetTop()    or 0
    local offsetX    = (ebLeft - ovLeft) + x
    local offsetTopY = -(ovTop - ebTop)  -- negative: Y grows downward in SetPoint

    local tex   = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()
    local cfg   = self:GetConfig()

    if style == "highlight" then
        local height = (self.EditBox:GetHeight() or 20) - 6
        local c = cfg.HighlightColor or { r = 1, g = 0.18, b = 0.18, a = 0.36 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, height)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT", offsetX, offsetTopY - 3)
    else
        local ovBottom   = self.UnderlineLayer:GetBottom() or 0
        local offsetBotY = ebBottom - ovBottom
        local c = cfg.UnderlineColor or { r = 1, g = 0.2, b = 0.2, a = 0.9 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, 2)
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", self.UnderlineLayer, "BOTTOMLEFT", offsetX, offsetBotY + 2)
    end

    tex:Show()
    self.Underlines[#self.Underlines + 1] = tex
end

function Spellcheck:EnsureUnderlineLayer()
    if self.UnderlineLayer or not self.Overlay then return end
    local layer = CreateFrame("Frame", nil, self.Overlay)
    layer:SetAllPoints(self.Overlay)
    self.UnderlineLayer = layer
end

function Spellcheck:AcquireUnderline()
    local tex = table_remove(self.UnderlinePool)
    if tex then return tex end
    self:EnsureUnderlineLayer()
    return self.UnderlineLayer:CreateTexture(nil, "OVERLAY")
end

function Spellcheck:ClearUnderlines()
    for i = 1, #self.Underlines do
        local tex = self.Underlines[i]
        tex:Hide()
        self.UnderlinePool[#self.UnderlinePool + 1] = tex
    end
    self.Underlines = {}
end

-- ---------------------------------------------------------------------------
-- Multiline Underline Support
-- ---------------------------------------------------------------------------
-- These functions handle underline drawing for word-wrap-enabled multiline
-- EditBoxes.  They coexist with the single-line variants so both can be
-- tested independently during the transition to the multiline editor frame.

function Spellcheck:EnsureMLMeasureFS()
    if self.MLMeasureFS then return end
    self:EnsureMeasureFontString()
    if not self.MeasureFS then return end
    -- Parent to the same hidden frame as MeasureFS so scale is consistent.
    local parent = self.MeasureFS:GetParent()
    local fs = parent:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    fs:SetWordWrap(true)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    self.MLMeasureFS = fs
end

-- Sync MLMeasureFS font/spacing to the current EditBox and constrain its
-- width so word-wrap fires at the same column it would in the real box.
function Spellcheck:SyncMLMeasureFont(boxWidth)
    local fs = self.MLMeasureFS
    if not fs then return end
    local editBox = self.EditBox
    if editBox and editBox.GetFont then
        local face, size, flags = editBox:GetFont()
        if face and size then
            local curFace, curSize, curFlags = fs:GetFont()
            if curFace ~= face or curSize ~= size or curFlags ~= flags then
                fs:SetFont(face, size, flags or "")
            end
        end
        if editBox.GetSpacing and fs.SetSpacing then
            local spacing = editBox:GetSpacing() or 0
            if (fs:GetSpacing() or 0) ~= spacing then
                fs:SetSpacing(spacing)
            end
        end
    end
    fs:SetWidth(boxWidth)
end

-- Measure where the END of `prefix` falls inside a word-wrapped box.
-- Returns: lineIndex (0-based), xOnLine (pixels from left), lineHeight.
--
-- Uses binary search to find the start of the last visual line without
-- reimplementing WoW's word-wrap algorithm.  The search is O(log N) in
-- character count — typically ~10 SetText calls for a 1000-char prefix.
function Spellcheck:MeasureMLPrefix(prefix, boxWidth)
    self:EnsureMLMeasureFS()
    local fs = self.MLMeasureFS
    if not fs then return 0, 0, 14 end
    self:SyncMLMeasureFont(boxWidth)

    local lineHeight = fs:GetLineHeight() or 14
    if lineHeight <= 0 then lineHeight = 14 end

    if not prefix or prefix == "" then
        return 0, 0, lineHeight
    end

    fs:SetText(prefix)
    local totalHeight = fs:GetStringHeight() or lineHeight
    -- Round to nearest integer to absorb floating-point error in GetStringHeight.
    local lineCount = math_max(1, math_floor(totalHeight / lineHeight + 0.5))
    local lineIndex = lineCount - 1  -- 0-based

    -- Binary-search for the character offset where the last visual line begins.
    -- We look for the smallest i such that prefix[1..i] spans lineCount lines;
    -- all characters before i are on earlier lines.
    local lastLineStart = 0
    if lineIndex > 0 then
        local lo, hi = 1, #prefix
        while lo < hi do
            local mid = math_floor((lo + hi) / 2)
            fs:SetText(string_sub(prefix, 1, mid))
            local h = fs:GetStringHeight() or lineHeight
            local n = math_max(1, math_floor(h / lineHeight + 0.5))
            if n < lineCount then
                lo = mid + 1
            else
                hi = mid
            end
        end
        lastLineStart = lo
    end

    local lastLineText = string_sub(prefix, lastLineStart)
    fs:SetText(lastLineText)
    local xOnLine = fs:GetStringWidth() or 0
    return lineIndex, xOnLine, lineHeight
end

-- Return the vertical scroll position of the multiline EditBox in pixels.
-- Checks the EditBox natively first, then falls back to self.MLScrollFrame
-- for when the box sits inside an explicit scroll container (set by the
-- multiline editor frame on Bind).
function Spellcheck:GetVerticalScroll()
    local eb = self.EditBox
    if not eb then return 0 end
    if eb.GetVerticalScroll then return eb:GetVerticalScroll() or 0 end
    if self.MLScrollFrame and self.MLScrollFrame.GetVerticalScroll then
        return self.MLScrollFrame:GetVerticalScroll() or 0
    end
    return 0
end

function Spellcheck:RedrawUnderlines_ML()
    if not self.EditBox or not self._lastMisspellings then return end

    local text = self.EditBox:GetText() or ""
    local leftInset, rightInset = 0, 0
    if self.EditBox.GetTextInsets then
        leftInset, rightInset = self.EditBox:GetTextInsets()
        leftInset  = leftInset  or 0
        rightInset = rightInset or 0
    end
    local boxWidth   = (self.EditBox:GetWidth() or 200) - leftInset - rightInset
    local vertScroll = self:GetVerticalScroll()

    self:ClearUnderlines()
    for _, item in ipairs(self._lastMisspellings) do
        self:DrawUnderline_ML(item.startPos, item.endPos, text, vertScroll, boxWidth, leftInset)
    end
end

function Spellcheck:DrawUnderline_ML(startPos, endPos, text, vertScroll, boxWidth, leftInset)
    if not self.EditBox or not self.Overlay then return end

    local prefix = string_sub(text, 1, startPos - 1)
    local word   = string_sub(text, startPos, endPos)
    local lineIndex, xOnLine, lineHeight = self:MeasureMLPrefix(prefix, boxWidth)
    local w = self:MeasureText(word)

    -- Clip to right edge of this visual line.
    local remainingWidth = boxWidth - xOnLine
    if w > remainingWidth then w = remainingWidth end
    if w <= 0 then return end

    -- Clip to vertical visibility (skip lines scrolled out of view).
    local ebHeight   = self.EditBox:GetHeight() or 200
    local lineTop    = lineIndex * lineHeight - vertScroll
    local lineBottom = lineTop + lineHeight
    if lineBottom <= 0 or lineTop >= ebHeight then return end

    -- Build pixel offsets from UnderlineLayer origin to this word's position.
    -- UnderlineLayer covers the Overlay, so we compensate for the EditBox offset.
    local ebLeft = self.EditBox:GetLeft() or 0
    local ovLeft = self.Overlay:GetLeft() or 0
    local ebTop  = self.EditBox:GetTop()  or 0
    local ovTop  = self.Overlay:GetTop()  or 0
    local offsetX    = (ebLeft - ovLeft) + leftInset + xOnLine
    local offsetTopY = -(ovTop - ebTop)  -- negative: Y grows downward in SetPoint

    local tex   = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()
    local cfg   = self:GetConfig()

    if style == "highlight" then
        local c = cfg.HighlightColor or { r = 1, g = 0.18, b = 0.18, a = 0.36 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, lineHeight - 2)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT",
            offsetX, offsetTopY - lineTop - 2)
    else
        local c = cfg.UnderlineColor or { r = 1, g = 0.2, b = 0.2, a = 0.9 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, 2)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT",
            offsetX, offsetTopY - lineTop - lineHeight + 2)
    end

    tex:Show()
    self.Underlines[#self.Underlines + 1] = tex
end

