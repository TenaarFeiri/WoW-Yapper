--[[
    Policies/LockdownPolicy.lua
    Central policy object for lockdown and permission checks.
    Passive module: declares policy methods only; performs no startup work.
]]

local _, YapperTable = ...

local LockdownPolicy = {}
YapperTable.LockdownPolicy = LockdownPolicy

-- ---------------------------------------------------------------------------
-- Addon restriction API (WoW 12.x: C_RestrictedActions / Enum.AddOnRestriction*)
-- ---------------------------------------------------------------------------

--- True when the client exposes the C_RestrictedActions surface.
--- @return boolean
function LockdownPolicy:HasAddOnRestrictionAPI()
    return type(C_RestrictedActions) == "table"
        and type(C_RestrictedActions.IsAddOnRestrictionActive) == "function"
        and type(Enum) == "table"
        and type(Enum.AddOnRestrictionType) == "table"
end

--- Returns true when a single Enum.AddOnRestrictionType is enforced.
--- @param restrictionType number|nil
--- @return boolean
function LockdownPolicy:IsAddOnRestrictionActive(restrictionType)
    if not self:HasAddOnRestrictionAPI() or restrictionType == nil then
        return false
    end
    local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, restrictionType)
    return ok and active == true
end

--- Returns true while ANY addon restriction type is enforced. Non-chat
--- restrictions leave messaging usable but poison Blizzard-produced data
--- (unit names, etc.) with secret values, so tainted calls into Blizzard
--- handlers -- forwarded slash commands, unit-menu clicks -- error on secret
--- comparisons inside Blizzard code.
--- @return boolean
function LockdownPolicy:IsAnyAddOnRestrictionActive()
    if not self:HasAddOnRestrictionAPI() then return false end
    for _, restrictionType in pairs(Enum.AddOnRestrictionType) do
        if self:IsAddOnRestrictionActive(restrictionType) then
            return true
        end
    end
    return false
end

-- Returns true if chat messaging security restrictions are active.
function LockdownPolicy:IsChatLockdown()
    -- The Chat restriction type is authoritative on clients with
    -- C_RestrictedActions; InChatMessagingLockdown covers older clients.
    local chatType = Enum and Enum.AddOnRestrictionType
        and Enum.AddOnRestrictionType.Chat
    if self:IsAddOnRestrictionActive(chatType) then
        return true
    end
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
    "MACRO",         -- /m, /macro -> ShowMacroFrame -> ShowUIPanel
    "ACHIEVEMENTUI", -- /achieve, /achievements -> ToggleAchievementFrame -> ShowUIPanel
    "RAIDFINDER",    -- /lfr, /df -> PVEFrame_ToggleFrame -> ShowUIPanel
}

local ALWAYS_FORBIDDEN_COMMAND_KEYS = {
    "TARGET",
    "TARGET_EXACT",
    "TARGET_NEAREST_ENEMY",
    "TARGET_NEAREST_ENEMY_PLAYER",
    "TARGET_NEAREST_FRIEND",
    "TARGET_NEAREST_FRIEND_PLAYER",
    "TARGET_NEAREST_PARTY",
    "TARGET_NEAREST_RAID",
    "CLEARTARGET",
    "TARGET_LAST_TARGET",
    "TARGET_LAST_ENEMY",
    "TARGET_LAST_FRIEND",
    "ASSIST",
    "FOCUS",
    "CLEARFOCUS",
}

local ALWAYS_FORBIDDEN_COMMANDS = {
    ["/TARGET"] = true,
    ["/TAR"] = true,
    ["/TARGETEXACT"] = true,
    ["/CLEARTARGET"] = true,
    ["/ASSIST"] = true,
    ["/FOCUS"] = true,
    ["/CLEARFOCUS"] = true,
}

local function MatchesCommandAlias(command, keys)
    local upper = command:upper()
    for _, key in ipairs(keys) do
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
    return MatchesCommandAlias(command, PROTECTED_COMMAND_KEYS)
end

--- Returns true when Blizzard's slash handler always reports its protected
--- action as an addon-forbidden call, even outside combat lockdown.
--- @param command string  Slash command including the leading slash.
--- @return boolean
function LockdownPolicy:IsAlwaysForbiddenSlashCommand(command)
    if type(command) ~= "string" or command == "" then return false end
    local upper = command:upper()
    return ALWAYS_FORBIDDEN_COMMANDS[upper]
        or MatchesCommandAlias(command, ALWAYS_FORBIDDEN_COMMAND_KEYS)
end
