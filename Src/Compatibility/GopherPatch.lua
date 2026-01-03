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
        if not _G.LibGopher.Listen then error("LibGopher.Listen missing") end

        local ChatTypes = {
            SAY = true,
            YELL = true,
            PARTY = true,
            RAID = true,
            EMOTE = true,
            GUILD = true
        }
        YapperTable.SendChatMessageOverride = _G.LibGopher.Internal.hooks.SendChatMessage -- Gopher saves the original hook before it overrides it.
        -- If Listen exists, we apply our patch.
        _G.LibGopher.Listen("CHAT_NEW", function(Event, Text, Chat_Type, Arg3, Target)
            if ChatTypes[Chat_Type] then
                -- If the chat type is a Yapper type, we return false to prevent the message from
                -- being read by Gopher.
                return false
            end
            -- Nil, i.e Gopher takes over.
        end)
        PatchTable.Patched = true
        _G.YAPPER_UTILS:Print("Gopher detected and patched successfully.")
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
if _G.YAPPER_COMPATIBILITY and _G.YAPPER_COMPATIBILITY:IsLoaded() then
    _G.YAPPER_COMPATIBILITY:RegisterPatch(AddonPatchTarget, PatchTable)
end