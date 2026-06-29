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
