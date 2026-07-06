#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_migrations.lua  --  Migrations module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_migrations.lua
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
-- Helpers
-- ===========================================================================

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do out[k] = DeepCopy(v) end
    return out
end

-- ===========================================================================
-- WoW environment mock
-- ===========================================================================

_G = _G or {}

local printLog = {}
local YapperName = "Yapper"
local YapperTable = {
    Utils = {
        Print = function(self, ...)
            local args = { ... }
            printLog[#printLog + 1] = table.concat(args, " ")
        end,
    },
    Core = nil,
}

-- Load Migrations.lua fresh for each test group by reloading.
local function LoadMigrations()
    local loader, err = loadfile("Src/Migrations.lua")
    if not loader then
        print("FATAL: " .. tostring(err))
        os.exit(1)
    end
    loader(YapperName, YapperTable)
    return YapperTable.Migrations
end

-- ===========================================================================
-- Test 1: YALLM -> YAS migration
-- ===========================================================================
print("\nTest 1: YALLM -> YAS migration")

local Migrations = LoadMigrations()
printLog = {}

local config = {
    Spellcheck = {
        YALLMEnabled = true,
        YALLMFreqCap = 100,
        YALLMBiasCap = 50,
        YALLMNegBiasCap = -10,
        YALLMAutoThreshold = 5,
        YALLMAutoCap = 200,
        ExistingKey = "untouched",
    },
}

Migrations:MigrateYALLMToYAS(config, "DB")

check("YASEnabled set", config.Spellcheck.YASEnabled == true)
check("YASFreqCap set", config.Spellcheck.YASFreqCap == 100)
check("YASBiasCap set", config.Spellcheck.YASBiasCap == 50)
check("YASNegBiasCap set", config.Spellcheck.YASNegBiasCap == -10)
check("YASAutoThreshold set", config.Spellcheck.YASAutoThreshold == 5)
check("YASAutoCap set", config.Spellcheck.YASAutoCap == 200)

check("YALLMEnabled removed", config.Spellcheck.YALLMEnabled == nil)
check("YALLMFreqCap removed", config.Spellcheck.YALLMFreqCap == nil)
check("YALLMBiasCap removed", config.Spellcheck.YALLMBiasCap == nil)
check("YALLMNegBiasCap removed", config.Spellcheck.YALLMNegBiasCap == nil)
check("YALLMAutoThreshold removed", config.Spellcheck.YALLMAutoThreshold == nil)
check("YALLMAutoCap removed", config.Spellcheck.YALLMAutoCap == nil)

check("existing key untouched", config.Spellcheck.ExistingKey == "untouched")
check("migration logged", #printLog > 0)

-- ===========================================================================
-- Test 2: YALLM migration is idempotent (no-op on second run)
-- ===========================================================================
print("\nTest 2: YALLM migration idempotence")

printLog = {}
Migrations:MigrateYALLMToYAS(config, "DB")
check("no log on second run (already migrated)", #printLog == 0)
check("YASEnabled still set", config.Spellcheck.YASEnabled == true)

-- ===========================================================================
-- Test 3: YALLM migration with nil/missing config
-- ===========================================================================
print("\nTest 3: YALLM migration with nil/missing data")

-- Reload to reset _completedMigrations.
Migrations = LoadMigrations()

Migrations:MigrateYALLMToYAS(nil, "DB")
check("nil config doesn't crash", true)

Migrations = LoadMigrations()
Migrations:MigrateYALLMToYAS({}, "DB")
check("no Spellcheck key doesn't crash", true)

Migrations = LoadMigrations()
Migrations:MigrateYALLMToYAS({ Spellcheck = "not_a_table" }, "DB")
check("non-table Spellcheck doesn't crash", true)

-- ===========================================================================
-- Test 4: YALLM migration with partial keys
-- ===========================================================================
print("\nTest 4: YALLM migration with partial keys")

Migrations = LoadMigrations()
local partialConfig = {
    Spellcheck = {
        YALLMEnabled = false,
        -- Other YALLM keys absent.
        OtherKey = 99,
    },
}

Migrations:MigrateYALLMToYAS(partialConfig, "LOCAL")
check("partial: YASEnabled set", partialConfig.Spellcheck.YASEnabled == false)
check("partial: YALLMEnabled removed", partialConfig.Spellcheck.YALLMEnabled == nil)
check("partial: OtherKey untouched", partialConfig.Spellcheck.OtherKey == 99)
check("partial: no YASFreqCap created", partialConfig.Spellcheck.YASFreqCap == nil)

-- ===========================================================================
-- Test 5: ChannelColorMode migration
-- ===========================================================================
print("\nTest 5: ChannelColorMode migration")

Migrations = LoadMigrations()
printLog = {}

-- Mock Core:GetDefaults for colour comparison.
YapperTable.Core = {
    GetDefaults = function()
        return {
            EditBox = {
                ChannelTextColors = {
                    SAY = { r = 1.0, g = 1.0, b = 1.0 },
                    YELL = { r = 1.0, g = 0.0, b = 0.0 },
                    PARTY = { r = 0.0, g = 0.0, b = 1.0 },
                    WHISPER = { r = 0.5, g = 0.5, b = 0.5 },
                    BN_WHISPER = { r = 0.3, g = 0.3, b = 0.3 },
                    CHANNEL = { r = 0.7, g = 0.7, b = 0.7 },
                    CLUB = { r = 0.2, g = 0.2, b = 0.2 },
                    INSTANCE_CHAT = { r = 0.8, g = 0.8, b = 0.8 },
                    RAID = { r = 0.9, g = 0.9, b = 0.9 },
                    RAID_WARNING = { r = 0.1, g = 0.1, b = 0.1 },
                },
            },
        }
    end,
}

local ccConfig = {
    EditBox = {
        ChannelColorOverrides = {
            SAY = true,    -- Was following master → "master"
            YELL = false,  -- Not following master → check colour
        },
        ChannelTextColors = {
            SAY = { r = 1.0, g = 1.0, b = 1.0 },  -- same as default
            YELL = { r = 0.5, g = 0.5, b = 0.5 },  -- different from default → "custom"
            PARTY = { r = 0.0, g = 0.0, b = 1.0 },  -- same as default
        },
    },
}

Migrations:MigrateChannelColorMode(ccConfig, "DB")

check("ChannelColorMode table created", type(ccConfig.EditBox.ChannelColorMode) == "table")
check("SAY mode is master", ccConfig.EditBox.ChannelColorMode.SAY == "master")
check("YELL mode is custom (differs from default)", ccConfig.EditBox.ChannelColorMode.YELL == "custom")
check("PARTY mode is blizzard (same as default)", ccConfig.EditBox.ChannelColorMode.PARTY == "blizzard")
check("WHISPER mode defaults to blizzard", ccConfig.EditBox.ChannelColorMode.WHISPER == "blizzard")
check("old overrides cleaned up", ccConfig.EditBox.ChannelColorOverrides == nil)
check("migration logged", #printLog > 0)

-- ===========================================================================
-- Test 6: ChannelColorMode migration idempotence
-- ===========================================================================
print("\nTest 6: ChannelColorMode migration idempotence")

printLog = {}
local savedMode = DeepCopy(ccConfig.EditBox.ChannelColorMode)
Migrations:MigrateChannelColorMode(ccConfig, "DB")
check("no log on second run", #printLog == 0)
check("modes unchanged", ccConfig.EditBox.ChannelColorMode.SAY == savedMode.SAY)

-- ===========================================================================
-- Test 7: ChannelColorMode with nil/missing config
-- ===========================================================================
print("\nTest 7: ChannelColorMode with nil/missing data")

Migrations = LoadMigrations()

Migrations:MigrateChannelColorMode(nil, "DB")
check("nil config doesn't crash", true)

Migrations = LoadMigrations()
Migrations:MigrateChannelColorMode({}, "DB")
check("no EditBox key doesn't crash", true)

-- ===========================================================================
-- Test 8: RunMigrations orchestrator
-- ===========================================================================
print("\nTest 8: RunMigrations orchestrator")

Migrations = LoadMigrations()
printLog = {}

local fullConfig = {
    Spellcheck = {
        YALLMEnabled = true,
        YALLMFreqCap = 10,
    },
    EditBox = {
        ChannelColorOverrides = { SAY = true },
        ChannelTextColors = { SAY = { r = 0.5, g = 0.5, b = 0.5 } },
    },
}

Migrations:RunMigrations(fullConfig, "DB")
check("RunMigrations: YALLM migrated", fullConfig.Spellcheck.YASEnabled == true)
check("RunMigrations: ChannelColorMode created", type(fullConfig.EditBox.ChannelColorMode) == "table")

-- ===========================================================================
-- Test 9: MarkCompleted / IsCompleted
-- ===========================================================================
print("\nTest 9: MarkCompleted / IsCompleted")

Migrations = LoadMigrations()

check("unknown migration not completed", Migrations:IsCompleted("MY_MIGRATION") == false)
Migrations:MarkCompleted("MY_MIGRATION")
check("marked migration is completed", Migrations:IsCompleted("MY_MIGRATION") == true)

-- ===========================================================================
-- Test 10: DB vs LOCAL config types are tracked independently
-- ===========================================================================
print("\nTest 10: DB vs LOCAL independent tracking")

Migrations = LoadMigrations()

local dbConf = { Spellcheck = { YALLMEnabled = true } }
local localConf = { Spellcheck = { YALLMEnabled = false } }

Migrations:MigrateYALLMToYAS(dbConf, "DB")
check("DB migrated", dbConf.Spellcheck.YASEnabled == true)

Migrations:MigrateYALLMToYAS(localConf, "LOCAL")
check("LOCAL migrated independently", localConf.Spellcheck.YASEnabled == false)

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
