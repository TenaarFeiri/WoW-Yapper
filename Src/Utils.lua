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
    local prefix = YapperName .. ": "
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
        -- If the frame carries a reposition callback, let it recompute
        -- its absolute coordinates for the new parent.
        if frame._yapperReposition then
            pcall(frame._yapperReposition)
        end
    end
    if FCF_SetFullScreenFrame then
        hooksecurefunc("FCF_SetFullScreenFrame", update)
    end
    if FCF_ClearFullScreenFrame then
        hooksecurefunc("FCF_ClearFullScreenFrame", update)
    end
    frame:HookScript("OnShow", update)
    return update
end


-- Return true if chat is currently under a real lockdown condition.
function Utils:IsChatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsChatLockdown) == "function" then
        return policy:IsChatLockdown() == true
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        return C_ChatInfo.InChatMessagingLockdown() == true
    end
    return false
end

-- Return true when protected-frame combat restrictions are active.
function Utils:IsCombatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsCombatLockdown) == "function" then
        return policy:IsCombatLockdown() == true
    end
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    return false
end

-- Return true when either chat-messaging or combat lockdown is active.
-- Useful for paths that manipulate secure/protected attributes.
function Utils:IsChatOrCombatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsChatOrCombatLockdown) == "function" then
        return policy:IsChatOrCombatLockdown() == true
    end
    return self:IsChatLockdown() or self:IsCombatLockdown()
end

-- Expose globally — other addons and compat patches may use this.
_G.YAPPER_UTILS = Utils

-- ---------------------------------------------------------------------------
-- Boilerplate helpers
-- ---------------------------------------------------------------------------

--- Ensure a value is a table, returning it or a new empty table.
--- @param t any
--- @return table
function Utils:EnsureTable(t)
    return type(t) == "table" and t or {}
end

--- Ensure a table path exists, creating intermediate tables as needed.
--- @param root table  The root table to traverse
--- @param ... string  Path segments (e.g., "EditBox", "ChannelTextColors")
--- @return table  The deepest table in the path
function Utils:EnsureTablePath(root, ...)
    local current = self:EnsureTable(root)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if type(key) ~= "string" and type(key) ~= "number" then return current end
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    return current
end

--- Assert type matches expected, return default if not.
--- @param value any  The value to check
--- @param expectedType string  Expected type string ("string", "table", etc.)
--- @param default any  Value to return if type doesn't match
--- @return any  Original value if type matches, otherwise default
function Utils:AssertType(value, expectedType, default)
    return type(value) == expectedType and value or default
end

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

--- Convert leetspeak characters back to their base alphabet equivalents.
--- Used to ensure blocked words can't be bypassed with common substitutions.
--- @param word string
--- @return string
function Utils.Deleet(word)
    -- a=4, e=3, i=1/!, o=0, s=5/$, t=7/+
    word = word:gsub("0", "o")
    word = word:gsub("1", "i")
    word = word:gsub("3", "e")
    word = word:gsub("4", "a")
    word = word:gsub("5", "s")
    word = word:gsub("7", "t")
    word = word:gsub("%$", "s")
    word = word:gsub("!", "i")
    word = word:gsub("%+", "t")
    return word
end
