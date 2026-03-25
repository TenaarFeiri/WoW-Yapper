--[[
    Small utility belt: printing, string helpers.
]]

local YapperName, YapperTable = ...

local Utils = {}
YapperTable.Utils = Utils

-- ---------------------------------------------------------------------------

local SENDER_PRESETS = {
    info    = "FFFFAA00",
    warn    = "FFFF4444",
    success = "FF00FF00",
    white   = "FFFFFFFF",
}

function Utils:Print(...)
    local args = { ... }

    -- Optional preset as first arg: Utils:Print("info", "message...")
    local prefix = YapperTable.Config.System.PREFIX and (YapperTable.Config.System.PREFIX .. ": ") or
        (YapperName .. ": ")
    if type(args[1]) == "string" and SENDER_PRESETS[args[1]] then
        local preset = table.remove(args, 1)
        prefix = ("|c%s%s:|r "):format(SENDER_PRESETS[preset], YapperName)
    end

    for i = 1, #args do args[i] = tostring(args[i]) end
    print(prefix .. table.concat(args, " "))
end

function Utils:VerbosePrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.VERBOSE then
        self:Print(...)
    end
end

function Utils:DebugPrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Print("DEBUG:", ...)
    end
end

--- Return the correct parent frame for chat-related UI.
--- During housing-editor (or any fullscreen panel) this is the panel
--- frame; otherwise plain UIParent.
function Utils:GetChatParent()
    if FCF_GetCurrentFullScreenFrame then
        return FCF_GetCurrentFullScreenFrame() or UIParent
    end
    return UIParent
end

--- Ensure frame stays parented to the active fullscreen panel
--- (housing editor, fullscreen dialogs, etc.).
--- Hooks FCF_SetFullScreenFrame/ClearFullScreenFrame and updates on
--- OnShow so the frame is repointed whenever the panel switches.
--- Frames that already set their parent can use this merely as a fallback.
function Utils:MakeFullscreenAware(frame)
    if not frame then return end
    local function update()
        if not frame or not frame:IsShown() then return end
        local target = self:GetChatParent()
        if frame:GetParent() == target then return end   -- already correct
        if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
            FrameUtil.SetParentMaintainRenderLayering(frame, target)
        else
            frame:SetParent(target)
        end
    end
    if FCF_SetFullScreenFrame then
        hooksecurefunc("FCF_SetFullScreenFrame", update)
    end
---@diagnostic disable-next-line: undefined-global
    if FCF_ClearFullScreenFrame then
        hooksecurefunc("FCF_ClearFullScreenFrame", update)
    end
    frame:HookScript("OnShow", update)
    return update
end


-- Return true if chat is currently under a real lockdown condition.
function Utils:IsChatLockdown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() then
        return true
    end
    return false
end

-- Expose globally — other addons and compat patches may use this.
_G.YAPPER_UTILS = Utils

-- Return true if the supplied value is secret (obfuscated) and should be
-- treated with caution. Prefer the built-in WoW API when available.
function Utils:IsSecret(value)
    if not value or value == "" then return true end
    if type(issecretvalue) == "function" then
        local ok, res = pcall(issecretvalue, value)
        if ok and res == true then
            if type(canaccessvalue) == "function" then
                local ok2, access = pcall(canaccessvalue, value)
                if ok2 and access == true then
                    return false
                end
            end
            return true
        end
    end
    -- Fallback heuristic: battle.net obfuscated tokens include "|K".
    if type(value) == "string" and value:find("|K") then return true end
    if type(value) == "string" and value:match("^%s*$") then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- String helpers
-- ---------------------------------------------------------------------------

--- Strip leading and trailing whitespace.
function Utils:Trim(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "Trim", "string", type(s))
        return ""
    end
    return s:match("^%s*(.-)%s*$")
end

--- Return the byte position of the start of the last word in `s`.
function Utils:FindLastWord(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "FindLastWord", "string", type(s))
        return nil
    end
    return s:find("[^%s]+$")
end
