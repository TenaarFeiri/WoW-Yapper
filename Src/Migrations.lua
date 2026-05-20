--[[
    Migrations.lua
    Detached module for handling configuration key migrations and data structure changes.

    This module provides a centralized place for migrating old configuration keys
    to new ones without losing user data. Each migration function should:
    1. Check if the old key exists
    2. Copy the value to the new key
    3. Clear the old key
    4. Log the migration for user awareness

    Migrations are versioned and should only run once per version bump.
]]

local _, YapperTable = ...

local Migrations = {}
YapperTable.Migrations = Migrations

-- Localise Lua globals for performance
local type  = type
local pairs = pairs

-- ---------------------------------------------------------------------------
-- Migration Registry
-- ---------------------------------------------------------------------------

-- Track which migrations have been run to prevent re-migration
local _completedMigrations = {}

-- ---------------------------------------------------------------------------
-- YALLM → YAS Migration (Version 2.2)
-- -----------------------------------------------------------------

--- Migrate YALLM configuration keys to YAS equivalents.
--- This handles the renaming from "Yapper Adaptive Language Learning Model" 
--- to the more accurate "Yapper Adaptive Spellcheck" naming.
function Migrations:MigrateYALLMToYAS(configTable, configType)
    if not configTable or type(configTable) ~= "table" then return end
    if not configTable.Spellcheck or type(configTable.Spellcheck) ~= "table" then return end
    
    local sc = configTable.Spellcheck
    local migrationKey = "YALLM_TO_YAS_" .. (configType or "UNKNOWN")
    
    -- Skip if already migrated
    if _completedMigrations[migrationKey] then return end
    
    local migrated = false
    local changes = {}
    
    -- Migration map: old key -> new key
    local keyMap = {
        YALLMEnabled    = "YASEnabled",
        YALLMFreqCap    = "YASFreqCap", 
        YALLMBiasCap    = "YASBiasCap",
        YALLMNegBiasCap = "YASNegBiasCap",
        YALLMAutoThreshold = "YASAutoThreshold",
        YALLMAutoCap    = "YASAutoCap",
    }
    
    for oldKey, newKey in pairs(keyMap) do
        if sc[oldKey] ~= nil then
            -- Copy value to new key
            sc[newKey] = sc[oldKey]
            -- Clear old key
            sc[oldKey] = nil
            migrated = true
            changes[#changes + 1] = oldKey .. " → " .. newKey
        end
    end
    
    if migrated and YapperTable.Utils then
        local changeList = table.concat(changes, ", ")
        YapperTable.Utils:Print("info", "Migrated YALLM config keys to YAS: " .. changeList)
    end
    
    _completedMigrations[migrationKey] = true
end

-- ---------------------------------------------------------------------------
-- API Migration Entry Point
-- ---------------------------------------------------------------------------

--- Run all pending migrations for a given configuration table.
--- @param configTable table The configuration table to migrate (YapperDB or YapperLocalConf)
--- @param configType string "DB" for account-wide, "LOCAL" for per-character
function Migrations:RunMigrations(configTable, configType)
    if not configTable or type(configTable) ~= "table" then return end
    
    -- Always run YALLM → YAS migration if needed
    self:MigrateYALLMToYAS(configTable, configType)
end

--- Mark a migration as completed (for external callers)
--- @param migrationKey string Unique identifier for the migration
function Migrations:MarkCompleted(migrationKey)
    _completedMigrations[migrationKey] = true
end

--- Check if a migration has been completed
--- @param migrationKey string Unique identifier for the migration
--- @return boolean
function Migrations:IsCompleted(migrationKey)
    return _completedMigrations[migrationKey] == true
end
