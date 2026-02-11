local YapperName, YapperTable = ...

-- Ensure CompatLib is loaded.
if not YapperTable.CompatLib then
    YapperTable.Error:Throw("PATCH_MISSING_COMPATLIB")
    return
end

-- CONFIGURATION --
local AddonPatchTarget = "ADDONNAME" -- REPLACE: The name of the addon we are patching.

local PatchTable = {
    -- Optional fields, args, whatever you need that need to be exposed to Yapper or elsewhere, go below this line!
    ---------------------------------------------------------------------------------
    -- Example: ThrowParty = true,


    -- Don't forget the trailing comma. I KNOW YOU FORGOT THE COMMA.
    -------------------------------------------------------------------------------------
    -- DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING --
    -------------------------------------------------------------------------------------
    -- MANDATORY FIELDS --
    Patched = false, -- Mandatory: Set to true when the patch has been applied.
    InProgress = false, -- Mandatory: Set to true while the patch is being applied to prevent re-entrance.
    AddonName = AddonPatchTarget, -- Mandatory: The name of the addon we are patching.
    -- Patch should return (ok, info). `ok` is boolean; `info` is optional diagnostic data.
    Patch = function() return false end -- Default function. Obviously also mandatory.
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
    if self.Patched then
        return true
    end

    -- Furthermore, prevent re-entrance if Patch() is already running.
    -- We really don't want a race condition to occur.
    if self.InProgress then
        return false
    end

    -- Apply patch guarded in pcall so failures won't leave InProgress set.
    self.InProgress = true
    local ok, info = pcall(function()
        -- 3. All your patch execution happens here. --
        -- example: hooksecurefunc(_G.ADDON_GLOBAL, "FunctionName", function(...) end)
        -- If you need to signal failure, error("reason") inside this block.
        --
        -- This is where you can override Yapper, set your own events, etc., and everything
        -- originates from Patch(). If you need further executions AFTER this, Patch() has to set
        -- that up, so you're responsible for creating any further hooks, timers, or whatever.
        -- The patch file itself can contain all the functions, extra tables, etc., that you 
        -- need to manage the program, and the patch is not discarded after execution,
        -- BUT IT WILL ONLY BE LOADED ONCE per session.
        -- If you set Patched to false here, that's on you; Yapper will run EVERY patch that is not
        -- Patched each time the edit box is shown. 
        -- Repeat: ---***YAPPER WILL RUN EVERY UNPATCHED PATCH EACH TIME THE EDIT BOX IS SHOWN!!!***---
    end)
    self.InProgress = false

    if not ok then
        -- pcall returns (false, err) on failure; return that to our caller.
        return ok, info
    end

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
