local YapperName, YapperTable = ...

if not YapperTable then
    YapperTable = {}
end

local CompatLib = {}
YapperTable.CompatLib = CompatLib
CompatLib.Patches = {}

-- Compatibility system contract:
-- - Each registered patch is a table (PatchTable) exposing at least:
--     * PatchTable.Patch: function() -> returns (ok, info) where `ok` is boolean
--       and `info` is optional diagnostic data (string/table) or nil.
--     * PatchTable.Patched: boolean flag set to true after a successful patch.
--     * (optional) PatchTable.InProgress: boolean used to guard concurrent runs.
--     * (set by CompatLib) PatchTable.PatchReturnData = { ok = bool, info = ... }
-- - `CompatLib:ApplyPatches(name)` will call `PatchTable:Patch()` for each matching
--   registered patch and store its return in `PatchTable.PatchReturnData`.
-- - The `Applied` return value from `ApplyPatches` is an array of
--   `{ AddonName, PatchReturnData }` entries for diagnostics and testing.

local reservedNames = {
    all = true,
    compatlib = true
}

--- Validates a PatchTable to ensure required fields exist and initializes defaults.
-- @param PatchTable table The patch table to validate.
-- @return boolean, string True if valid, otherwise false and a reason string.
function CompatLib:ValidatePatch(PatchTable)
    if type(PatchTable) ~= "table" then
        return false, "table", type(PatchTable)
    end
    if type(PatchTable.Patch) ~= "function" then
        return false, "Patch function", type(PatchTable.Patch)
    end
    if type(PatchTable.Patched) ~= "boolean" then
        return false, "Patched boolean", type(PatchTable.Patched)
    end
    if type(PatchTable.InProgress) ~= "boolean" then
        return false, "InProgress boolean", type(PatchTable.InProgress)
    end
    if type(PatchTable.AddonName) ~= "string" then
        return false, "AddonName string", type(PatchTable.AddonName)
    end
    return true
end

--- Checks if a patch is registered and returns its version.
-- @param PatchName The name of the patch (case-insensitive).
-- @return string|false The version of the patch, or false if not found.
function CompatLib:CheckPatchVersion(PatchName)
    if PatchName == nil or PatchName == "" then return false end
    PatchName = string.lower(PatchName)
    local Patch = CompatLib.Patches[PatchName]
    
    if type(Patch) == "table" then
        if Patch.Version then return Patch.Version end
        if type(Patch.GetVersion) == "function" then
            return Patch.GetVersion()
        end
    end
    return false
end

--- Registers a new compatibility patch for a specific addon.
-- @param AddonName The name of the addon (case-insensitive).
-- @param PatchTable The function to execute when applying the patch.
function CompatLib:RegisterPatch(AddonName, PatchTable)
    if not AddonName or AddonName == "" or not PatchTable then return end
    
    if type(AddonName) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "RegisterPatch", "string", type(AddonName))
        return
    end
    
    -- Validate the patch structure; throw on invalid patch tables (developer error).
    local ok, expected, got = CompatLib:ValidatePatch(PatchTable)
    if not ok then
        YapperTable.Error:Throw("BAD_ARG", "RegisterPatch", expected, got)
        return
    end
    
    -- We don't allow reserved names to be registered.
    local NameLower = string.lower(AddonName)
    if reservedNames[NameLower] then
        YapperTable.Error:Throw("BAD_ARG", "RegisterPatch", "reserved name", AddonName)
        return
    end
    
    CompatLib.Patches[NameLower] = PatchTable
end

--- Applies registered patches.
-- @param AddonName (Optional) The name of a specific addon to patch, or "all" to run all. Defaults to "all" if nil.
-- @return table List of {AddonName, result} pairs for applied patches.
function CompatLib:ApplyPatches(AddonName)
    if not CompatLib.Patches then
        -- If there are no patches, there's nothing to do.
        -- This is normal and fine.
        return
    end

    AddonName = AddonName and string.lower(AddonName) or "all"
    if AddonName == "all" and not YapperTable.Config.System.RUN_ALL_PATCHES then
        return
    end

    local Applied = {}
    if AddonName == "all" then
        for Addon, PatchTable in pairs(CompatLib.Patches) do
            if type(PatchTable.Patch) == "function" and PatchTable.Patched ~= true then
                local ok, info = PatchTable:Patch()
                PatchTable.PatchReturnData = { ok = ok, info = info }
                table.insert(Applied, { Addon, PatchTable.PatchReturnData })
            end
        end
    elseif CompatLib.Patches[AddonName] then
        local PatchTable = CompatLib.Patches[AddonName]
        if type(PatchTable.Patch) == "function" and PatchTable.Patched ~= true then
            local ok, info = PatchTable:Patch()
            PatchTable.PatchReturnData = { ok = ok, info = info }
            table.insert(Applied, { AddonName, PatchTable.PatchReturnData })
        end
    end
    
    return Applied
end

function CompatLib:IsLoaded()
    return true -- This is always loaded.
end

-- Finally, expose CompatLib to the global namespace.
_G.YAPPER_COMPATIBILITY = CompatLib

if _G.YAPPER_COMPATIBILITY and YapperTable.Debug then
    if _G.YAPPER_UTILS then
        _G.YAPPER_UTILS:Print("Yapper Compatibility library is loaded.")
    else
        YapperTable.Utils:Print("Yapper Compatibility library is loaded.")
    end
end