#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_api_features.lua  —  Yapper API feature test suite
-- Run from the repo root:  lua tools/test_api_features.lua
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

-- Bootstrap: mock WoW environment and load API.lua
local debugLines = {}
_G.C_Timer = {
    NewTimer = function(duration, callback)
        return {
            duration = duration,
            callback = callback,
            Cancel = function(self) self.cancelled = true end
        }
    end
}

local YapperTable = {}
YapperTable.Utils = {
    DebugPrint = function(_, msg)
        debugLines[#debugLines+1] = msg
    end,
}

local api_loader, lerr = loadfile("Src/API.lua")
if not api_loader then
    print("FATAL: failed to load Src/API.lua: " .. tostring(lerr))
    os.exit(1)
end
api_loader("Yapper", YapperTable)

local YapperAPI = _G.YapperAPI
assert(type(YapperAPI) == "table", "YapperAPI not created")
assert(type(YapperTable.API) == "table", "YapperTable.API not created")

local tmpFiles = {}

local function load_as(code, fake_path)
    local dir = fake_path:match("(.+)/")
    if dir then os.execute("mkdir -p '/tmp/_yappertest/" .. dir .. "'") end
    local full = "/tmp/_yappertest/" .. fake_path
    local f = assert(io.open(full, "w"))
    f:write(code)
    f:close()
    tmpFiles[#tmpFiles+1] = full
    local fn, err = loadfile(full)
    if not fn then error("loadfile " .. full .. ": " .. tostring(err)) end
    return fn()
end

local function cleanup()
    for i = #tmpFiles, 1, -1 do os.remove(tmpFiles[i]) end
    os.execute("rm -rf /tmp/_yappertest 2>/dev/null")
end

-- ================= TESTS =================

-- Test 1: Spellcheck Accessors (mocked)
print("Test 1: Spellcheck Accessors")

YapperTable.Spellcheck = {
    IsEnabled = function() return true end,
    IsWordCorrect = function(_, word) return word == "hello" end,
    GetSuggestions = function(_, word) 
        if word == "teh" then return {{word="the"}, {word="ten"}} end
        return {}
    end,
    GetLocale = function() return "enUS" end,
    AddUserWord = function(self, locale, word)
        self.added = {locale, word}
        YapperTable.API:Fire("SPELLCHECK_WORD_ADDED", word, locale)
    end,
    IgnoreWord = function(self, locale, word)
        self.ignored = {locale, word}
        YapperTable.API:Fire("SPELLCHECK_WORD_IGNORED", word, locale)
    end
}

check("IsSpellcheckEnabled returns true", YapperAPI:IsSpellcheckEnabled() == true)
check("CheckWord('hello') returns true", YapperAPI:CheckWord("hello") == true)
check("CheckWord('worrrrrld') returns false", YapperAPI:CheckWord("worrrrrld") == false)

check("GetSpellcheckLocale returns locale", YapperAPI:GetSpellcheckLocale() == "enUS")
local suggs = YapperAPI:GetSuggestions("teh")
check("GetSuggestions returns table", type(suggs) == "table")
check("GetSuggestions unwraps tables correctly", suggs and suggs[1] == "the" and suggs[2] == "ten")

local evts = {}
YapperAPI:RegisterCallback("SPELLCHECK_WORD_ADDED", function(word, locale)
    evts.added = {word, locale}
end)

check("AddToDictionary returns true", YapperAPI:AddToDictionary("worrrrrld") == true)
check("AddToDictionary triggers mock method", YapperTable.Spellcheck.added and YapperTable.Spellcheck.added[2] == "worrrrrld")
check("AddToDictionary fires event", evts.added and evts.added[1] == "worrrrrld")

-- Test 2: Post delegation system
print("\nTest 2: Post Delegation System")
local postClaimed = nil
YapperAPI:RegisterCallback("POST_CLAIMED", function(handle, text, chatType, language, target)
    postClaimed = {handle=handle, text=text, chatType=chatType, language=language, target=target}
end)

local function simulate_direct_send(msg, chatType, language, target)
    local payload = YapperTable.API:RunFilter("PRE_DELIVER", {
        text = msg, chatType = chatType, language = language, target = target
    })
    
    if payload == false then
        local owner = YapperTable.API._lastCancelOwner
        local handle = YapperTable.API:_createClaim(msg, chatType, language, target, owner)
        YapperTable.API:Fire("POST_CLAIMED", handle, msg, chatType, language, target)
        return
    end
    msg = payload.text
    if YapperTable.Router then
        YapperTable.Router:Send(msg, payload.chatType, payload.language, payload.target)
    end
end

local sentByYapper = nil
YapperTable.Router = {
    Send = function(self, text) sentByYapper = text end
}

-- 2a: Unclaimed message
postClaimed = nil
simulate_direct_send("DONT CLAIM", "SAY", "", "")
check("Unclaimed message does not fire POST_CLAIMED", postClaimed == nil)
check("Unclaimed message is sent by Router", sentByYapper == "DONT CLAIM")

-- 2b: Claimed message
sentByYapper = nil
load_as([[
    YapperAPI:RegisterFilter("PRE_DELIVER", function(payload)
        if payload.text == "CLAIM ME" then return false end
        return payload
    end)
]], "AddOns/MockAddon/filter.lua")

simulate_direct_send("CLAIM ME", "SAY", "", "")

check("Claimed message is NOT sent by Router", sentByYapper == nil)
check("Claimed message fires POST_CLAIMED", postClaimed ~= nil and postClaimed.text == "CLAIM ME")
local activeHandle = postClaimed and postClaimed.handle
check("Handle is a number", type(activeHandle) == "number")

-- 2c: Resolve the post
local resolved = YapperAPI:ResolvePost(activeHandle)
check("ResolvePost succeeds with valid handle", resolved == true)

local resolveAgain = YapperAPI:ResolvePost(activeHandle)
check("ResolvePost fails when called again", resolveAgain == false)

cleanup()

print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
