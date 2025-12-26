-- Compatibility patches for TRP3, including chat overrides.

-- TODO: Actually implement this.

--[[ -- Override TRP3's disabledByOOC function to always return true.
if TRP3_API and TRP3_API.chat then
    local originalDisabledByOOC = TRP3_API.chat.disabledByOOC;
    TRP3_API.chat.disabledByOOC = function() return true; end; -- Force disable
    -- Store originalDisabledByOOC to restore later
end]]

local YapperName, YapperTable = ...

-- Ensure CompatLib is loaded.
if not YapperTable.CompatLib then
    YapperTable.Error:Throw("PATCH_MISSING_COMPATLIB")
    return
end

-- CONFIGURATION --
local AddonPatchTarget = "ADDONNAME" -- REPLACE: The name of the addon we are patching.
local PatchFrameName = "Yapper" .. AddonPatchTarget .. "PatchFrame"

local PatchTable = {
    Patched = false,
    AddonName = AddonPatchTarget,
    Patch = function() return false end -- Default function.
}

-------------------------------------------------------------------------------------
-- PATCH LOGIC --

--- Patches [ADDONNAME] to be compatible with Yapper.
--- @return boolean True if the patch was successful, false otherwise.
function PatchTable:Patch()
    -- 1. Check if the addon is actually loaded and accessible.
    -- if not _G.ADDON_GLOBAL then return false end

    -- 2. Prevent double-patching.
    if self.Patched then return true end

    -- 3. APPLY MAGIC HERE --
    -- example: hooksecurefunc(_G.ADDON_GLOBAL, "FunctionName", function(...) end)

    self.Patched = true
    return true
end

-------------------------------------------------------------------------------------
-- REGISTRATION --

local function OnAddOnLoaded(self, Event, AddonName)
    -- Only act if our target addon is the one being loaded.
    if AddonName ~= AddonPatchTarget then return end

    -- Ensure the global CompatLib is ready.
    if _G.YAPPER_COMPATIBILITY and _G.YAPPER_COMPATIBILITY:IsLoaded() then
        -- Clean up the temporary listener frame.
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        self:Hide()

        -- Register this patch table with the Lib.
        _G.YAPPER_COMPATIBILITY:RegisterPatch(AddonPatchTarget, PatchTable)

        -- Attempt to apply the patch immediately.
        if PatchTable:Patch() then
            if _G.YAPPER_UTILS then
                _G.YAPPER_UTILS:Print(AddonPatchTarget .. " compatibility patch applied.")
            end
        end
    end
end

-- Create a temporary frame to listen for the addon loading.
local frame = CreateFrame("Frame", PatchFrameName, UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnAddOnLoaded)
