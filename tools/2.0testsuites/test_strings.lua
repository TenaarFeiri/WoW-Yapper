#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_strings.lua  —  UI string registry/resolver tests
-- Run from the repo root:  lua tools/2.0testsuites/test_strings.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        io.write("  [" .. PASS .. "] " .. label .. "\n")
    else
        FAILURES = FAILURES + 1
        io.write("  [" .. FAIL .. "] " .. label .. "\n")
    end
end

local YapperTable = {}
local fired = {}
YapperTable.API = {
    Fire = function(_, event, ...) fired[#fired + 1] = { event = event, args = { ... } } end,
}

local function LoadFile(path)
    local f = assert(loadfile(path))
    f("Yapper", YapperTable)
end

LoadFile("../../Src/Strings.lua")
local Strings = YapperTable.Strings

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------
check("enUS resolves canonical text",
    Strings:Get("ui.spellcheck.more", 7) == "7. More Suggestions »")
check("format args apply",
    Strings:Get("ui.spellcheck.add", 1, "foo") == '1. Add "foo" to dictionary')
check("unknown key resolves to the key itself",
    Strings:Get("ui.nope.missing") == "ui.nope.missing")
check("nil key degrades to 'nil' string", Strings:Get(nil) == "nil")

-- ---------------------------------------------------------------------------
-- Locale fallback + registration
-- ---------------------------------------------------------------------------
Strings._forceLocale = "deDE"
check("unregistered locale falls back to enUS",
    Strings:Get("ui.emotes.hint") == "Tab: browse emotes")

local ok, err = Strings:Register("deDE", { ["ui.emotes.hint"] = "Tab: Emotes durchsuchen" }, "DictDE")
check("valid deDE registration accepted", ok == true)
check("registered locale overrides enUS",
    Strings:Get("ui.emotes.hint") == "Tab: Emotes durchsuchen")
check("untranslated key still falls back to enUS",
    Strings:Get("ui.spellcheck.more", 2) == "2. More Suggestions »")
check("STRINGS_UPDATED fired with the locale",
    #fired == 1 and fired[1].event == "STRINGS_UPDATED" and fired[1].args[1] == "deDE")

-- Other locales remain untouched.
Strings._forceLocale = "frFR"
check("other locale unaffected by deDE registration",
    Strings:Get("ui.emotes.hint") == "Tab: browse emotes")
Strings._forceLocale = "deDE"

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------
local bad = Strings:Register("deDE", { ["ui.invented.key"] = "x" }, "DictDE")
check("invented keys rejected", bad == false)
check("rejected registration changed nothing",
    Strings:Get("ui.emotes.hint") == "Tab: Emotes durchsuchen"
    and fired[#fired].args[1] == "deDE")

check("non-table rejected", Strings:Register("deDE", "nope") == false)
check("empty locale rejected", Strings:Register("", {}) == false)
check("enUS override rejected", Strings:Register("enUS", { ["ui.emotes.hint"] = "x" }) == false)
check("non-string value rejected",
    Strings:Register("deDE", { ["ui.emotes.hint"] = 42 }, "DictDE") == false)

local longVal = string.rep("x", 600)
check("over-length value rejected",
    Strings:Register("deDE", { ["ui.emotes.hint"] = longVal }, "DictDE") == false)

-- ---------------------------------------------------------------------------
-- Owner semantics: wholesale replace + deterministic collision order
-- ---------------------------------------------------------------------------
Strings:Register("deDE", { ["ui.spellcheck.row"] = "%d. %s" }, "DictA")
Strings:Register("deDE", { ["ui.spellcheck.row"] = "%d/%s" }, "DictB")
check("later owner wins a collision deterministically",
    Strings:Get("ui.spellcheck.row", 1, "x") == "1/x")

-- DictA re-registers; its old keys must be dropped wholesale.
Strings:Register("deDE", { ["ui.emotes.hint"] = "Tab-Neustart" }, "DictA")
check("re-registration replaces owner contribution",
    Strings:Get("ui.emotes.hint") == "Tab-Neustart")

-- Malformed format string degrades to raw text instead of erroring.
Strings:Register("deDE", { ["ui.spellcheck.more"] = "%q broken %d" }, "DictC")
local got = Strings:Get("ui.spellcheck.more", 3)
check("bad format falls back to raw text", type(got) == "string" and #got > 0)

Strings._forceLocale = nil

-- ---------------------------------------------------------------------------
print(("\n%d check(s), %d failure(s)"):format(TESTS, FAILURES))
if FAILURES > 0 then os.exit(1) end
print("Strings tests finished")
