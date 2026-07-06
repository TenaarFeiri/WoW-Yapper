#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_router.lua  --  Router module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_router.lua
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
_G.GetTime = function() return 100 end  -- fixed time for cache tests

-- Track sends for inspection.
local sentMessages = {}

_G.C_ChatInfo = {
    SendChatMessage = function(msg, chatType, language, target)
        sentMessages[#sentMessages + 1] = {
            msg = msg, chatType = chatType, language = language, target = target,
            api = "SendChatMessage",
        }
    end,
}

_G.BNSendWhisper = function(presenceID, msg)
    sentMessages[#sentMessages + 1] = {
        msg = msg, presenceID = presenceID, api = "BNSendWhisper",
    }
end

_G.C_BattleNet = {
    GetFriendAccountInfo = function(index)
        local friends = {
            [1] = {
                accountName = "FriendOne",
                battleTag = "FriendOne#1234",
                bnetAccountID = 1001,
                gameAccountInfo = { characterName = "Thrall" },
            },
            [2] = {
                accountName = "FriendTwo",
                battleTag = "FriendTwo#5678",
                bnetAccountID = 1002,
                gameAccountInfo = { characterName = "Jaina" },
            },
        }
        return friends[index]
    end,
    SendWhisper = function(bnetAccountID, msg)
        sentMessages[#sentMessages + 1] = {
            msg = msg, bnetAccountID = bnetAccountID, api = "C_BattleNet.SendWhisper",
        }
    end,
}

_G.BNGetNumFriends = function() return 2 end
_G.BNGetFriendInfo = nil  -- Use only the modern API

_G.C_Club = {
    SendMessage = function(clubId, streamId, msg)
        sentMessages[#sentMessages + 1] = {
            msg = msg, clubId = clubId, streamId = streamId, api = "ClubSendMessage",
        }
    end,
}

_G.GetChannelName = function(target)
    if target == "Community:42:7" then
        return 5, "Community:42:7"
    end
    return 3, "General"
end

local YapperName = "Yapper"
local YapperTable = {
    Config = {},
    Utils = {
        DebugPrint = function() end,
        Print = function() end,
    },
    Core = {
        GetCharacterLanguage = function(self, lang) return lang end,
    },
    Events = {
        Register = function() end,
    },
}

-- Load Router.lua.
local loader, err = loadfile("Src/Router.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)

local Router = YapperTable.Router
Router:Init()

local function ResetSends()
    sentMessages = {}
end

-- ===========================================================================
-- Test 1: Standard SAY send
-- ===========================================================================
print("\nTest 1: Standard SAY send")

ResetSends()
local ok = Router:Send("Hello!", "SAY", "Common", nil)
check("SAY returns true", ok == true)
check("one message sent", #sentMessages == 1)
check("uses SendChatMessage", sentMessages[1].api == "SendChatMessage")
check("msg content correct", sentMessages[1].msg == "Hello!")
check("chatType correct", sentMessages[1].chatType == "SAY")

-- ===========================================================================
-- Test 2: WHISPER send
-- ===========================================================================
print("\nTest 2: WHISPER send")

ResetSends()
ok = Router:Send("Hey there", "WHISPER", "Common", "PlayerName")
check("WHISPER returns true", ok == true)
check("target passed", sentMessages[1].target == "PlayerName")

-- ===========================================================================
-- Test 3: WHISPER with empty target
-- ===========================================================================
print("\nTest 3: WHISPER with empty target")

ResetSends()
ok = Router:Send("Hey", "WHISPER", "Common", "")
check("empty target returns false", ok == false)
check("no message sent", #sentMessages == 0)

ResetSends()
ok = Router:Send("Hey", "WHISPER", "Common", nil)
check("nil target returns false", ok == false)

-- ===========================================================================
-- Test 4: Empty message
-- ===========================================================================
print("\nTest 4: Empty / nil message")

ResetSends()
ok = Router:Send("", "SAY", nil, nil)
check("empty message returns false", ok == false)
check("no message sent for empty", #sentMessages == 0)

ResetSends()
ok = Router:Send(nil, "SAY", nil, nil)
check("nil message returns false", ok == false)

-- ===========================================================================
-- Test 5: BN_WHISPER via BNet resolution
-- ===========================================================================
print("\nTest 5: BN_WHISPER via BNet resolution")

ResetSends()
Router:FlushBnetCache()
ok = Router:Send("BNet hello", "BN_WHISPER", nil, "FriendOne")
check("BN_WHISPER returns true", ok == true)
check("uses C_BattleNet.SendWhisper", sentMessages[1].api == "C_BattleNet.SendWhisper")
check("bnetAccountID resolved", sentMessages[1].bnetAccountID == 1001)

-- ===========================================================================
-- Test 6: BN_WHISPER by character name
-- ===========================================================================
print("\nTest 6: BN_WHISPER by character name")

ResetSends()
Router:FlushBnetCache()
ok = Router:Send("Hey Jaina", "BN_WHISPER", nil, "Jaina")
check("character name resolves", ok == true)
check("correct bnetAccountID for Jaina", sentMessages[1].bnetAccountID == 1002)

-- ===========================================================================
-- Test 7: BN_WHISPER by battleTag (without discriminator)
-- ===========================================================================
print("\nTest 7: BN_WHISPER by battleTag base")

ResetSends()
Router:FlushBnetCache()
ok = Router:Send("Hey friend", "BN_WHISPER", nil, "FriendTwo")
check("battleTag base resolves", ok == true)
check("correct bnetAccountID", sentMessages[1].bnetAccountID == 1002)

-- ===========================================================================
-- Test 8: BN_WHISPER with numeric presenceID
-- ===========================================================================
print("\nTest 8: BN_WHISPER with numeric presenceID")

ResetSends()
Router:FlushBnetCache()

-- When target is numeric and no BNet resolution finds it, it falls through
-- to the legacy BNSendWhisper path.
_G.BNGetFriendInfo = function(i)
    if i == 1 then return 500, "LegacyFriend", "Legacy#1111", nil, "ToonName", nil, nil, nil, nil, nil, nil, nil, nil, 2000 end
    return nil
end
_G.BNGetNumFriends = function() return 1 end

ok = Router:Send("Legacy msg", "BN_WHISPER", nil, "500")
check("numeric presenceID send ok", ok == true)

-- Restore.
_G.BNGetFriendInfo = nil
_G.BNGetNumFriends = function() return 2 end

-- ===========================================================================
-- Test 9: BNet cache (TTL)
-- ===========================================================================
print("\nTest 9: BNet cache")

Router:FlushBnetCache()
local currentTime = 100
_G.GetTime = function() return currentTime end

-- First resolve populates cache.
local pID1, bID1 = Router:ResolveBnetTarget("FriendOne")
check("first resolve finds target", bID1 == 1001)

-- Second resolve uses cache (even if we remove the underlying data).
local origGetFriendInfo = _G.C_BattleNet.GetFriendAccountInfo
_G.C_BattleNet.GetFriendAccountInfo = function() return nil end

local pID2, bID2 = Router:ResolveBnetTarget("FriendOne")
check("cached resolve works", bID2 == 1001)

-- Advance past TTL.
currentTime = 200
local pID3, bID3 = Router:ResolveBnetTarget("FriendOne")
check("cache expired, re-resolves (nil when data gone)", bID3 == nil)

-- Restore.
_G.C_BattleNet.GetFriendAccountInfo = origGetFriendInfo
_G.GetTime = function() return 100 end

-- ===========================================================================
-- Test 10: FlushBnetCache
-- ===========================================================================
print("\nTest 10: FlushBnetCache")

Router:FlushBnetCache()
-- After flush, a previously cached entry should re-resolve.
local _, bIDFlush = Router:ResolveBnetTarget("FriendOne")
check("cache flushed and re-resolved", bIDFlush == 1001)

-- ===========================================================================
-- Test 11: Community channel detection
-- ===========================================================================
print("\nTest 11: Community channel detection")

local isClub, clubId, streamId = Router:DetectCommunityChannel("Community:42:7")
check("community detected", isClub == true)
check("clubId parsed", clubId == "42")
check("streamId parsed", streamId == "7")

local isClub2 = Router:DetectCommunityChannel("General")
check("non-community returns false", isClub2 == false)

local isClub3 = Router:DetectCommunityChannel(nil)
check("nil target returns false", isClub3 == false)

-- ===========================================================================
-- Test 12: CHANNEL send to community
-- ===========================================================================
print("\nTest 12: CHANNEL send to community")

ResetSends()
ok = Router:Send("Community message", "CHANNEL", nil, "Community:42:7")
check("community CHANNEL returns true", ok == true)
check("uses ClubSendMessage", sentMessages[1].api == "ClubSendMessage")

-- ===========================================================================
-- Test 13: CLUB send
-- ===========================================================================
print("\nTest 13: CLUB send")

ResetSends()
-- For CLUB, language=clubId, target=streamId.
ok = Router:Send("Club message", "CLUB", "42", "7")
check("CLUB returns true", ok == true)
check("uses ClubSendMessage for CLUB", sentMessages[1].api == "ClubSendMessage")

-- ===========================================================================
-- Test 14: Default chatType
-- ===========================================================================
print("\nTest 14: Default chatType")

ResetSends()
ok = Router:Send("Default type", nil, nil, nil)
check("nil chatType defaults to SAY", sentMessages[1].chatType == "SAY")

-- ===========================================================================
-- Test 15: ResolveBnetDisplay
-- ===========================================================================
print("\nTest 15: ResolveBnetDisplay")

Router:FlushBnetCache()
local display = Router:ResolveBnetDisplay("FriendOne")
check("display name resolved", display == "FriendOne")

local display2 = Router:ResolveBnetDisplay("Jaina")
check("display by character name", display2 == "FriendTwo")

local display3 = Router:ResolveBnetDisplay(nil)
check("nil target returns nil", display3 == nil)

local display4 = Router:ResolveBnetDisplay("")
check("empty target returns nil", display4 == nil)

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
