--[[
    State.lua
    Centralised state machine for Yapper.
    Manages the lifecycle and transitions between different operational modes.
]]

local _, YapperTable = ...

local State = {}
YapperTable.State = State

--- @enum States
State.STATES = {
    IDLE      = "IDLE",      -- Overlay hidden, no active send or queue.
    EDITING   = "EDITING",   -- Single-line overlay is shown and focused.
    MULTILINE = "MULTILINE", -- Expanded storyteller editor is active.
    SENDING   = "SENDING",   -- Message is being processed or sent (chunking/router).
    STALLED   = "STALLED",   -- Queue is waiting for user hardware input to continue.
    LOCKDOWN  = "LOCKDOWN",  -- Combat or M+ handoff: overlay hidden, handed back to Blizzard.
}

-- Current active state.
State._current = State.STATES.IDLE

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Get the current state.
--- @return string
function State:Get()
    return self._current
end

--- Check if the machine is in a specific state.
--- @param state string
--- @return boolean
function State:Is(state)
    return self._current == state
end

--- Transition to a new state.
--- @param newState string One of State.STATES.
--- @param ... any Optional metadata to pass to callbacks.
function State:Transition(newState, ...)
    if not State.STATES[newState] then
        if YapperTable.Error then
            YapperTable.Error:PrintError("BAD_ARG", "State:Transition", "State.STATES", tostring(newState))
        end
        return
    end

    if self._current == newState then
        return
    end

    local oldState = self._current
    self._current = newState

    -- Emit state change event via API if available.
    if YapperTable.API and type(YapperTable.API.Fire) == "function" then
        YapperTable.API:Fire("STATE_CHANGED", newState, oldState, ...)
    end

    -- Debug logging
    local core = YapperTable.Core
    if core and core.Config and core.Config.System and core.Config.System.DEBUG then
        if YapperTable.Utils and type(YapperTable.Utils.DebugPrint) == "function" then
            YapperTable.Utils:DebugPrint("STATE", ("%s -> %s"):format(oldState, newState))
        end
    end
end

--- Reset the state machine to IDLE.
function State:Reset()
    self:Transition(self.STATES.IDLE)
end

-- ---------------------------------------------------------------------------
-- Semantic Helpers (Readable State Checks)
-- ---------------------------------------------------------------------------

--- Is the machine in IDLE state?
--- @return boolean
function State:IsIdle()
    return self._current == self.STATES.IDLE
end

--- Is the user typing in the single-line overlay?
--- @return boolean
function State:IsEditing()
    return self._current == self.STATES.EDITING
end

--- Is the user typing in the expanded multiline editor?
--- @return boolean
function State:IsMultiline()
    return self._current == self.STATES.MULTILINE
end

--- Is a message currently being delivered?
--- @return boolean
function State:IsSending()
    return self._current == self.STATES.SENDING
end

--- Is the queue stalled awaiting hardware input?
--- @return boolean
function State:IsStalled()
    return self._current == self.STATES.STALLED
end

--- Is the addon suppressed by combat or manual lockdown?
--- @return boolean
function State:IsLockdown()
    return self._current == self.STATES.LOCKDOWN
end

--- Helper: is the user currently typing (either overlay or multiline)?
--- @return boolean
function State:IsInputActive()
    return self:IsEditing() or self:IsMultiline()
end

--- Helper: is the addon busy (sending, stalled, or in lockdown)?
--- @return boolean
function State:IsBusy()
    return self:IsSending() or self:IsStalled() or self:IsLockdown()
end

-- ---------------------------------------------------------------------------
-- Semantic Transitions
-- ---------------------------------------------------------------------------

--- Transition to IDLE state.
function State:ToIdle(...)
    self:Transition(self.STATES.IDLE, ...)
end

--- Transition to EDITING state.
function State:ToEditing(...)
    self:Transition(self.STATES.EDITING, ...)
end

--- Transition to MULTILINE state.
function State:ToMultiline(...)
    self:Transition(self.STATES.MULTILINE, ...)
end

--- Transition to SENDING state.
function State:ToSending(...)
    self:Transition(self.STATES.SENDING, ...)
end

--- Transition to STALLED state.
function State:ToStalled(...)
    self:Transition(self.STATES.STALLED, ...)
end

--- Transition to LOCKDOWN state.
function State:ToLockdown(...)
    self:Transition(self.STATES.LOCKDOWN, ...)
end
