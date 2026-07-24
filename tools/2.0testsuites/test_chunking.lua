#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_chunking.lua  --  Chunking (message splitting) module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_chunking.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G = _G or {}
_G.C_AddOns = nil
_G.IsAddOnLoaded = nil

-- Mock YapperAPI for delineator and atomic pattern support.
_G.YapperAPI = {
    GetDelineator = function() return ">>" end,
    GetRegisteredAtomicPatterns = function() return {} end,
    RunFilter = function(_, _, payload) return payload end,
}

local YapperName = "Yapper"
local YapperTable = {
    API = _G.YapperAPI,
    Config = {
        Chat = {
            CHARACTER_LIMIT = 255,
            USE_DELINEATORS = true,
        },
    },
}

-- Load Chunking.lua
local loader, err = loadfile("Src/Chunking.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)

local Chunking = YapperTable.Chunking

-- ===========================================================================
-- Test 1: Short text (no splitting needed)
-- ===========================================================================
print("\nTest 1: Short text - no splitting")

local result = Chunking:Split("Hello, World!", 255)
check("single chunk returned", #result == 1)
check("text unchanged", result[1] == "Hello, World!")

-- ===========================================================================
-- Test 2: Empty / whitespace text
-- ===========================================================================
print("\nTest 2: Empty and whitespace text")

local empty = Chunking:Split("", 255)
check("empty string returns one empty chunk", #empty == 1)
check("empty chunk is empty", empty[1] == "")

local ws = Chunking:Split("   ", 255)
check("whitespace-only returns one empty chunk", #ws == 1)
check("whitespace trimmed to empty", ws[1] == "")

-- ===========================================================================
-- Test 3: Exact limit boundary
-- ===========================================================================
print("\nTest 3: Exact limit boundary")

local exact = string.rep("a", 50)
local res = Chunking:Split(exact, 50)
check("text at exactly the limit stays in one chunk", #res == 1)
check("text content preserved", res[1] == exact)

-- ===========================================================================
-- Test 4: Basic splitting on word boundaries
-- ===========================================================================
print("\nTest 4: Basic word-boundary splitting")

-- Build text that exceeds limit.
local words = {}
for i = 1, 20 do words[i] = "word" .. i end
local longText = table.concat(words, " ")  -- ~120 chars

local chunks = Chunking:Split(longText, 30)
check("multiple chunks created", #chunks > 1)

-- Verify no chunk exceeds the limit.
local allFit = true
for i, chunk in ipairs(chunks) do
    if #chunk > 30 then allFit = false end
end
check("all chunks within limit", allFit)

-- ===========================================================================
-- Test 5: Splitting with delineators enabled
-- ===========================================================================
print("\nTest 5: Splitting with delineators")

local longMsg = "This is a longer message that should be split into multiple chunks when the limit is very small."
local chunksD = Chunking:Split(longMsg, 40, {
    useDelineators = true,
    delineator = ">>",
})
check("delineated: multiple chunks", #chunksD > 1)

-- First chunk should end with " >>" if delineators are on.
if #chunksD > 1 then
    local endsWithDelineator = chunksD[1]:match(" >>$") ~= nil
    check("first chunk ends with delineator", endsWithDelineator)

    -- Subsequent chunks (except last) should start with ">> ".
    local startsCorrectly = true
    for i = 2, #chunksD - 1 do
        if not chunksD[i]:match("^>> ") then
            startsCorrectly = false
        end
    end
    if #chunksD > 2 then
        check("middle chunks start with prefix", startsCorrectly)
    end
end

-- ===========================================================================
-- Test 6: Splitting with delineators disabled
-- ===========================================================================
print("\nTest 6: Splitting with delineators disabled")

-- Override config to disable delineators.
YapperTable.Config.Chat.USE_DELINEATORS = false
local chunksND = Chunking:Split(longMsg, 40, { useDelineators = false })
YapperTable.Config.Chat.USE_DELINEATORS = true  -- restore
check("no-delineator: multiple chunks", #chunksND > 1)

local noDelineator = true
for _, chunk in ipairs(chunksND) do
    if chunk:match(">>") then noDelineator = false end
end
check("no delineator markers present", noDelineator)

-- ===========================================================================
-- Test 7: Colour codes preserved across chunks
-- ===========================================================================
print("\nTest 7: Colour code preservation")

local coloured = "|cFF00FF00This is a very long green coloured message that needs to be split because it is over the limit.|r"
local chunksC = Chunking:Split(coloured, 60)
check("colour text splits into multiple chunks", #chunksC > 1)

-- Second chunk should re-open the colour.
if #chunksC > 1 then
    local reopensColour = chunksC[2]:find("|cFF00FF00", 1, true) ~= nil
    check("second chunk re-opens colour code", reopensColour)
end

-- Last chunk or its predecessor should close colour.
local lastChunk = chunksC[#chunksC]
local closesOrNoColour = lastChunk:match("|r") ~= nil or not lastChunk:match("|c")
check("colour properly closed", closesOrNoColour)

-- ===========================================================================
-- Test 8: Hyperlink kept atomic (not split)
-- ===========================================================================
print("\nTest 8: Hyperlink atomicity")

local link = "|cFF0000FF|Hitem:12345:0:0:0|h[Epic Sword]|h|r"
local withLink = "Before " .. link .. " after text that goes on and on to fill space."
local chunksL = Chunking:Split(withLink, 80)

-- The link should appear intact in one of the chunks.
local linkFound = false
for _, chunk in ipairs(chunksL) do
    if chunk:find("[Epic Sword]", 1, true) then
        linkFound = true
    end
end
check("hyperlink kept in one chunk", linkFound)

-- ===========================================================================
-- Test 9: Texture escape kept atomic
-- ===========================================================================
print("\nTest 9: Texture escape atomicity")

local texture = "|TInterface/Icons/Spell_Nature_Starfall:16|t"
local withTex = "Start " .. texture .. " " .. string.rep("x", 100)
local chunksT = Chunking:Split(withTex, 80)

local texFound = false
for _, chunk in ipairs(chunksT) do
    if chunk:find("Spell_Nature_Starfall", 1, true) then
        texFound = true
    end
end
check("texture escape kept intact", texFound)

-- ===========================================================================
-- Test 10: Atlas escape {name} kept atomic
-- ===========================================================================
print("\nTest 10: Atlas escape atomicity")

local atlas = "{star}"
local withAtlas = "Rating: " .. atlas .. " " .. string.rep("y", 100)
local chunksA = Chunking:Split(withAtlas, 50)

local atlasFound = false
for _, chunk in ipairs(chunksA) do
    if chunk:find("{star}", 1, true) then
        atlasFound = true
    end
end
check("atlas escape kept intact", atlasFound)

-- ===========================================================================
-- Test 11: Paragraph isolation mode (ignoreParagraphMerging)
-- ===========================================================================
print("\nTest 11: Paragraph isolation")

local paragraphs = "First paragraph here.\nSecond paragraph here.\nThird paragraph."
local chunksP = Chunking:Split(paragraphs, 255, { ignoreParagraphMerging = true })
check("each paragraph is a separate chunk", #chunksP == 3)
check("first paragraph correct", chunksP[1] == "First paragraph here.")
check("second paragraph correct", chunksP[2] == "Second paragraph here.")
check("third paragraph correct", chunksP[3] == "Third paragraph.")

-- Blank lines are skipped.
local withBlanks = "Line one.\n\nLine two.\n\n\nLine three."
local chunksBlanks = Chunking:Split(withBlanks, 255, { ignoreParagraphMerging = true })
check("blank lines are skipped", #chunksBlanks == 3)

-- ===========================================================================
-- Test 12: UTF-8 safety (no broken multi-byte characters)
-- ===========================================================================
print("\nTest 12: UTF-8 safety")

-- Build a string with multi-byte chars (e.g. e-acute = 2 bytes in UTF-8).
local utf8text = string.rep("\xC3\xA9", 30)  -- 30x "e" = 60 bytes
local chunksU = Chunking:Split(utf8text, 20)

local allValidUTF8 = true
for _, chunk in ipairs(chunksU) do
    -- Check that no chunk ends on a continuation byte (0x80-0xBF).
    local lastByte = chunk:byte(#chunk)
    if lastByte and lastByte >= 0x80 and lastByte < 0xC0 then
        -- This is a continuation byte, which means the leading byte
        -- should be present (i.e. before it). Check the preceding byte.
        local prevByte = chunk:byte(#chunk - 1)
        if not prevByte or (prevByte >= 0x80 and prevByte < 0xC0) then
            allValidUTF8 = false
        end
    end
end
check("no broken UTF-8 sequences at chunk boundaries", allValidUTF8)

-- ===========================================================================
-- Test 13: Very long word (force-cut)
-- ===========================================================================
print("\nTest 13: Very long word force-cut")

local longWord = string.rep("x", 100)
local chunksLW = Chunking:Split(longWord, 30)
check("long word gets force-split", #chunksLW > 1)

local allUnder = true
for _, chunk in ipairs(chunksLW) do
    if #chunk > 30 then allUnder = false end
end
check("force-split chunks within limit", allUnder)

-- ===========================================================================
-- Test 14: GetDelineators API
-- ===========================================================================
print("\nTest 14: GetDelineators API")

local suffix, prefix = Chunking:GetDelineators()
check("suffix is ' >>'", suffix == " >>")
check("prefix is '>> '", prefix == ">> ")

-- ===========================================================================
-- Test 15: Continuation prefix on continuation chunks
-- ===========================================================================
print("\nTest 15: Continuation prefix")

local contText = "Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu."
local continuationEnabled = true
_G.YapperAPI.RunFilter = function(_, hook, payload)
    if continuationEnabled and hook == "PRE_CHUNK" then
        payload.continuationPrefix = "[cont] "
    end
    return payload
end
local chunksCont = Chunking:Split(contText, 50)
continuationEnabled = false
check("continuation: multiple chunks", #chunksCont > 1)
if #chunksCont > 1 then
    check("continuation prefix on chunk 2", chunksCont[2]:match("^>> %[cont%] ") ~= nil)
    check("no continuation prefix on chunk 1", not chunksCont[1]:match("^%[cont%] "))
end

-- ===========================================================================
-- Results
-- ===========================================================================
print("\n" .. string.rep("-", 50))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed.")
end
