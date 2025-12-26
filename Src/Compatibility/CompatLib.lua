local YapperName, YapperTable = ...

if not YapperTable then
    YapperTable = {}
end

local CompatLib = {}
YapperTable.CompatLib = CompatLib
CompatLib.Patches = {}

local reservedNames = {
    all = true,
    compatlib = true
}

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
    
    if type(PatchTable) ~= "table" then
        -- if not a table then it's not a patch; halt execution.
        YapperTable.Error:Throw("BAD_ARG", "RegisterPatch", "table", type(PatchTable))
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
        if type(PatchTable.Patch) == "function" then
            table.insert(Applied, {Addon, PatchTable:Patch()})
        end
    end
    elseif CompatLib.Patches[AddonName] then
        local PatchTable = CompatLib.Patches[AddonName]
        if type(PatchTable.Patch) == "function" then
            table.insert(Applied, {AddonName, PatchTable:Patch()})
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