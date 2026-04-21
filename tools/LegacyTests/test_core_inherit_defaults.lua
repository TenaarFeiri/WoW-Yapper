#!/usr/bin/env lua
-- Regression test for Core.InheritDefaults self-loop bug in profile flows.

_G = _G or {}

if type(wipe) ~= "function" then
    function wipe(tbl)
        for k in pairs(tbl) do
            tbl[k] = nil
        end
        return tbl
    end
end

local function assert_ok(label, cond)
    if not cond then
        error("FAIL: " .. label, 2)
    end
    print("PASS: " .. label)
end

local function assert_no_dict_self_loop(globalDB, label)
    local dict = globalDB.Spellcheck.Dict
    assert_ok(label .. " (dict exists)", type(dict) == "table")
    assert_ok(label .. " (dict metatable is nil)", getmetatable(dict) == nil)
    local ok, value = pcall(function() return dict.AddedWords end)
    assert_ok(label .. " (missing key read does not error)", ok and value == nil)
end

local YapperTable = {}
local core_loader = assert(loadfile("Src/Core.lua"))
core_loader("Yapper", YapperTable)
local Core = YapperTable.Core

-- Fresh init baseline.
_G.YapperDB = nil
_G.YapperLocalConf = nil
_G.YapperLocalHistory = nil
Core:InitSavedVars()

assert_no_dict_self_loop(_G.YapperDB, "InitSavedVars baseline")

-- Push flow should not corrupt global Spellcheck.Dict metatable.
Core:PushToGlobal()
assert_no_dict_self_loop(_G.YapperDB, "PushToGlobal")

-- Promote flow should also avoid self-looping the global Dict table.
Core:PromoteCharacterToGlobal()
assert_no_dict_self_loop(_G.YapperDB, "PromoteCharacterToGlobal")

-- Global profile inheritance should still resolve from global DB.
_G.YapperDB.EditBox.InputBg = { r = 0.2, g = 0.3, b = 0.4, a = 0.5 }
Core:PromoteCharacterToGlobal()
assert_ok(
    "Global profile inheritance still resolves EditBox.InputBg",
    YapperTable.Config.EditBox.InputBg == _G.YapperDB.EditBox.InputBg
)

-- Local-only behavior should still work when global profile is off.
_G.YapperDB = nil
_G.YapperLocalConf = nil
_G.YapperLocalHistory = nil
Core:InitSavedVars()
_G.YapperLocalConf.EditBox.FontSize = 21
assert_ok(
    "Single-character override remains local when not using global profile",
    _G.YapperDB.EditBox.FontSize ~= 21
)

print("All Core inheritance regression checks passed.")
