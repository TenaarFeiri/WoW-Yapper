--[[
    Regression test: English variant inheritance and purge behavior.
]]

local function newHarness()
    _G.C_Timer = {}
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    local YapperName = "Yapper"
    local YapperTable = {
        Config = { Spellcheck = { Enabled = true, Locale = "enUS", NgramKeyCapSize = 0 } },
        Utils = { Print = function() end },
        Spellcheck = {
            Dictionaries = {},
            DictionaryBuilders = {},
            LocaleAddons = {
                enBase = "Yapper_Dict_en",
                enUS = "Yapper_Dict_enUS",
                enGB = "Yapper_Dict_enGB",
                enAU = "Yapper_Dict_enAU",
                deDE = "Yapper_Dict_deDE",
            },
            KnownLocales = { "enBase", "enUS", "enGB", "enAU", "deDE" },
            _asyncLoaders = {},
            _pendingBuilders = {},
            _pendingLocaleLoads = {},
            _DICT_CHUNK_SIZE = 1000,
            Clamp = function(v, min, max) return math.min(max, math.max(min, v)) end,
            NormaliseWord = function(s) return (s or ""):lower():gsub("[%p%c%s]", "") end,
            NormaliseVowels = function(s) return (s or ""):lower():gsub("[aeiouy]", "*") end,
            IsWordStartByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
            Notify = function() end,
            IsEnabled = function() return true end,
            ScheduleRefresh = function() end,
            ClearSuggestionCache = function() end,
            ClearUnderlines = function() end,
            GetConfig = function(self) return self._testConfig or { Locale = "enUS" } end,
            _RegisterLanguageEngine = function() end,
            UserDictCache = {},
            SuggestionFrame = nil,
            HintFrame = nil,
        },
    }

    local SC = YapperTable.Spellcheck
    local addonLoaders = {}
    local loadCalls = {}

    _G.C_AddOns = {
        GetAddOnInfo = function(addon) return addon, nil, nil, true, "DEMAND_LOADED" end,
        IsAddOnLoaded = function() return false end,
        LoadAddOn = function(addon)
            loadCalls[#loadCalls + 1] = addon
            local loader = addonLoaders[addon]
            if loader then loader() end
            return true
        end
    }

    local function LoadFile(path)
        local f = assert(loadfile(path))
        f(YapperName, YapperTable)
    end

    LoadFile("Src/Spellcheck/Dictionary.lua")
    LoadFile("Src/Spellcheck/UI.lua")

    return SC, addonLoaders, loadCalls
end

local failures = 0
local function check(name, cond)
    if cond then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name)
        failures = failures + 1
    end
end

do
    local SC, addonLoaders, loadCalls = newHarness()
    addonLoaders["Yapper_Dict_en"] = function()
        SC:RegisterDictionary("enBase", { words = { "hello", "world" }, languageFamily = "en", engine = {} })
    end

    SC:RegisterDictionary("enUS", { words = { "color" }, languageFamily = "en", extends = "enBase", isDelta = true })
    local base = SC.Dictionaries["enBase"]
    local us = SC.Dictionaries["enUS"]
    local mt = us and getmetatable(us.set)

    check("Fix 1: EnsureLocale demand-loads the enBase LOD addon", base ~= nil)
    check("Fix 1: enUS set inherits base membership via metatable", mt and mt.__index == base.set)
    check("Fix 1: base words resolve through inherited set", us and us.set["hello"] == true)
    check("Fix 1: enBase addon load was attempted", #loadCalls >= 1 and loadCalls[1] == "Yapper_Dict_en")
end

do
    local SC = newHarness()
    SC:RegisterDictionary("enBase", { words = { "hello", "world" }, languageFamily = "en", engine = {} })
    SC:RegisterDictionary("enGB", { words = { "colour" }, languageFamily = "en", extends = "enBase", isDelta = true })
    SC._asyncLoaders = { enBase = { cancelled = false }, frFR = { cancelled = false } }

    SC:PurgeOtherDictionaries("enUS")
    check("Fix 2: keep enBase when switching to not-yet-loaded enUS", SC.Dictionaries["enBase"] ~= nil)
    check("Fix 2: purge non-kept enGB", SC.Dictionaries["enGB"] == nil)
    check("Fix 2: keep enBase async loader", SC._asyncLoaders["enBase"] ~= nil and not SC._asyncLoaders["enBase"].cancelled)
    check("Fix 2: cancel/purge unrelated async loaders", SC._asyncLoaders["frFR"] == nil)
end

do
    local SC = newHarness()
    SC:RegisterDictionary("enBase", { words = { "hello", "world" }, languageFamily = "en", engine = {} })
    SC:RegisterDictionary("enUS", { words = { "color" }, languageFamily = "en", extends = "enBase", isDelta = true })
    SC:RegisterDictionary("deDE", { words = { "hallo", "welt" }, languageFamily = "de", engine = {} })

    SC:PurgeOtherDictionaries("deDE")
    check("Acceptance: keep target family locale", SC.Dictionaries["deDE"] ~= nil)
    check("Acceptance: purge unused English variant", SC.Dictionaries["enUS"] == nil)
    check("Acceptance: purge enBase when switching to deDE", SC.Dictionaries["enBase"] == nil)
end

if failures > 0 then
    print(("FAILED: %d checks failed"):format(failures))
    os.exit(1)
end
print("SUCCESS: all regression checks passed")
