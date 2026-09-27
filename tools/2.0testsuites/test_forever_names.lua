#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_forever_names.lua  --  WoW: Forever regional-unique-names regression
-- tests: client/capability detection, Blizzard-parity whisper target
-- extraction, and surname-aware name normalisation.
-- Run from the repo root:  lua tools/2.0testsuites/test_forever_names.lua
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

_G.strlower = string.lower
_G.strmatch = string.match
_G.strfind  = string.find
_G.strsub   = string.sub
_G.strlen   = string.len

-- Autocomplete state driven per-test: names in this set "belong" to real
-- characters (mirrors C_AutoComplete.GetAutoCompleteResults).
local knownNames = {}
_G.AUTOCOMPLETE_LIST = {
    WHISPER_EXTRACT = { include = {}, exclude = {} },
    SMART_WHISPER_EXTRACT = { include = {}, exclude = {} },
}
_G.C_AutoComplete = {
    GetAutoCompleteResults = function(candidate)
        -- WoW's autocomplete is prefix-strict: "Name " (trailing space) does
        -- not match "Name". Do not trim here — that distinction is load-
        -- bearing for Blizzard's ExtractTellTarget semantics.
        local out = {}
        if candidate and knownNames[candidate:lower()] then
            out[#out + 1] = candidate
        end
        return out
    end,
}

-- Feature toggles flipped per-test.
local regionalEnabled = false
_G.RegionalUniqueNamesEnabled = function() return regionalEnabled end
_G.GetBuildInfo = function() return "11.0.5.0" end

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
loadModule("Src/EditBox.lua")

local Utils   = YapperTable.Utils
local EditBox = YapperTable.EditBox

local function setRegional(v)
    regionalEnabled = v
end

local function setKnownNames(...)
    knownNames = {}
    for _, n in ipairs({ ... }) do
        knownNames[n:lower()] = true
    end
end

-- ===========================================================================
-- Test 1: IsForeverClient — capability and label probes
-- ===========================================================================
print("Test 1: IsForeverClient detection")

local function resetDetect()
    Utils._isForeverClient = nil
end

resetDetect()
check("no Forever APIs and retail build -> false", Utils:IsForeverClient() == false)

_G.C_GameRules = { GetForeverExperiencePreset = function() return 1 end }
resetDetect()
check("ForeverExperiencePreset API -> true", Utils:IsForeverClient() == true)
_G.C_GameRules = nil

_G.Enum = { ForeverExperiencePreset = { Classic = 0, Modern = 1 } }
resetDetect()
check("Enum.ForeverExperiencePreset -> true", Utils:IsForeverClient() == true)
_G.Enum = nil

_G.C_NameUtil = { ReplaceSurnameSeparatorWithLinkSeparator = function(s) return s end }
resetDetect()
check("C_NameUtil surname API -> true", Utils:IsForeverClient() == true)
_G.C_NameUtil = nil

_G.C_CharacterCreation = { AreRegionalUniqueNamesEnabled = function() return true end }
resetDetect()
check("AreRegionalUniqueNamesEnabled -> true", Utils:IsForeverClient() == true)
_G.C_CharacterCreation = nil

_G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
resetDetect()
check("ShouldDisplaySurname -> true", Utils:IsForeverClient() == true)
_G.C_PlayerInfo = nil

_G.C_GameRules = { GetGameModeGlueScreenName = function() return "Camelot" end }
resetDetect()
check("glue screen label 'Camelot' -> true", Utils:IsForeverClient() == true)
_G.C_GameRules.GetGameModeGlueScreenName = function() return "Forever" end
resetDetect()
check("glue screen label 'Forever' -> true", Utils:IsForeverClient() == true)
_G.C_GameRules.GetGameModeGlueScreenName = function() return "Classic+" end
resetDetect()
check("glue screen label 'Classic+' -> true", Utils:IsForeverClient() == true)
_G.C_GameRules.GetGameModeGlueScreenName = function() return "classicplus" end
resetDetect()
check("glue screen label 'classicplus' -> true", Utils:IsForeverClient() == true)
_G.C_GameRules.GetGameModeGlueScreenName = function() return "Mainline" end
resetDetect()
check("glue screen label 'Mainline' -> false", Utils:IsForeverClient() == false)
_G.C_GameRules = nil

_G.GetBuildInfo = function() return "1.60.1.70009" end
resetDetect()
check("build 1.60.x -> true", Utils:IsForeverClient() == true)
_G.GetBuildInfo = function() return "12.0.0.12345" end
resetDetect()
check("build 12.x -> false", Utils:IsForeverClient() == false)

-- ===========================================================================
-- Test 2: HasRegionalUniqueNames — the feature gate
-- ===========================================================================
print("\nTest 2: HasRegionalUniqueNames gate")

setRegional(false)
check("RegionalUniqueNamesEnabled()=false -> false", Utils:HasRegionalUniqueNames() == false)
setRegional(true)
check("RegionalUniqueNamesEnabled()=true -> true", Utils:HasRegionalUniqueNames() == true)

local savedFn = _G.RegionalUniqueNamesEnabled
_G.RegionalUniqueNamesEnabled = nil
check("API absent -> false", Utils:HasRegionalUniqueNames() == false)
_G.RegionalUniqueNamesEnabled = savedFn

-- ===========================================================================
-- Test 3: NormaliseCharName on both clients
-- ===========================================================================
print("\nTest 3: NormaliseCharName")

setRegional(false)
check("retail strips realm", Utils:NormaliseCharName("Arthas-Frostmourne") == "arthas")
check("retail bare name", Utils:NormaliseCharName("Arthas") == "arthas")

setRegional(true)
check("forever keeps surname (space)", Utils:NormaliseCharName("Charname Surname") == "charname surname")
check("forever keeps surname (dash)", Utils:NormaliseCharName("Charname-Surname") == "charname surname")
check("forever spellings compare equal",
    Utils:NormaliseCharName("Charname Surname") == Utils:NormaliseCharName("Charname-Surname"))
check("forever distinct surnames differ",
    Utils:NormaliseCharName("Charname Alpha") ~= Utils:NormaliseCharName("Charname Beta"))

setRegional(false)

-- ===========================================================================
-- Test 4: Retail whisper-slash parsing is unchanged
-- ===========================================================================
print("\nTest 4: ParseWhisperSlash (retail)")

setRegional(false)
local tgt, rem = EditBox.ParseWhisperSlash("/w Alice hello there")
check("retail target", tgt == "Alice")
check("retail remainder", rem == "hello there")
tgt, rem = EditBox.ParseWhisperSlash("/w Alice-Realm ")
check("retail realm-form target", tgt == "Alice-Realm")
check("retail empty remainder", rem == "")

-- ===========================================================================
-- Test 5: Regional whisper-slash parsing (Blizzard ExtractTellTarget parity)
-- ===========================================================================
print("\nTest 5: ParseWhisperSlash (forever)")

setRegional(true)

-- Prefill path: "/w Charname Surname " — trailing space supplied by Blizzard.
setKnownNames("Charname Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname ")
check("forever prefill target is full name", tgt == "Charname Surname")
check("forever prefill has no surname bleed", rem == "")

-- Typed with a following message; autocomplete knows the character.
setKnownNames("Charname Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname hello world")
check("typed whisper target", tgt == "Charname Surname")
check("typed whisper remainder", rem == "hello world")

-- Hyphenated form.
setKnownNames("Charname-Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname-Surname hello")
check("hyphen-form target", tgt == "Charname-Surname")
check("hyphen-form remainder", rem == "hello")

-- Unknown to autocomplete: min-two-words refinement still splits correctly.
setKnownNames()
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname hello")
check("no-AC fallback target is two words", tgt == "Charname Surname")
check("no-AC fallback remainder", rem == "hello")

-- Incomplete surname: no interior boundary -> nil (caller keeps waiting).
setKnownNames("Charname Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Sur")
check("incomplete surname unresolved", tgt == nil)
tgt, rem = EditBox.ParseWhisperSlash("/w Charname ")
check("bare first name + space unresolved", tgt == nil)

-- Whole rest is a known name -> still typing (Blizzard returns false).
setKnownNames("Charname Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname")
check("whole-known-name unresolved mid-typing", tgt == nil)

-- Once the surname boundary is closed, a following word is message text
-- immediately (Blizzard resolves the target as soon as the name is closed).
setKnownNames("Charname Surname")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname hel")
check("surname + partial message resolves", tgt == "Charname Surname")
check("surname + partial message remainder", rem == "hel")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname hel ")
check("surname + finished word resolves", tgt == "Charname Surname")
check("surname + finished word remainder", rem == "hel")

-- A longer name beats a shorter known prefix only when it is itself known:
-- "Charname Surname Extra" stays unresolved while the full rest matches AC.
setKnownNames("Charname Surname", "Charname Surname Extra")
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname Extra")
check("longer known name keeps waiting", tgt == nil)
tgt, rem = EditBox.ParseWhisperSlash("/w Charname Surname Extra hi")
check("longer known name resolves longest", tgt == "Charname Surname Extra")
check("longer known name remainder", rem == "hi")

setRegional(false)

print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
