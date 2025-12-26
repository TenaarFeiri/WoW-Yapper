local YapperName, YapperTable = ...

-- Ensure CompatLib is loaded.
if not YapperTable.CompatLib then
    YapperTable.Error:Throw("PATCH_MISSING_COMPATLIB")
    return
end

-- CONFIGURATION --
local AddonPatchTarget = "ADDONNAME" -- REPLACE: The name of the addon we are patching.

local PatchTable = {
    Patched = false,
    AddonName = AddonPatchTarget,
    Patch = function() return false end -- Default function.
}

-------------------------------------------------------------------------------------
-- WHATEVER YOU WANT HERE --

-------------------------------------------------------------------------------------
--[[
    This is the actual meat of the template.
    Once you have modified the configs, added your own variables, functions, whatever,
    you register these functions by adding them into Patch(), which is run automatically
    when Yapper is loaded.

    You can also add your own functions to the PatchTable, and call them from Patch().

    Example:

    function PatchTable:MyFunction()
        -- Do stuff here.
    end

    Another example of how you can use this is to write replacement functions for
    Yapper which are stored in YapperTable, or in its modules (like YapperTable.Chat)
    and have them registered.
    If you have an addon that is doing something to the chat under specific circumstances,
    you can store Yapper's chat functions as a variable and overwrite functions like ProcessPost
    or YapperOnEnter to do whatever you want.
    Just be sure to set everything back again afterwards; the power of these patches is they can
    impose session-lasting changes to Yapper's functionality. It's a lot of responsibility.

    Here's a real-world example:
    
        -- Store original function
        local OriginalProcessPost = YapperTable.Chat.ProcessPost
        
        -- Override with custom behaviour
        YapperTable.Chat.ProcessPost = function(self, text, limit)
            -- Custom logic here
            return OriginalProcessPost(self, text, limit)
        end
    
        -- Remember to restore in cleanup!

    You could also do this the hard way, everything important should be exposed, but
    I hope this framework and template can help automate some of the work.
]]

--- Patches [ADDONNAME] to be compatible with Yapper.
--- @return boolean True if the patch was successful, false otherwise.
function PatchTable:Patch()
    -- 1. Check if the addon is actually loaded and accessible.
    -- if not _G.ADDON_GLOBAL then return false end

    -- 2. Prevent double-patching.
    -- This is critical! CompatLib will call Patch() on ALL registered patches
    -- automatically, when the edit box is shown.
    -- Without this, whatever you do from this point on will happen every time
    -- the user opens their edit box to chat. EVERY. TIME.
    if self.Patched then return true end

    -- 3. APPLY MAGIC HERE --
    -- example: hooksecurefunc(_G.ADDON_GLOBAL, "FunctionName", function(...) end)

    self.Patched = true
    return true
end

-------------------------------------------------------------------------------------
-- REGISTRATION --

--- Register the patch immediately. CompatLib will call Patch() when needed.
--- The Patch() function has built-in guards against re-execution.
if _G.YAPPER_COMPATIBILITY and _G.YAPPER_COMPATIBILITY:IsLoaded() then
    _G.YAPPER_COMPATIBILITY:RegisterPatch(AddonPatchTarget, PatchTable)
end
