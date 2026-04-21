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
local type         = type
local math_min     = math.min
local math_max     = math.max
local math_floor   = math.floor
local math_abs     = math.abs
local string_sub   = string.sub
local string_byte  = string.byte
local table_remove = table.remove

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
    local ebLeft = self.EditBox:GetLeft() or 0
    local ovLeft = self.Overlay:GetLeft() or 0
    local offsetX = (ebLeft - ovLeft) + x

    -- Determine the visual line height.  OnCursorChanged gives us the cursor
    -- height which equals the actual rendered line height, immune to any frame
    -- resizing done by addons like ElvUI.  Fall back to the EditBox font size
    -- (or a safe default) when cursor data is not yet available.
    local lineH
    if type(self._lastCursorH) == "number" and self._lastCursorH > 0 then
        lineH = self._lastCursorH
    else
        local _, fontSize = self.EditBox:GetFont()
        lineH = (type(fontSize) == "number" and fontSize > 0) and fontSize or 14
    end

    -- The EditBox is inset `pad` px inside the Overlay on every side (0 when
    -- no border theme is active).  Single-line WoW EditBoxes vertically centre
    -- their text, so the text occupies a `lineH`-tall band in the middle of the
    -- EditBox.  Compute the top and bottom of that band in overlay-local Y
    -- (negative = downward from TOPLEFT), independent of the EditBox height.
    local activeTheme  = YapperTable.Theme and YapperTable.Theme:GetTheme()
    local borderActive = activeTheme and activeTheme.border == true
    local pad          = (borderActive and self.Overlay.BorderPad) or 0
    local editBoxH     = self.EditBox:GetHeight() or (lineH + 2 * pad)
    local textTopY     = -(pad + (editBoxH - lineH) / 2)   -- Y of text top from overlay TOPLEFT
    local textBotY     = textTopY - lineH                   -- Y of text bottom

    local tex   = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()
    local cfg   = self:GetConfig()

    if style == "highlight" then
        local c = cfg.HighlightColor or { r = 1, g = 0.18, b = 0.18, a = 0.36 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, lineH)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT", offsetX, textTopY)
    else
        local c = cfg.UnderlineColor or { r = 1, g = 0.2, b = 0.2, a = 0.9 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, 2)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT", offsetX, textBotY - 1)
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

-- Measure where a `word` appended to `prefix` falls inside a word-wrapped box.
-- Returns: yPixels (pixel distance from text-area top to the word's line),
--          xOnLine (pixels from left), lineHeight.
--
-- To correctly account for word-wrap, we must measure the prefix AND the word
-- together.  If we only measure prefix, WoW might fit it on line N, but adding
-- the word might force the word itself to line N+1.
function Spellcheck:MeasureMLWord(prefix, word, boxWidth)
    self:EnsureMLMeasureFS()
    local fs = self.MLMeasureFS
    if not fs then return 0, 0, 14 end
    self:SyncMLMeasureFont(boxWidth)

    local lineHeight = fs:GetLineHeight() or 14
    if lineHeight <= 0 then lineHeight = 14 end

    local fullText = (prefix or "") .. (word or "")
    if fullText == "" then return 0, 0, lineHeight end

    -- 1. Y coordinate
    -- Because fullText ends with our word (misspellings don't have trailing newlines),
    -- GetStringHeight cleanly measures everything including embedded \n without collapsing.
    fs:SetText(fullText)
    local totalH = fs:GetStringHeight() or lineHeight
    local yPixels = totalH - lineHeight
    if yPixels < 0 then yPixels = 0 end

    -- 2. X coordinate
    -- The word is at the very end of the text. It must reside on the last
    -- visual line of the final paragraph.
    local lastPara = fullText:match("([^\n]*)$") or fullText
    local xOnLine = 0

    if lastPara ~= "" then
        fs:SetText(lastPara)
        local paraH = fs:GetStringHeight() or lineHeight
        local paraLines = math_max(1, math_floor(paraH / lineHeight + 0.5))

        if paraLines == 1 then
            -- Entire paragraph fits on one line.
            local beforeWord = string_sub(lastPara, 1, #lastPara - #word)
            xOnLine = self:MeasureText(beforeWord)
        else
            -- Paragraph wraps. Binary search for the start of its last visual line.
            local lo, hi = 1, #lastPara
            while lo < hi do
                local mid = math_floor((lo + hi) / 2)
                fs:SetText(string_sub(lastPara, 1, mid))
                local mh = fs:GetStringHeight() or lineHeight
                local n  = math_max(1, math_floor(mh / lineHeight + 0.5))
                if n < paraLines then lo = mid + 1 else hi = mid end
            end

            -- Backtrack to the actual word-wrap boundary (a space).
            local spaceIdx = string_sub(lastPara, 1, lo):match(".*()[ \t]")
            local tailStart = lo
            if spaceIdx then
                fs:SetText(string_sub(lastPara, 1, spaceIdx))
                local spaceH = fs:GetStringHeight() or lineHeight
                local spaceLines = math_max(1, math_floor(spaceH / lineHeight + 0.5))
                if spaceLines == paraLines - 1 then
                    tailStart = spaceIdx + 1
                end
            end

            local lastLineText = string_sub(lastPara, tailStart)
            lastLineText = lastLineText:match("^[ ]*(.*)$") or ""

            if #lastLineText >= #word then
                local beforeWord = string_sub(lastLineText, 1, #lastLineText - #word)
                xOnLine = self:MeasureText(beforeWord)
            end
        end
    end

    return yPixels, xOnLine, lineHeight
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
    local yPixels, xOnLine, lineHeight = self:MeasureMLWord(prefix, word, boxWidth)
    local w = self:MeasureText(word)

    -- Clip to right edge of this visual line.
    -- Subtract 1px to compensate for the sub-pixel difference between
    -- FontString measurement and the EditBox's actual glyph rendering.
    local remainingWidth = boxWidth - xOnLine
    if w > remainingWidth then w = remainingWidth end
    w = w - 1
    if w <= 0 then return end

    -- Clip to vertical visibility (skip lines scrolled out of view).
    -- yPixels is the pixel distance from text-area top to this line's top,
    -- computed from GetStringHeight() accumulation (no lineCount*lineHeight drift).
    local ebHeight   = self.EditBox:GetHeight() or 200
    local lineTop    = yPixels - vertScroll
    local lineBottom = lineTop + lineHeight
    if lineBottom <= 0 or lineTop >= ebHeight then return end

    -- Build pixel offsets from UnderlineLayer origin to this word's position.
    -- UnderlineLayer covers the Overlay (the multiline container), so we
    -- compensate for the EditBox's position within the container AND its
    -- top text inset (text does not start at the EditBox frame's top edge).
    local ebLeft = self.EditBox:GetLeft() or 0
    local ovLeft = self.Overlay:GetLeft() or 0
    local ebTop  = self.EditBox:GetTop()  or 0
    local ovTop  = self.Overlay:GetTop()  or 0

    local topInset = 0
    if self.EditBox.GetTextInsets then
        local _, _, t = self.EditBox:GetTextInsets()
        topInset = t or 0
    end

    local offsetX    = (ebLeft - ovLeft) + leftInset + xOnLine - 1
    -- offsetTopY reaches the top of the text area (EditBox top + text inset).
    local offsetTopY = -(ovTop - ebTop) - topInset

    local tex   = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()
    local cfg   = self:GetConfig()

    if style == "highlight" then
        local c = cfg.HighlightColor or { r = 1, g = 0.18, b = 0.18, a = 0.36 }
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        tex:SetSize(w, lineHeight)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.UnderlineLayer, "TOPLEFT",
            offsetX, offsetTopY - lineTop)
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

