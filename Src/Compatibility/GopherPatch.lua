local YapperName, YapperTable = ...

if not YapperTable.CompatLib then
    YapperTable.Error:Throw("PATCH_MISSING_COMPATLIB")
    return
end

local PatchFrameName = "GopherPatchFrame"
local PatchTable = {
    Patched = false,
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
    else
        if _G.LibGopher.Listen then

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
        else
            return false
        end
    end
    return true
end

-- We will wait until YAPPER_COMPATIBILITY is loaded before registering the patch.
local function OnAddOnLoaded(self, event, AddonName)
    if not AddonName or AddonName == "" or AddonName ~= AddonPatchTarget then return end
    -- If the global YAPPER_COMPATIBILITY:IsLoaded() returns true on an ADDON_LOADED event, we're ready.
    if _G.YAPPER_COMPATIBILITY and _G.YAPPER_COMPATIBILITY:IsLoaded() then
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        self:Hide()
        _G.YAPPER_COMPATIBILITY:RegisterPatch(AddonPatchTarget, PatchTable) -- Register the patch.
        -- Then apply it.
        if PatchTable:Patch() then
            YapperTable.Utils:Print(AddonPatchTarget .. " patch for " .. YapperName .. " has been applied.")
        end
    end
end

local frame = CreateFrame("Frame", PatchFrameName, UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnAddOnLoaded)