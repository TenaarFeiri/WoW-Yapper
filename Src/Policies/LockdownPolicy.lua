--[[
    Policies/LockdownPolicy.lua
    Central policy object for lockdown and permission checks.
    Passive module: declares policy methods only; performs no startup work.
]]

local _, YapperTable = ...

local LockdownPolicy = {}
YapperTable.LockdownPolicy = LockdownPolicy

-- Returns true if chat messaging security restrictions are active.
function LockdownPolicy:IsChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() == true
end

-- Returns true if protected-frame combat restrictions are active.
function LockdownPolicy:IsCombatLockdown()
    return InCombatLockdown and InCombatLockdown() == true
end

-- Returns true when either chat or combat lockdown is active.
function LockdownPolicy:IsChatOrCombatLockdown()
    return self:IsChatLockdown() or self:IsCombatLockdown()
end

-- Non-secure slash command keys whose Blizzard handlers invoke protected
-- APIs (frame toggles, unit interaction, etc.). They are absent from
-- Blizzard's secure command registry but still trip "Interface action
-- blocked" when dispatched from tainted code during combat lockdown.
local PROTECTED_COMMAND_KEYS = {
    "MACRO",         -- /m, /macro → ShowMacroFrame → ShowUIPanel
    "ACHIEVEMENTUI", -- /achieve, /achievements → ToggleAchievementFrame → ShowUIPanel
    "RAIDFINDER",    -- /lfr, /df → PVEFrame_ToggleFrame → ShowUIPanel
}

--- Returns true when a slash command token (e.g. "/m") resolves to an action
--- that insecure code cannot run during combat lockdown.
--- @param command string  Slash command including the leading slash.
--- @return boolean
function LockdownPolicy:IsProtectedSlashCommand(command)
    if type(command) ~= "string" or command == "" then return false end

    -- Blizzard's secure command registry (/cast, /target, /click, ...).
    if type(IsSecureCmd) == "function" and IsSecureCmd(command) then
        return true
    end

    -- Non-secure commands that still call protected APIs. Aliases are read
    -- from the SLASH_<key>i globals so localised clients resolve too.
    local upper = command:upper()
    for _, key in ipairs(PROTECTED_COMMAND_KEYS) do
        local i = 1
        local alias = _G["SLASH_" .. key .. i]
        while alias do
            if type(alias) == "string" and alias:upper() == upper then
                return true
            end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
    return false
end
