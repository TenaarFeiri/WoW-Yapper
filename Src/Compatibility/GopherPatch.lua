local YapperName, YapperTable = ...

if not YapperTable.CompatLib then
    YapperTable.Error:Throw("PATCH_MISSING_COMPATLIB")
    return
end

local PatchTable = {
    Patched = false,
    InProgress = false,
    AddonName = nil,
    Patch = function() return false end -- Default function.
}
local AddonPatchTarget = "Gopher" -- The addon we are patching.
PatchTable.AddonName = AddonPatchTarget

--- Patches Gopher to be compatible with Yapper.
--- @return boolean True if the patch was successful, false otherwise.
function PatchTable:Patch() -- Patch the Gopher addon.
    if not _G.LibGopher or not _G.LibGopher.Internal then
        -- Gopher isn't loaded, so we just return false.
        return false
    end
    if PatchTable.Patched then
        return true
    end

    if PatchTable.InProgress then
        return false
    end

    PatchTable.InProgress = true -- Mark as applying early to prevent re-entry.
    local ok, info = pcall(function()
        -- Gopher saves the original C_ChatInfo.SendChatMessage before hooking it.
        -- Using this bypasses Gopher's queue completely and returns msgID.
        if _G.LibGopher.Internal and _G.LibGopher.Internal.hooks and _G.LibGopher.Internal.hooks.SendChatMessage then
            YapperTable.SendChatMessageOverride = _G.LibGopher.Internal.hooks.SendChatMessage
        else
            error("LibGopher.Internal.hooks.SendChatMessage not found")
        end
        PatchTable.Patched = true
        YapperTable.Utils:Print("Gopher detected and patched successfully.")
    end)

    -- Ensure InProgress is cleared regardless of success or error
    PatchTable.InProgress = false

    if not ok then
        -- Log the failure but do not leave InProgress set.
        if YapperTable and YapperTable.Error and type(YapperTable.Error.PrintError) == "function" then
            YapperTable.Error:PrintError("UNKNOWN", "GopherPatch", tostring(info))
        end
        return ok, info
    end

    return ok, info
end

-- Register the patch immediately. CompatLib will call Patch() when needed.
-- The Patch() function has built-in guards against re-execution.
-- TOC load order guarantees CompatLib is available here.
YapperTable.CompatLib:RegisterPatch(AddonPatchTarget, PatchTable)