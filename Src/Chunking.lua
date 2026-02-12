--[[
    Message splitting.

    Splits text into chunks that fit within WoW's byte limit, preserving
    colour codes, hyperlinks, texture/atlas escapes, and word boundaries.
    Adds optional delineators (" >>" / ">> ") for continuation.
]]

local YapperName, YapperTable = ...

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
        local ch = text:sub(pos, pos)

        -- ── WoW escape: starts with | ────────────────────────────────
        if ch == "|" then
            local nxt = text:sub(pos + 1, pos + 1)

            if nxt == "c" then
                -- Colour open: |cAARRGGBB  (10 bytes)
                tokens[#tokens + 1] = text:sub(pos, pos + 9)
                pos = pos + 10

            elseif nxt == "r" then
                -- Colour reset: |r  (2 bytes)
                tokens[#tokens + 1] = text:sub(pos, pos + 1)
                pos = pos + 2

            elseif nxt == "H" then
                -- Hyperlink: |H<type>:<data>|h[display text]|h
                local metaEnd = text:find("|h", pos + 2, true)
                if metaEnd then
                    local displayEnd = text:find("|h", metaEnd + 2, true)
                    if displayEnd then
                        tokens[#tokens + 1] = text:sub(pos, displayEnd + 1)
                        pos = displayEnd + 2
                    else
                        -- Malformed — take up to first |h.
                        tokens[#tokens + 1] = text:sub(pos, metaEnd + 1)
                        pos = metaEnd + 2
                    end
                else
                    -- No |h at all — emit the pipe as plain text.
                    tokens[#tokens + 1] = ch
                    pos = pos + 1
                end

            elseif nxt == "T" or nxt == "t" then
                -- Texture: |T<path>|t
                local closePos = text:find("|t", pos + 2, true)
                if closePos then
                    tokens[#tokens + 1] = text:sub(pos, closePos + 1)
                    pos = closePos + 2
                else
                    tokens[#tokens + 1] = text:sub(pos, pos + 1)
                    pos = pos + 2
                end

            elseif nxt == "A" then
                -- Atlas marker: |A<name>|a
                local closePos = text:find("|a", pos + 2, true)
                if closePos then
                    tokens[#tokens + 1] = text:sub(pos, closePos + 1)
                    pos = closePos + 2
                else
                    tokens[#tokens + 1] = text:sub(pos, pos + 1)
                    pos = pos + 2
                end

            else
                -- Unknown escape — emit just the pipe.
                tokens[#tokens + 1] = ch
                pos = pos + 1
            end

        -- ── Atlas shorthand: {atlas} ─────────────────────────────────
        elseif ch == "{" then
            local closePos = text:find("}", pos + 1, true)
            if closePos then
                tokens[#tokens + 1] = text:sub(pos, closePos)
                pos = closePos + 1
            else
                tokens[#tokens + 1] = ch
                pos = pos + 1
            end

        -- ── Plain text: consume up to the next special character ─────
        else
            local nextSpecial = text:find("[|{]", pos + 1)
            if nextSpecial then
                tokens[#tokens + 1] = text:sub(pos, nextSpecial - 1)
                pos = nextSpecial
            else
                tokens[#tokens + 1] = text:sub(pos)
                pos = len + 1
            end
        end
    end

    return tokens
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Search backwards for a space to split on.
local function FindSplitSpace(s)
    for i = #s, 1, -1 do
        if s:byte(i) == 32 then return i end
    end
    return nil
end

-- Find a safe byte position to cut without breaking a UTF-8 sequence.
local function SafeUTF8Cut(s, maxBytes)
    if maxBytes >= #s then return #s end
    local pos = maxBytes
    while pos > 0 do
        local b = s:byte(pos)
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
        chunks[#chunks + 1] = table.concat(parts)
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

--- Split text into chunks that each fit within the byte limit.
function Chunking:Split(text, limit, useDelineators, delineator, prefix)
    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}

    limit          = limit or cfg.CHARACTER_LIMIT or 255
    useDelineators = (useDelineators ~= nil) and useDelineators
                     or (cfg.USE_DELINEATORS ~= false)
    delineator     = delineator or cfg.DELINEATOR or " >>"
    prefix         = prefix     or cfg.PREFIX     or ">> "

    if not useDelineators then
        delineator = ""
        prefix     = ""
    end

    -- Trim.
    text = text:match("^%s*(.-)%s*$") or ""

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

    for _, token in ipairs(tokens) do
        local isColour = (token:sub(1, 2) == "|c" and #token == 10)
        local isReset  = (token == "|r")
        local isEscape = (#token > 1 and token:sub(1, 1) == "|")
                         or token:sub(1, 1) == "{"

        -- How many bytes the delineator/colour-close would cost at EOL.
        local suffixCost = #delineator + (colour and 2 or 0)
        local effective  = limit - suffixCost

        -- ── Token fits ───────────────────────────────────────────────
        if size + #token <= effective then
            parts[#parts + 1] = token
            size = size + #token

        -- ── Escape sequence that doesn't fit — keep it atomic ────────
        elseif isEscape then
            -- Close current chunk.
            if colour then parts[#parts + 1] = "|r" end
            if delineator ~= "" then parts[#parts + 1] = delineator end
            parts, size = FlushChunk(chunks, parts)

            -- Open new chunk.
            size = StartNewChunk(parts, size, prefix, colour)
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
                    if colour then parts[#parts + 1] = "|r" end
                    if delineator ~= "" then parts[#parts + 1] = delineator end
                    parts, size = FlushChunk(chunks, parts)
                    size = StartNewChunk(parts, size, prefix, colour)
                    -- Recalculate and loop.
                else
                    -- Try to split on a word boundary.
                    local bite  = remaining:sub(1, space)
                    local split = FindSplitSpace(bite)

                    if split and split > 0 then
                        -- Split on the space (discard the space itself).
                        parts[#parts + 1] = remaining:sub(1, split - 1)
                        size = size + (split - 1)
                        remaining = remaining:sub(split + 1)
                    else
                        -- No space found — force-cut (UTF-8 safe).
                        local cut = SafeUTF8Cut(remaining, space)
                        if cut <= 0 then cut = 1 end
                        parts[#parts + 1] = remaining:sub(1, cut)
                        size = size + cut
                        remaining = remaining:sub(cut + 1)
                    end

                    -- Close chunk.
                    if colour then parts[#parts + 1] = "|r" end
                    if delineator ~= "" then parts[#parts + 1] = delineator end
                    parts, size = FlushChunk(chunks, parts)
                    size = StartNewChunk(parts, size, prefix, colour)
                end
            end
        end

        -- Track colour state.
        if isColour then colour = token end
        if isReset  then colour = nil   end
    end

    -- Flush the final chunk (no delineator on the last one).
    if #parts > 0 then
        chunks[#chunks + 1] = table.concat(parts)
    end

    return chunks
end

-- ---------------------------------------------------------------------------
-- Delineator API
-- ---------------------------------------------------------------------------

local function NormalizeMarker(raw)
    local marker = tostring(raw or "")
    marker = marker:match("^%s*(.-)%s*$") or ""
    return marker
end

--- Returns the delineation markers currently in use.
function Chunking:GetDelineators()
    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}
    local marker = NormalizeMarker(cfg.DELINEATOR or cfg.PREFIX)
    if marker == "" then
        return "", ""
    end
    return " " .. marker, marker .. " "
end

--- Update delineation markers.
function Chunking:SetDelineators(newDelineator, newPrefix)
    local cfg = YapperTable.Config and YapperTable.Config.Chat
    if not cfg then return end
    local source = (newDelineator ~= nil and newDelineator)
                or (newPrefix ~= nil and newPrefix)
                or cfg.DELINEATOR
                or cfg.PREFIX
    local marker = NormalizeMarker(source)

    -- Prefix/suffix use the same marker, with whitespace added by us.
    -- Marker is treated as an opaque UTF-8 byte string (no slicing performed).
    if marker == "" then
        cfg.DELINEATOR = ""
        cfg.PREFIX     = ""
    else
        cfg.DELINEATOR = " " .. marker
        cfg.PREFIX     = marker .. " "
    end
end
