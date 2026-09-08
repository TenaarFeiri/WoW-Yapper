--[[
    Hooks/Slash.lua
    Slash command forwarding to Blizzard.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore

-- Re-localise Lua globals.
local type = type
local strupper = string.upper

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

--- Execute an unrecognised slash command through Blizzard's command registry.
--- This avoids calling ChatEdit_SendText from Yapper's tainted overlay path;
--- Blizzard's own handler remains responsible for protected-command feedback.
function EditBox:ForwardSlashCommand(text)
    if type(text) ~= "string" or text == "" then
        return false
    end

    -- If chat is locked down (combat/m+ lockdown), save draft and handoff.
    -- Blizzard must retain ownership of native command execution there.
    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        self:HandoffToBlizzard()
        return false
    end

    local command, args = text:match("^%s*(/[^%s]+)%s*([%s%S]*)$")
    if not command then
        return false
    end

    if ChatFrameUtil and ChatFrameUtil.ImportAllListsToHash then
        ChatFrameUtil.ImportAllListsToHash()
    end

    local commandTable = _G.hash_SlashCmdList
    local handler = commandTable and commandTable[strupper(command)]
    if type(handler) ~= "function" then
        return false
    end

    -- Do not pcall the handler. Protected-command failures should retain
    -- Blizzard's normal user-facing blocked-command behavior.
    handler(strtrim(args or ""))
    return true
end
