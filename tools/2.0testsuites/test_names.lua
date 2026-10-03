#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_names.lua  --  Session player-name registry (Src/Names.lua)
-- Run from the repo root:  lua tools/2.0testsuites/test_names.lua
--
-- Covers: name normalisation (realm strip, Forever surname forms,
-- battletag discrims), secret-value refusal, the combat and
-- addon-restriction harvest gates, restriction-transition purging,
-- deferred roster sweeps, chat-sender harvesting, ring capacity/eviction,
-- and the Spellcheck:IsWordCorrect consumer integration.
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition, extra)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label .. (extra and (" -> " .. tostring(extra)) or ""))
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.GetTime = function() return 100 end
_G.time = os.time

-- Drainable timer queue: C_Timer.After callbacks run only when tests
-- explicitly drain, so deferred-sweep retries are observable.
local TIMER_QUEUE = {}
_G.C_Timer = {
    After = function(_, fn) TIMER_QUEUE[#TIMER_QUEUE + 1] = fn end,
}
local function drainTimers()
    local q = TIMER_QUEUE
    TIMER_QUEUE = {}
    for _, fn in ipairs(q) do fn() end
end

-- Controllable safety flags.
local COMBAT       = false
local RESTRICTED   = false
local FOREVER_MODE = false

_G.InCombatLockdown = function() return COMBAT end

-- Secret-value surface: SECRET_SET holds sentinel "secret" values.
local SECRET_SENTINEL = "<<secret-string>>"
local SECRET_TABLE    = {}  -- sentinel "secret table" value
_G.issecretvalue  = function(v) return v == SECRET_SENTINEL end
_G.canaccessvalue = function() return false end
_G.issecrettable  = function(t) return t == SECRET_TABLE end
_G.canaccesstable = function(t) return t ~= SECRET_TABLE end

-- Restriction API surface (12.x) + state-change enum.
_G.Enum = {
    AddOnRestrictionType  = { Chat = 1, Combat = 2, Other = 3 },
    AddOnRestrictionState = { Activating = 1, Active = 2, Inactive = 3 },
}
_G.C_RestrictedActions = {
    IsAddOnRestrictionActive = function() return RESTRICTED end,
}

-- Forever naming scheme toggle (RegionalUniqueNamesEnabled global).
_G.RegionalUniqueNamesEnabled = function() return FOREVER_MODE end

-- Roster fixtures.
local ROSTER = {
    player    = "Tester",
    groupN    = 0,
    inRaid    = false,
    party     = {},
    raid      = {},
    friends   = {},
    guild     = {},
    bnFriends = {},
}
_G.UnitName = function(unit)
    if unit == "player" then return ROSTER.player end
    local kind, idx = unit:match("^(%a+)(%d+)$")
    return ROSTER[kind] and ROSTER[kind][tonumber(idx)] or nil
end
_G.GetNumGroupMembers = function() return ROSTER.groupN end
_G.IsInRaid           = function() return ROSTER.inRaid end
_G.C_FriendList = {
    GetNumFriends        = function() return #ROSTER.friends end,
    GetFriendInfoByIndex = function(i) return ROSTER.friends[i] end,
}
-- Guild API shape: C_GuildInfo.GuildRoster is a REQUEST (returns nothing)
-- and the reads are GetNumGuildMembers/GetGuildRosterInfo globals.
local GUILD_REQUESTED = false
local IN_GUILD        = true
_G.C_GuildInfo = {
    GuildRoster = function() GUILD_REQUESTED = true end,
}
_G.GuildRoster = nil
_G.IsInGuild          = function() return IN_GUILD end
_G.GetNumGuildMembers = function() return #ROSTER.guild end
_G.GetGuildRosterInfo = function(i) return ROSTER.guild[i] end
_G.BNGetNumFriends = function() return #ROSTER.bnFriends end
_G.C_BattleNet = {
    GetFriendAccountInfo = function(i) return ROSTER.bnFriends[i] end,
}

local YapperName = "Yapper"
local YapperTable = {
    Config = { System = { DEBUG = false, VERBOSE = false } },
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

-- LockdownPolicy stand-in driving CanHarvest from the test flags.
YapperTable.LockdownPolicy = {
    IsCombatLockdown              = function() return COMBAT end,
    IsAnyAddOnRestrictionActive   = function() return RESTRICTED end,
}

-- Events mock: captures registrations so tests can dispatch by event name.
local EVENT_HANDLERS = {} -- event -> fn
YapperTable.Events = {
    Register = function(_, frame, event, fn, handlerId)
        EVENT_HANDLERS[event] = fn
    end,
}
local function fire(event, ...)
    local fn = EVENT_HANDLERS[event]
    if fn then fn(...) end
end

loadModule("Src/Names.lua")
local Names = YapperTable.Names

-- Init registers all event handlers into the mock and runs an initial
-- roster sweep (harmless: tests Clear() via reset()).
Names:Init()
check("sender event registered", EVENT_HANDLERS["CHAT_MSG_SAY"] ~= nil)
check("regen flush registered", EVENT_HANDLERS["PLAYER_REGEN_ENABLED"] ~= nil)
check("restriction event registered",
    EVENT_HANDLERS["ADDON_RESTRICTION_STATE_CHANGED"] ~= nil)

local function reset()
    Names:Clear()
    Names._pendingSweep = false
    Names._retryScheduled = false
    TIMER_QUEUE = {}
    COMBAT, RESTRICTED = false, false
end

-- ===========================================================================
print("Test 1: basic add / lookup")
-- ===========================================================================
reset()
Names:Add("Velkira")
check("lowercase lookup", Names:IsName("velkira"))
check("case-insensitive lookup", Names:IsName("VeLkIrA"))
check("unknown token not a name", not Names:IsName("somebody"))
check("non-string lookups are safe", not Names:IsName(nil) and not Names:IsName(42))

-- ===========================================================================
print("\nTest 2: retail realm-suffix stripping")
-- ===========================================================================
reset()
Names:Add("Morvayn-Silvermoon")
check("realm suffix stripped", Names:IsName("morvayn"))
check("realm itself not a name", not Names:IsName("silvermoon"))

-- ===========================================================================
print("\nTest 3: Forever Firstname-Lastname / Firstname Lastname")
-- ===========================================================================
reset()
FOREVER_MODE = true
Names:Add("Jaina-Proudmoore")
check("surname part indexed (hyphen form)", Names:IsName("proudmoore"))
check("forename part indexed (hyphen form)", Names:IsName("jaina"))
check("full surname form indexed", Names:IsName("jaina proudmoore"))
Names:Clear()
Names:Add("Baelor Swiftbrook")
check("surname part indexed (space form)", Names:IsName("swiftbrook"))
check("forename part indexed (space form)", Names:IsName("baelor"))
FOREVER_MODE = false

-- ===========================================================================
print("\nTest 4: battletag + secret ingress")
-- ===========================================================================
reset()
Names:Add("CoolDude#1234")
check("battletag discrims stripped", Names:IsName("cooldude"))
check("discriminator not a name", not Names:IsName("1234"))

Names:Add(SECRET_SENTINEL)
check("secret string refused", not Names:IsName(SECRET_SENTINEL) and #Names._order == 1)

Names:Add("|KfObfuscated|k")
check("obfuscated |K token refused", not Names:IsName("|kfobfuscated|k"))
Names:Add(nil)
Names:Add("")
check("nil/empty refused", #Names._order == 1)

-- ===========================================================================
print("\nTest 4b: junk-input bounds (memory hygiene)")
-- ===========================================================================
local before = #Names._order
Names:Add(("x"):rep(129))
check("oversized input refused", #Names._order == before)
Names:Add("12345")
check("pure digits refused", #Names._order == before)
Names:Add("!!!???")
check("pure punctuation refused", #Names._order == before)
Names:Add("###")
check("battletag-only remnant refused", #Names._order == before)
Names:Add(("a"):rep(70))
check("over-length normalised name refused", #Names._order == before)
Names:Add("O'Brien-Xorcist")
check("apostrophe name stored", Names:IsName("o'brien"))

-- ===========================================================================
print("\nTest 4c: Init is idempotent (re-registers wiped handlers)")
-- ===========================================================================
reset()
Names:Init()
check("re-init runs without error", EVENT_HANDLERS["CHAT_MSG_SAY"] ~= nil)
check("re-init sweeps roster", Names:IsName("selfname") or Names:IsName("combattester")
    or Names:IsName("rostername") or Names:IsName("tester"))

-- ===========================================================================
print("\nTest 5: combat gate -- never harvest, not even safe sources")
-- ===========================================================================
reset()
COMBAT = true
Names:Add("InCombatName")
check("Add refused during combat", not Names:IsName("incombatname"))

ROSTER.player = "CombatTester"
Names:SweepRoster()
check("sweep deferred during combat", Names._pendingSweep == true)
check("sweep stored nothing", not Names:IsName("combattester"))

fire("CHAT_MSG_SAY", "hello", "ChatName")
check("chat sender dropped during combat", not Names:IsName("chatname"))

COMBAT = false
fire("PLAYER_REGEN_ENABLED")
check("regen flushes deferred sweep", Names:IsName("combattester"))
check("pending flag cleared", Names._pendingSweep == false)

-- ===========================================================================
print("\nTest 5b: deferred-sweep retry chain (reload under restriction)")
-- ===========================================================================
-- Simulates a /reload while ANY restriction is active: every harvest
-- path defers, and retries persist until NO gate is active -- even with
-- no event firing to mark the lift.
reset()
ROSTER.player = "RetryTester"
RESTRICTED = true

-- Every harvest path defers under restriction.
fire("CHAT_MSG_SAY", "hi", "SayName")
Names:SweepRoster()
check("pending sweep under restriction", Names._pendingSweep == true)
check("nothing stored while restricted", not Names:IsName("retrytester")
    and not Names:IsName("sayname"))

-- Draining the retry while still restricted re-defers, not drops.
drainTimers()
check("still pending while restricted", Names._pendingSweep == true)
check("retry re-queued", #TIMER_QUEUE > 0)

-- Lift the restriction with NO event dispatch (loading screens swallow
-- Inactive): the retry chain itself recovers.
RESTRICTED = false
drainTimers()
check("retry chain recovers without events", Names:IsName("retrytester"))
check("pending cleared after recovery", Names._pendingSweep == false)

-- A dropped Add during combat also queues the catch-up sweep.
reset()
COMBAT = true
Names:Add("DroppedDuringFight")
check("dropped Add queues catch-up sweep", Names._pendingSweep == true)
COMBAT = false
drainTimers()
check("catch-up sweep harvested roster", Names:IsName("retrytester"))

-- ===========================================================================
print("\nTest 6: restriction gate + state-change purge")
-- ===========================================================================
reset()
RESTRICTED = true
Names:Add("RestrictedName")
check("Add refused while restricted", not Names:IsName("restrictedname"))
check("sweep deferred while restricted", (function()
    Names:SweepRoster(); return Names._pendingSweep == true end)())
RESTRICTED = false
Names._pendingSweep = false

Names:Add("PurgedName")
check("pre-purge name present", Names:IsName("purgedname"))
ROSTER.player = "RosterName"
fire("ADDON_RESTRICTION_STATE_CHANGED",
    Enum.AddOnRestrictionType.Other, Enum.AddOnRestrictionState.Activating)
check("Activating purges buffer", not Names:IsName("purgedname") and #Names._order == 0)

fire("ADDON_RESTRICTION_STATE_CHANGED",
    Enum.AddOnRestrictionType.Other, Enum.AddOnRestrictionState.Active)
check("Active also purges", #Names._order == 0)

fire("ADDON_RESTRICTION_STATE_CHANGED",
    Enum.AddOnRestrictionType.Other, Enum.AddOnRestrictionState.Inactive)
check("Inactive re-sweeps roster", Names:IsName("rostername"))

-- ===========================================================================
print("\nTest 7: harvest sources")
-- ===========================================================================
reset()
ROSTER.player  = "Selfname"
ROSTER.groupN  = 3
ROSTER.inRaid  = false
ROSTER.party   = { "Partyone", "Partytwo" }
ROSTER.friends = { { name = "Friendone" }, { name = "Friendtwo" } }
ROSTER.guild   = { "Guildone", "Guildtwo" }
ROSTER.bnFriends = {
    { accountName = "BnetFriend", battleTag = "Tag#9999",
      gameAccountInfo = { characterName = "BnetChar" } },
}
Names:SweepRoster()
check("player harvested", Names:IsName("selfname"))
check("party members harvested", Names:IsName("partyone") and Names:IsName("partytwo"))
check("friends harvested", Names:IsName("friendone") and Names:IsName("friendtwo"))
check("guild roster harvested", Names:IsName("guildone") and Names:IsName("guildtwo"))
check("bnet account harvested", Names:IsName("bnetfriend"))
check("bnet tag harvested", Names:IsName("tag"))
check("bnet game character harvested", Names:IsName("bnetchar"))

-- Secret roster values must not be stored.
ROSTER.friends[1].name = SECRET_SENTINEL
Names:Clear()
Names:SweepRoster()
check("secret friend name skipped", not Names:IsName(SECRET_SENTINEL)
    and Names:IsName("friendtwo"))
ROSTER.friends[1].name = "Friendone"

-- A whole roster row can arrive inaccessible (Communities-backed data
-- under restrictions): it must be skipped, not error.
ROSTER.friends[1] = SECRET_TABLE
Names:Clear()
local ok = pcall(Names.SweepRoster, Names)
check("secret friend row skipped without error", ok
    and Names:IsName("friendtwo"))
ROSTER.friends[1] = { name = "Friendone" }

-- Individual guild names can arrive secret while the roster is readable.
ROSTER.guild = { SECRET_SENTINEL, "Guildtwo" }
Names:Clear()
Names:SweepRoster()
check("secret guild name skipped", not Names:IsName(SECRET_SENTINEL)
    and Names:IsName("guildtwo"))
ROSTER.guild = { "Guildone", "Guildtwo" }

-- Cold guild cache: in a guild but the roster read returns zero ->
-- the module REQUESTS a refresh (GuildRoster is a request, not a read)
-- and GUILD_ROSTER_UPDATE re-sweeps when data lands.
local realGuild = ROSTER.guild
GUILD_REQUESTED = false
Names:Clear()
Names:SweepRoster()
check("warm guild cache does not request", not GUILD_REQUESTED)
ROSTER.guild = {}
Names:SweepRoster()
check("cold guild cache requests refresh", GUILD_REQUESTED)
ROSTER.guild = realGuild
fire("GUILD_ROSTER_UPDATE", true)
check("guild roster update re-sweeps", Names:IsName("guildone"))

-- Chat senders outside combat.
fire("CHAT_MSG_WHISPER", "psst", "WhisperName")
check("whisper sender harvested", Names:IsName("whispername"))
fire("CHAT_MSG_GUILD", "hi", "GuildChatter")
check("guild chatter harvested", Names:IsName("guildchatter"))

-- Raid branch.
reset()
ROSTER.inRaid = true
ROSTER.groupN = 2
ROSTER.raid   = { "Raiderone", "Raidertwo" }
Names:SweepRoster()
check("raid members harvested", Names:IsName("raiderone") and Names:IsName("raidertwo"))

-- ===========================================================================
print("\nTest 8: ring capacity + eviction")
-- ===========================================================================
reset()
for i = 1, 520 do
    Names:Add("CapName" .. i)
end
check("order bounded at 512", #Names._order == 512, #Names._order)
check("oldest evicted", not Names:IsName("capname1") and not Names:IsName("capname8"))
check("newest retained", Names:IsName("capname520") and Names:IsName("capname10"))

-- Re-adding an existing name must not duplicate or evict.
local before = #Names._order
Names:Add("CapName260")
check("re-add is a no-op", #Names._order == before)

-- ===========================================================================
print("\nTest 9: FindByPrefix (autocomplete tier)")
-- ===========================================================================
reset()
Names:Add("Velkira")
Names:Add("Veldara")
check("prefix finds a stored name", Names:FindByPrefix("vel") == "velkira")
check("shorter prefix still matches", Names:FindByPrefix("v") == "velkira")
check("non-matching prefix nil", Names:FindByPrefix("xyz") == nil)
check("exact-length prefix does not self-match", Names:FindByPrefix("velkira") == nil)

-- ===========================================================================
print("\nTest 10: IsWordCorrect consumer (names = correct)")
-- ===========================================================================
-- Load the real spellcheck hub + engine and exercise the real
-- IsWordCorrect: a registered name must pass even when the dictionary
-- does not contain it.
loadModule("Src/Spellcheck.lua")
loadModule("Src/Spellcheck/Engine.lua")
local Spellcheck = YapperTable.Spellcheck
Spellcheck.GetDictionary   = function() return { set = {} } end
Spellcheck.GetLocale       = function() return "tloc" end
Spellcheck.GetActiveEngine = function() return nil end
Spellcheck.GetUserSets     = function() return nil, nil end
Spellcheck.IsWordBlocked   = function() return false end

reset()
check("unknown word incorrect", Spellcheck:IsWordCorrect("velkira") == false)
Names:Add("Velkira")
check("known name correct", Spellcheck:IsWordCorrect("Velkira") == true)

FOREVER_MODE = true
Names:Add("Baelor-Swiftbrook")
check("forever surname part correct", Spellcheck:IsWordCorrect("Swiftbrook") == true)
FOREVER_MODE = false

-- ===========================================================================
print(("\n%d tests, %d failures"):format(TESTS, FAILURES))
os.exit(FAILURES == 0 and 0 or 1)
