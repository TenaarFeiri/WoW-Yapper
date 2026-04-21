--[[
    Message splitting.

    Splits text into chunks that fit within WoW's byte limit, preserving
    colour codes, hyperlinks, texture/atlas escapes, and word boundaries.
    Adds optional delineators (" >>" / ">> ") for continuation.
]]

local YapperName, YapperTable = ...

-- Localise Lua globals for performance
local string_byte   = string.byte
local string_sub    = string.sub
local string_find   = string.find
local string_match  = string.match
local string_gmatch = string.gmatch
local table_concat  = table.concat
local type     = type
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local tonumber = tonumber
local select   = select

local Chunking = {}
YapperTable.Chunking = Chunking

-- ---------------------------------------------------------------------------
-- Tokeniser
-- ---------------------------------------------------------------------------

-- Tokenise text into atomic tokens (escape sequences stay intact).
local function Tokenise(text)
    local tokens = {}
    local pos = 1
    local len = #text

    while pos <= len do
        local b1 = string_byte(text, pos)

        -- ── WoW escape: starts with | (124) ──────────────────────────
        if b1 == 124 then
            local b2 = string_byte(text, pos + 1)

            if b2 == 99 then -- "c"
                -- Colour open.  Consume |c plus everything up to the
                -- next pipe — standard |cAARRGGBB (10 bytes) and the
                -- shorter non-hex variants WoW 12.0 produces both work.
                local nextPipe = string_find(text, "|", pos + 2, true)
                if nextPipe then
                    tokens[#tokens + 1] = string_sub(text, pos, nextPipe - 1)
                    pos = nextPipe
                else
                    tokens[#tokens + 1] = string_sub(text, pos)
                    pos = len + 1
                end

            elseif b2 == 114 then -- "r"
                -- Colour reset: |r  (2 bytes)
                tokens[#tokens + 1] = string_sub(text, pos, pos + 1)
                pos = pos + 2

            elseif b2 == 72 then -- "H"
                -- Hyperlink: |H<type>:<data>|h[display text]|h
                local metaEnd = string_find(text, "|h", pos + 2, true)
                if metaEnd then
                    local displayEnd = string_find(text, "|h", metaEnd + 2, true)
                    if displayEnd then
                        tokens[#tokens + 1] = string_sub(text, pos, displayEnd + 1)
                        pos = displayEnd + 2
                    else
                        -- Malformed — take up to first |h.
                        tokens[#tokens + 1] = string_sub(text, pos, metaEnd + 1)
                        pos = metaEnd + 2
                    end
                else
                    -- No |h at all — emit the pipe as plain text.
                    tokens[#tokens + 1] = string_sub(text, pos, pos)
                    pos = pos + 1
                end

            elseif b2 == 84 or b2 == 116 then -- "T" or "t"
                -- Texture: |T<path>|t
                local closePos = string_find(text, "|t", pos + 2, true)
                if closePos then
                    tokens[#tokens + 1] = string_sub(text, pos, closePos + 1)
                    pos = closePos + 2
                else
                    tokens[#tokens + 1] = string_sub(text, pos, pos + 1)
                    pos = pos + 2
                end

            elseif b2 == 65 then -- "A"
                -- Atlas marker: |A<name>|a
                local closePos = string_find(text, "|a", pos + 2, true)
                if closePos then
                    tokens[#tokens + 1] = string_sub(text, pos, closePos + 1)
                    pos = closePos + 2
                else
                    tokens[#tokens + 1] = string_sub(text, pos, pos + 1)
                    pos = pos + 2
                end

            else
                -- Unknown escape — emit just the pipe.
                tokens[#tokens + 1] = string_sub(text, pos, pos)
                pos = pos + 1
            end

        -- ── Atlas shorthand: {atlas} (123) ───────────────────────────
        elseif b1 == 123 then
            local closePos = string_find(text, "}", pos + 1, true)
            if closePos then
                tokens[#tokens + 1] = string_sub(text, pos, closePos)
                pos = closePos + 1
            else
                tokens[#tokens + 1] = string_sub(text, pos, pos)
                pos = pos + 1
            end

        -- ── Plain text: consume up to the next special character ─────
        else
            local nextSpecial = string_find(text, "[|{]", pos + 1)
            if nextSpecial then
                tokens[#tokens + 1] = string_sub(text, pos, nextSpecial - 1)
                pos = nextSpecial
            else
                tokens[#tokens + 1] = string_sub(text, pos)
                pos = len + 1
            end
        end
    end

    return tokens
end

-- ---------------------------------------------------------------------------
-- Continuation delimiter pairs
-- ---------------------------------------------------------------------------
-- When a chunk boundary falls inside one of these pairs the closer is
-- appended to the outgoing chunk and the opener is prepended to the next,
-- e.g.  "I am saying >>"  /  ">> that I am splitting."
-- Longer / more-specific pairs must appear before shorter ones ("((" before "(").

--- Constructor: MakeDelim(open [, close])
--- When close is omitted the delimiter is symmetric (open == close).
---
--- Yes, I totally stole this idea from Chattery.
--- Sorry!
local function MakeDelim(open, close)
    return { open = open, close = close or open }
end

---@type { open: string, close: string }[]
local CONTINUATION_PAIRS = {
    MakeDelim('"'),           -- "dialogue"
    MakeDelim("**"),          -- **emote bold** (before single *)
    MakeDelim("*"),           -- *emote*
    MakeDelim("((", "))"),    -- ((OOC double paren)) (before single)
    MakeDelim("(", ")"),      -- (OOC single paren)
    MakeDelim("<", ">"),      -- <angle brackets>
}

-- Returns the first unclosed pair found in text, or nil.
-- Symmetric pairs (same open/close char) use parity counting.  To avoid
-- introducing new behaviour for users who don't run TotalRP3, the logic
-- is gated behind a one‑time AddOn check; if TotalRP3 isn't loaded we
-- simply act as though no pairs exist.
local TRP3_DETECTED
local function EnsureTRP3()
    if TRP3_DETECTED == nil then
        -- prefer the secure C_ API
        TRP3_DETECTED = C_AddOns.IsAddOnLoaded("totalRP3")
    end
    return TRP3_DETECTED
end

local function FindUnclosedPair(text)
    if not EnsureTRP3() then
        return nil
    end

    for _, pair in ipairs(CONTINUATION_PAIRS) do
        if pair.open == pair.close then
            -- Normal symmetric delimiter: parity count suffices.
            local count = 0
            local pos   = 1
            while true do
                local s = string_find(text, pair.open, pos, true)
                if not s then break end
                count = count + 1
                pos   = s + #pair.open
            end
            if count % 2 == 1 then
                return pair
            end
        else
            -- Find the last opener; if no closer follows it, the pair is open.
            local lastOpen = nil
            local pos      = 1
            while true do
                local s = string_find(text, pair.open, pos, true)
                if not s then break end
                lastOpen = s
                pos      = s + #pair.open
            end
            if lastOpen then
                local closePos = string_find(text, pair.close, lastOpen + #pair.open, true)
                if not closePos then
                    return pair
                end
            end
        end
    end
    return nil
end

--- Returns true when `close` appears at least once in tokens[fromIndex..#tokens].
--- We only look for the literal close string — good enough for a "does it exist?"
--- check without re-running the full heuristics.
local function CloseExistsAhead(tokens, fromIndex, close)
    for i = fromIndex, #tokens do
        if string_find(tokens[i], close, 1, true) then
            return true
        end
    end
    return false
end

--- Look for an unclosed delimiter pair in the accumulated `parts`.
--- Only injects a close (and returns the matching open for the next chunk)
--- when the closing delimiter actually appears somewhere in the remaining
--- tokens — i.e. the user *does* intend to close it eventually.  If there
--- is no closer anywhere ahead, assume mistake or intentional open.
local function InjectContClose(parts, tokens, fromIndex)
    local pair = FindUnclosedPair(table_concat(parts))
    if pair then
        if CloseExistsAhead(tokens, fromIndex, pair.close) then
            parts[#parts + 1] = pair.close
            return pair.open
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Search backwards for a space to split on.
local function FindSplitSpace(s)
    for i = #s, 1, -1 do
        if string_byte(s, i) == 32 then return i end
    end
    return nil
end

-- Find a safe byte position to cut without breaking a UTF-8 sequence.
local function SafeUTF8Cut(s, maxBytes)
    if maxBytes >= #s then return #s end
    local pos = maxBytes
    while pos > 0 do
        local b = string_byte(s, pos)
        -- ASCII or UTF-8 leading byte — safe to cut here.
        if b < 128 or b >= 192 then
            -- Leading byte of multi-byte char: cut before it.
            if b >= 192 then
                return pos - 1
            end
            return pos
        end
        pos = pos - 1
    end
    return maxBytes  -- safety fallback
end

-- ---------------------------------------------------------------------------
-- Chunk flushing helpers
-- ---------------------------------------------------------------------------

-- Flush accumulated parts into chunks and return fresh accumulators.
local function FlushChunk(chunks, parts)
    if #parts > 0 then
        chunks[#chunks + 1] = table_concat(parts)
    end
    return {}, 0
end

-- Start a new chunk: prepend prefix and re-open active colour.
local function StartNewChunk(parts, size, prefix, colour)
    if prefix ~= "" then
        parts[#parts + 1] = prefix
        size = size + #prefix
    end
    if colour then
        parts[#parts + 1] = colour
        size = size + #colour
    end
    return size
end

-- ---------------------------------------------------------------------------
-- Main split function
-- ---------------------------------------------------------------------------

-- Normalize marker helper (defined early so Split can call it).
local function NormaliseMarker(raw)
    local marker = tostring(raw or "")
    marker = string_match(marker, "^%s*(.-)%s*$") or ""
    return marker
end


--- Split text into chunks that each fit within the byte limit.
function Chunking:Split(text, limit, ignoreParagraphMerging, useDelineators, delineator, prefix)
    -- Paragraph isolation for "Send All": keep each paragraph as a standalone chunk
    if ignoreParagraphMerging and string_find(text, "\n") then
        local allChunks = {}
        -- Iterate over every line, splitting by \n
        for paragraph in string_gmatch(text .. "\n", "(.-)\n") do
            -- Only process non-empty lines (skip blank lines)
            if paragraph ~= "" then
                -- Recurse into the standard splitting logic for this paragraph alone
                local pChunks = self:Split(paragraph, limit, false, useDelineators, delineator, prefix)
                for _, chunk in ipairs(pChunks) do
                    allChunks[#allChunks + 1] = chunk
                end
            end
        end
        return allChunks
    end

    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}

    limit          = limit or cfg.CHARACTER_LIMIT or 255
    useDelineators = (useDelineators ~= nil) and useDelineators
                     or (cfg.USE_DELINEATORS ~= false)
    -- Normalize markers: accept explicit args or config values (which
    -- may already include or omit spacing).  Treat the marker as an
    -- opaque UTF-8 string and add spacing here to ensure consistent
    -- behaviour when building chunks.
    local markerSource = delineator or cfg.DELINEATOR or cfg.PREFIX or ""
    local marker = NormaliseMarker(markerSource)
    if marker == "" then
        delineator = ""
        prefix = ""
    else
        delineator = " " .. marker
        prefix = marker .. " "
    end

    if not useDelineators then
        delineator = ""
        prefix     = ""
    end

    -- Trim.
    text = string_match(text, "^%s*(.-)%s*$") or ""

    -- Fast path: already fits.
    if #text <= limit then
        return { text }
    end

    -- ── Tokenise ─────────────────────────────────────────────────────
    local tokens = Tokenise(text)

    local chunks = {}
    local parts  = {}   -- accumulator for the current chunk
    local size   = 0    -- byte count of the current chunk
    local colour = nil  -- active |cXXXXXXXX tag (re-opened on new chunks)

    for i = 1, #tokens do
        local token = tokens[i]
        local b1, b2 = string_byte(token, 1, 2)
        local isColour = (b1 == 124 and b2 == 99 and #token >= 4)
        local isReset  = (b1 == 124 and b2 == 114 and #token == 2)
        local isEscape = (b1 == 124 and #token > 1) or b1 == 123

        -- How many bytes the delineator/colour-close would cost at EOL.
        local suffixCost = #delineator + (colour and 2 or 0)
        local effective  = limit - suffixCost

        -- ── Token fits ───────────────────────────────────────────────
        if size + #token <= effective then
            parts[#parts + 1] = token
            size = size + #token

        -- ── Escape sequence that doesn't fit — keep it atomic ────────
        elseif isEscape then
            -- Prevent orphaned link parts across chunks.  WoW silently
            -- drops a message whose hyperlink structure is incomplete.
            -- Case A: |c is the last part (its |H didn't fit).
            -- Case B: |c + |H are the last two parts (the closing |r
            --         didn't fit).  Pull back the whole group.
            local movedParts = {}
            if #parts > 0 then
                local last = parts[#parts]
                local lb1, lb2
                if last then lb1, lb2 = string_byte(last, 1, 2) end
                
                if last and lb1 == 124 and lb2 == 99 and #last >= 4 then
                    -- Case A: orphaned colour code.
                    movedParts[1] = last
                    parts[#parts] = nil
                    size = size - #last
                    colour = nil
                elseif last and #last > 2 and lb1 == 124 and lb2 == 72 then
                    -- The |H token is incomplete without its |r.
                    -- Check if the part before it is a |c colour code.
                    local prev = #parts > 1 and parts[#parts - 1] or nil
                    local pb1, pb2
                    if prev then pb1, pb2 = string_byte(prev, 1, 2) end
                    
                    if prev and pb1 == 124 and pb2 == 99 and #prev >= 4 then
                        -- Case B: pull back both |c and |H.
                        movedParts[1] = prev   -- |c
                        movedParts[2] = last   -- |H
                        parts[#parts] = nil     -- remove |H
                        parts[#parts] = nil     -- remove |c
                        size = size - #prev - #last
                        colour = nil
                    end
                end
            end

            -- Close current chunk.
            local nextOpen = InjectContClose(parts, tokens, i)
            if colour then parts[#parts + 1] = "|r" end
            if delineator ~= "" then parts[#parts + 1] = delineator end
            parts, size = FlushChunk(chunks, parts)

            -- Open new chunk.
            size = StartNewChunk(parts, size, prefix, colour)
            if nextOpen then parts[#parts + 1] = nextOpen; size = size + #nextOpen end

            -- Re-inject the pulled-back parts, then the current token.
            for _, mp in ipairs(movedParts) do
                parts[#parts + 1] = mp
                size = size + #mp
            end
            if #movedParts > 0 then
                local mpb1, mpb2 = string_byte(movedParts[1], 1, 2)
                if mpb1 == 124 and mpb2 == 99 then
                    colour = movedParts[1]
                end
            end

            parts[#parts + 1] = token
            size = size + #token

        -- ── Plain text too large — word-level split ──────────────────
        else
            local remaining = token

            while true do
                suffixCost = #delineator + (colour and 2 or 0)
                effective  = limit - suffixCost
                local space = effective - size

                if #remaining <= space then
                    -- Leftover fits — append and stop.
                    if #remaining > 0 then
                        parts[#parts + 1] = remaining
                        size = size + #remaining
                    end
                    break
                end

                if space <= 0 then
                    -- Current chunk is full with just overhead; flush it.
                    -- Pass i+1 as fromIndex: the remaining text includes the
                    -- rest of this token (still in `remaining`) plus tokens
                    -- beyond i.
                    local nextOpen = InjectContClose(parts, tokens, i)
                    if colour then parts[#parts + 1] = "|r" end
                    if delineator ~= "" then parts[#parts + 1] = delineator end
                    parts, size = FlushChunk(chunks, parts)
                    size = StartNewChunk(parts, size, prefix, colour)
                    if nextOpen then parts[#parts + 1] = nextOpen; size = size + #nextOpen end
                    -- Recalculate and loop.
                else
                    -- Try to split on a word boundary.
                    local bite  = string_sub(remaining, 1, space)
                    local split = FindSplitSpace(bite)

                    if split and split > 0 then
                        -- Split on the space (discard the space itself).
                        parts[#parts + 1] = string_sub(remaining, 1, split - 1)
                        size = size + (split - 1)
                        remaining = string_sub(remaining, split + 1)
                    else
                        -- No space found — force-cut (UTF-8 safe).
                        local cut = SafeUTF8Cut(remaining, space)
                        if cut <= 0 then cut = 1 end
                        parts[#parts + 1] = string_sub(remaining, 1, cut)
                        size = size + cut
                        remaining = string_sub(remaining, cut + 1)
                    end

                    -- Close chunk. fromIndex=i so CloseExistsAhead sees both
                    -- `remaining` (still part of tokens[i]) and all later tokens.
                    local nextOpen = InjectContClose(parts, tokens, i)
                    if colour then parts[#parts + 1] = "|r" end
                    if delineator ~= "" then parts[#parts + 1] = delineator end
                    parts, size = FlushChunk(chunks, parts)
                    size = StartNewChunk(parts, size, prefix, colour)
                    if nextOpen then parts[#parts + 1] = nextOpen; size = size + #nextOpen end
                end
            end
        end

        -- Track colour state.
        if isColour then colour = token end
        if isReset  then colour = nil   end

    end

    -- Flush the final chunk (no delineator on the last one).
    if #parts > 0 then
        chunks[#chunks + 1] = table_concat(parts)
    end

    return chunks
end

-- ---------------------------------------------------------------------------
-- Delineator API
-- ---------------------------------------------------------------------------

--- Returns the delineation markers currently in use.
function Chunking:GetDelineators()
    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}
    local marker = NormaliseMarker(cfg.DELINEATOR or cfg.PREFIX)
    if marker == "" then
        return "", ""
    end
    return " " .. marker, marker .. " "
end
