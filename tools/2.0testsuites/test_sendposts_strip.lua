#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_sendposts_strip.lua  --  SendPosts display-escape stripping
-- Run from the repo root:  lua tools/2.0testsuites/test_sendposts_strip.lua
--
-- Asserts the systemic guarantee: display-only escapes (spellcheck
-- recolouring, pasted colour codes) are stripped at Chat:SendPosts entry,
-- so history, PRE_SEND filters, chunking and delivery all see canonical
-- text — while hyperlinks survive intact.
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

_G.print = print

local YapperName = "Yapper"
local YapperTable = {
    Config = { Chat = { CHARACTER_LIMIT = 255 } },
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader(YapperName, YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end

-- Recorded history entries and delivered messages.
local historyAdds = {}
YapperTable.History = {
    AddChatHistory = function(_, text, chatType, target)
        historyAdds[#historyAdds + 1] = { text = text, chatType = chatType, target = target }
    end,
}

-- Chunking passes each post through as a single chunk.
YapperTable.Chunking = {
    Split = function(_, post) return { post } end,
}

loadModule("Src/Chat.lua")
local Chat = YapperTable.Chat

-- Capture delivery without touching Router/Queue.
local delivered = {}
Chat.DirectSend = function(_, msg)
    delivered[#delivered + 1] = msg
    return true
end

-- ===========================================================================
-- Test 1: recoloured text is stripped everywhere downstream
-- ===========================================================================
print("\nTest 1: recoloured text is stripped before history and delivery")

local coloured = "I |cffff3333mispelled|r a wurd"
local ok = Chat:SendPosts({ coloured }, "SAY", nil, nil)

check("send succeeds", ok == true)
check("history records canonical text",
    #historyAdds == 1 and historyAdds[1].text == "I mispelled a wurd")
check("delivery is canonical",
    #delivered == 1 and delivered[1] == "I mispelled a wurd")

-- ===========================================================================
-- Test 2: hyperlinks survive the strip
-- ===========================================================================
print("\nTest 2: hyperlinks survive")

historyAdds = {}
delivered = {}
local linked = "look |cffff0000|Hitem:1234|h[Shiny]|h|r here"
ok = Chat:SendPosts({ linked }, "SAY", nil, nil)

check("send succeeds", ok == true)
check("item link keeps its required colour wrapper",
    delivered[1] == "look |cffff0000|Hitem:1234|h[Shiny]|h|r here")
check("history matches delivery",
    historyAdds[1] and historyAdds[1].text == delivered[1])

historyAdds = {}
delivered = {}
local modernLinked = "look |cnIQ4:|Hitem:1234|h[Coiled Serpent Idol]|h|r here"
ok = Chat:SendPosts({ modernLinked }, "SAY", nil, nil)
check("modern named-colour link sends successfully", ok == true)
check("modern named-colour wrapper survives",
    delivered[1] == modernLinked)

-- ===========================================================================
-- Test 3: multi-line posts are each stripped
-- ===========================================================================
print("\nTest 3: multi-line posts are each stripped")

historyAdds = {}
delivered = {}
ok = Chat:SendPosts({ "|cff00ff00first|r line\nsecond |cffff3333wurd|r line" }, "SAY", nil, nil)

check("send succeeds", ok == true)
check("both posts delivered", #delivered == 2)
check("first post stripped", delivered[1] == "first line")
check("second post stripped", delivered[2] == "second wurd line")
check("both history entries stripped",
    #historyAdds == 2 and historyAdds[1].text == "first line" and historyAdds[2].text == "second wurd line")

-- ===========================================================================
-- Test 4: plain text passes through untouched
-- ===========================================================================
print("\nTest 4: plain text passes through untouched")

historyAdds = {}
delivered = {}
ok = Chat:SendPosts({ "nothing to strip here" }, "SAY", nil, nil)
check("send succeeds", ok == true)
check("plain text delivered verbatim", delivered[1] == "nothing to strip here")

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
