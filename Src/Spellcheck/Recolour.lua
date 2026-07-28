--[[
    Spellcheck/Recolour.lua
    Canonical-text invariant and misspelling recolour engine.

    The overlay and multiline EditBoxes carry |cffrrggbb ... |r colour escapes
    around misspelled words at rest (injected by Recolour:Apply). All module
    logic operates on canonical (escape-free) text and canonical byte offsets;
    the helpers below are the single translation layer between the two spaces.
]]

local _, YapperTable = ...

local Recolour = {}
YapperTable.Recolour = Recolour

local type         = type
local string_byte  = string.byte
local string_sub   = string.sub
local string_find  = string.find
local string_format = string.format

-- Byte constants for '|', 'c', 'r', 'T', 'A'
local PIPE = 124

-- ---------------------------------------------------------------------------
-- Canonical accessors
-- ---------------------------------------------------------------------------

--- Return the editbox text with display-only escapes removed.
--- This is what all module logic should read instead of box:GetText().
--- @param box table  EditBox (overlay or multiline)
--- @return string
function Recolour.CanonicalText(box)
    if not box or not box.GetText then return "" end
    local text = box:GetText()
    if type(text) ~= "string" or text == "" then return "" end
    local Strip = YapperTable.Utils and YapperTable.Utils.StripDisplayEscapes
    if type(Strip) ~= "function" then return text end
    return Strip(YapperTable.Utils, text)
end

--- Translate a display byte offset (from GetCursorPosition) into a canonical
--- byte offset by walking the text and skipping stripped escape sequences
--- atomically. Hyperlink escapes are preserved in canonical text, so they
--- count on both sides; only |c/|cn/|r/|T|t/|A|a sequences are skipped.
--- A position landing inside an escape sequence clamps to the sequence start.
--- @param text string
--- @param displayPos number
--- @return number
function Recolour.CanonicalCursorFromText(text, displayPos)
    if type(text) ~= "string" then return 0 end
    displayPos = tonumber(displayPos) or 0
    if displayPos <= 0 then return 0 end
    local canon = 0
    local i = 1
    local n = #text
    while i <= displayPos and i <= n do
        if string_byte(text, i) == PIPE then
            local nxt = string_byte(text, i + 1)
            if nxt == 99 then -- 'c': |c + 8 hex, or |cnNAME:
                if string_byte(text, i + 2) == 110 then -- 'n'
                    local close = string_find(text, ":", i + 3, true)
                    if close and close <= displayPos then
                        i = close + 1
                    else
                        return canon
                    end
                elseif i + 9 <= displayPos then
                    i = i + 10
                else
                    return canon
                end
            elseif nxt == 114 then -- 'r': |r
                if i + 1 <= displayPos then
                    i = i + 2
                else
                    return canon
                end
            elseif nxt == 84 then -- 'T': |T...|t
                local close = string_find(text, "|t", i + 2, true)
                if close and close + 1 <= displayPos then
                    i = close + 2
                elseif close then
                    return canon
                else
                    i = i + 1 -- malformed; count the pipe as a byte
                end
            elseif nxt == 65 then -- 'A': |A...|a
                local close = string_find(text, "|a", i + 2, true)
                if close and close + 1 <= displayPos then
                    i = close + 2
                elseif close then
                    return canon
                else
                    i = i + 1
                end
            else
                -- |H hyperlinks and anything else: preserved, counts as bytes.
                canon = canon + 1
                i = i + 1
            end
        else
            canon = canon + 1
            i = i + 1
        end
    end
    return canon
end

--- Return the cursor position of an editbox as a canonical byte offset.
--- @param box table  EditBox (overlay or multiline)
--- @return number
function Recolour.CanonicalCursor(box)
    if not box or not box.GetText or not box.GetCursorPosition then return 0 end
    local pos = box:GetCursorPosition()
    if not pos then return 0 end
    return Recolour.CanonicalCursorFromText(box:GetText() or "", pos)
end

--- Canonical text and canonical cursor in a single read of the widget.
--- Falls back to end-of-text when GetCursorPosition is unavailable, mirroring
--- the `GetCursorPosition() or #text` idiom used throughout the codebase.
--- @param box table  EditBox (overlay or multiline)
--- @return string text, number cursor
function Recolour.CanonicalTextAndCursor(box)
    if not box or not box.GetText then return "", 0 end
    local raw = box:GetText() or ""
    local Strip = YapperTable.Utils and YapperTable.Utils.StripDisplayEscapes
    local text = (type(Strip) == "function" and raw ~= "") and Strip(YapperTable.Utils, raw) or raw
    local pos = box.GetCursorPosition and box:GetCursorPosition()
    if not pos then return text, #text end
    return text, Recolour.CanonicalCursorFromText(raw, pos)
end

-- ---------------------------------------------------------------------------
-- Colour resolution
-- ---------------------------------------------------------------------------

local DEFAULT_MISSPELLING_COLOUR = { r = 1.0, g = 0.0, b = 1.0 }

--- Resolve the effective misspelling colour for a box.
--- Designated extension point for on-the-fly visibility adaptation against
--- the box's themed text colour; currently returns the configured colour
--- verbatim. Kept pure (config read only) so it stays unit-testable.
--- @param box table  EditBox (unused today; part of the seam signature)
--- @return table  { r, g, b } with 0-1 floats
function Recolour.ResolveColour(box)
    local sc = YapperTable.Spellcheck
    if sc and type(sc.GetMisspellingColour) == "function" then
        return sc:GetMisspellingColour()
    end
    return DEFAULT_MISSPELLING_COLOUR
end

--- Build the "|cffrrggbb" escape prefix for an { r, g, b } colour (0-1 floats).
--- @param c table
--- @return string
function Recolour.ColourPrefix(c)
    local function byte(v)
        v = tonumber(v) or 0
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return math.floor(v * 255 + 0.5)
    end
    return string_format("|cff%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
end

-- ---------------------------------------------------------------------------
-- Display-text construction (pure)
-- ---------------------------------------------------------------------------

--- Wrap each misspelling span in colour escapes. Spans are inclusive
--- canonical byte ranges { startPos, endPos } in ascending, non-overlapping
--- order (as produced by YapperAPI:FindMisspellings). Out-of-order or
--- malformed spans are skipped rather than corrupting the text.
--- @param canonical string
--- @param spans table[]
--- @param prefix string  e.g. "|cffff3333"
--- @return string
function Recolour.BuildDisplayText(canonical, spans, prefix)
    if type(canonical) ~= "string" then return "" end
    if type(spans) ~= "table" or #spans == 0 then return canonical end
    prefix = prefix or "|cffff3333"
    local out = {}
    local pos = 1
    local n = #canonical
    for i = 1, #spans do
        local s = spans[i].startPos
        local e = spans[i].endPos
        if type(s) == "number" and type(e) == "number"
            and s >= pos and e >= s and e <= n then
            out[#out + 1] = string_sub(canonical, pos, s - 1)
            out[#out + 1] = prefix
            out[#out + 1] = string_sub(canonical, s, e)
            out[#out + 1] = "|r"
            pos = e + 1
        end
    end
    out[#out + 1] = string_sub(canonical, pos)
    return table.concat(out)
end

--- Translate a canonical cursor position into a display byte offset for
--- text built by BuildDisplayText. An opening escape (10 bytes) counts once
--- the caret is at or past the span start; a closing escape (2 bytes) counts
--- once the caret is past the span end. Caret at a span start stays outside
--- the colour run; caret at a span end stays inside it, so typed characters
--- extend the coloured word until the next pass (live tracking).
--- @param canonicalCursor number
--- @param spans table[]
--- @return number
function Recolour.ToDisplayCursor(canonicalCursor, spans)
    local c = tonumber(canonicalCursor) or 0
    if type(spans) ~= "table" then return c end
    local display = c
    for i = 1, #spans do
        local s = spans[i].startPos
        local e = spans[i].endPos
        if type(s) == "number" and type(e) == "number" then
            if s <= c then display = display + 10 end
            if e < c then display = display + 2 end
        end
    end
    return display
end

-- ---------------------------------------------------------------------------
-- Misspelling detection (scan window ported from the old underline renderer)
-- ---------------------------------------------------------------------------

-- Maximum number of characters to scan around the cursor for misspellings.
local SCAN_RADIUS = 1000
local SCAN_RECENTER_MARGIN = 200

local function ComputeSpans(rec, canonical, cursor, textSame)
    -- Short texts: scan everything (no window overhead). Unchanged text
    -- reuses the cached spans.
    if #canonical <= SCAN_RADIUS * 2 then
        rec._scanWindowStart = nil
        rec._scanWindowEnd = nil
        if textSame and rec._lastSpans then return rec._lastSpans end
        local words = YapperAPI and YapperAPI:FindMisspellings(canonical)
        return words or {}
    end

    -- Large text: scan window centered on the cursor, reused until the
    -- cursor approaches its margins or the text changes.
    local IsWordByte = YapperTable.Spellcheck and YapperTable.Spellcheck.IsWordByte
    if not IsWordByte then return {} end

    local needRescan = false
    if not rec._scanWindowStart or not rec._scanWindowEnd then
        needRescan = true
    elseif not textSame then
        needRescan = true
    elseif cursor - rec._scanWindowStart < SCAN_RECENTER_MARGIN
        or rec._scanWindowEnd - cursor < SCAN_RECENTER_MARGIN then
        needRescan = true
    end

    if not needRescan and rec._lastSpans then
        return rec._lastSpans
    end

    local textLen = #canonical
    local rawStart = math.max(1, cursor - SCAN_RADIUS)
    local rawEnd = math.min(textLen, cursor + SCAN_RADIUS)

    -- Snap start forward to the next word boundary (skip partial word).
    if rawStart > 1 then
        while rawStart <= rawEnd do
            local b = string_byte(canonical, rawStart)
            if not b or not IsWordByte(b) then break end
            rawStart = rawStart + 1
        end
    end

    -- Snap end backward to the previous word boundary (skip partial word).
    if rawEnd < textLen then
        while rawEnd >= rawStart do
            local b = string_byte(canonical, rawEnd)
            if not b or not IsWordByte(b) then break end
            rawEnd = rawEnd - 1
        end
    end

    rec._scanWindowStart = rawStart
    rec._scanWindowEnd = rawEnd

    local windowText = string_sub(canonical, rawStart, rawEnd)
    local words = YapperAPI and YapperAPI:FindMisspellings(windowText)

    -- Convert window-local positions to full-text positions.
    local spans = {}
    for _, item in ipairs(words or {}) do
        spans[#spans + 1] = {
            startPos = item.startPos + rawStart - 1,
            endPos   = item.endPos + rawStart - 1,
        }
    end
    return spans
end

-- ---------------------------------------------------------------------------
-- The recolour pass (sole writer of escapes)
-- ---------------------------------------------------------------------------

--- Recolour misspelled words in the bound editbox. Detection results are
--- cached by canonical text + dictionary identity; the display string is
--- rebuilt every call (cheap concat) and diffed against the widget text —
--- the diff is the recursion loop-breaker and caret-stability guarantee:
--- no SetText happens unless the rendered text would actually change.
--- @param box table  EditBox (overlay or multiline, whichever is bound)
function Recolour:Apply(box)
    local sc = YapperTable.Spellcheck
    if not box or not sc or type(sc.IsEnabled) ~= "function" or not sc:IsEnabled() then
        return
    end
    local dict = sc.GetDictionary and sc:GetDictionary()
    if not dict then return end

    local canonical = Recolour.CanonicalText(box)
    if canonical == "" then
        self._lastCanonical  = nil
        self._lastDict       = nil
        self._lastSpans      = nil
        self._scanWindowStart = nil
        self._scanWindowEnd  = nil
        return
    end

    -- Always route through ComputeSpans: unchanged text reuses cached spans,
    -- but the large-text window may still recenter when the cursor travels.
    local textSame = (self._lastCanonical == canonical and self._lastDict == dict)
    local cursor = Recolour.CanonicalCursor(box)
    self._lastSpans     = ComputeSpans(self, canonical, cursor, textSame)
    self._lastCanonical = canonical
    self._lastDict      = dict

    local spans = self._lastSpans or {}
    local display = Recolour.BuildDisplayText(canonical, spans,
        Recolour.ColourPrefix(Recolour.ResolveColour(box)))

    if display == (box.GetText and box:GetText() or "") then return end

    local canonCursor = Recolour.CanonicalCursor(box)
    box:SetText(display)
    if box.SetCursorPosition then
        box:SetCursorPosition(Recolour.ToDisplayCursor(canonCursor, spans))
    end
end

--- Remove any injected escapes from the box (spellcheck disabled, overlay
--- hiding) and drop detection caches. Replaces the old ClearUnderlines.
--- @param box table|nil
function Recolour:Clear(box)
    self._lastCanonical   = nil
    self._lastDict        = nil
    self._lastSpans       = nil
    self._scanWindowStart = nil
    self._scanWindowEnd   = nil
    if not box or not box.GetText then return end
    local raw = box:GetText() or ""
    if raw == "" then return end
    local canonical = Recolour.CanonicalText(box)
    if canonical == raw then return end -- no escapes present
    local canonCursor = Recolour.CanonicalCursor(box)
    box:SetText(canonical)
    if box.SetCursorPosition then
        box:SetCursorPosition(canonCursor)
    end
end

--- Force a rescan on the next Apply (user dictionary sets changed but the
--- text and dictionary identity did not).
function Recolour:Invalidate()
    self._lastCanonical = nil
end
