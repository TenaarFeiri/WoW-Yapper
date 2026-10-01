--[[
    State.lua
    State machine for the addon's operational modes.
]]

local _, YapperTable = ...

local State = {
    _current = "INITIALISING",
    _logBuffer = {}, -- local circular buffer
    _flags = {},     -- session-based flags
    _saveScheduled = false,
    MAX_LOGS = 200,
}
YapperTable.State = State

--- @enum States
State.STATES = {
    INITIALISING = "INITIALISING", -- Addon is booting or reloading UI.
    IDLE         = "IDLE",         -- Overlay hidden, no active send or queue.
    EDITING      = "EDITING",      -- Single-line overlay is shown and focused.
    MULTILINE    = "MULTILINE",    -- Expanded storyteller editor is active.
    SENDING      = "SENDING",      -- Message is being processed or sent (chunking/router).
    STALLED      = "STALLED",      -- Queue is waiting for user hardware input to continue.
    LOCKDOWN     = "LOCKDOWN",     -- Combat or M+ handoff: overlay hidden, handed back to Blizzard.
    CONFIG       = "CONFIG",       -- Settings/Interface window is open.
}

State._current = State.STATES.INITIALISING

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

--- Get a state flag value.
--- @param name string
--- @param default any
--- @return any
function State:GetFlag(name, default)
    -- Session flags win over persisted config flags.
    if self._flags[name] ~= nil then
        return self._flags[name]
    end

    local config = YapperTable.Config
    if config and config.System and config.System.StateFlags then
        if config.System.StateFlags[name] ~= nil then
            return config.System.StateFlags[name]
        end
    end

    return default
end

--- Set a state flag value.
--- @param name string
--- @param value any
--- @param persistent boolean? If true, value is stored in SavedVariables.
function State:SetFlag(name, value, persistent)
    self._flags[name] = value

    if persistent then
        local config = YapperTable.Config
        if config and config.System then
            config.System.StateFlags = config.System.StateFlags or {}
            config.System.StateFlags[name] = value
            self:_ScheduleSave()
        end
    end
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

    -- 'Blame' attribution via stack inspection (DEBUG only).
    -- Skip 2 levels: Transition -> ToIdle/etc -> [Real Source]
    local file, line, func
    local config = YapperTable.Config
    if config and config.System and config.System.DEBUG then
        if type(debug) == "table" and type(debug.getinfo) == "function" then
            local level = 3 -- Skip Transition -> semantic helper -> real source
            local info = debug.getinfo(level, "nSl")
            
            -- Skip an extra level if the caller was a semantic helper
            if info then
                local name = (info.name or ""):lower()
                if name:find("idle") or name:find("editing") or name:find("multiline") or
                   name:find("sending") or name:find("stalled") or name:find("lockdown") then
                    info = debug.getinfo(level + 1, "nSl")
                end
            end
            
            if info then
                file = info.short_src and info.short_src:match("([^/\\]+)$") or info.short_src
                line = info.currentline
                func = info.name or "anonymous"
            end
        end
    end

    self:_PushLog(oldState, newState, file, func, line)

    -- IDLE is a resting state: persist the log.
    if newState == self.STATES.IDLE then
        self:_ScheduleSave()
    end

    -- Optional chat-frame logging if Verbose mode is enabled.
    local config = YapperTable.Config
    if config and config.System and config.System.VERBOSE then
        local utils = YapperTable.Utils
        if utils and type(utils.VerbosePrint) == "function" then
            local last = self:GetLog(self:GetLogCount())
            if last then
                local blame
                if last.func and last.func ~= "anonymous" then
                    blame = ("%s:%s (%s)"):format(last.file or "unknown", last.line or "?", last.func)
                else
                    blame = ("%s:%s"):format(last.file or "unknown", last.line or "?")
                end
                local ts = last.time or date("%H:%M:%S")
                utils:VerbosePrint("info", "STATE", ("|cFF888888[%s]|r |cFF00FF00%s|r -> |cFFFFFF00%s|r [|cFF66CCFF%s|r]"):format(ts, last.old, last.new, blame))
            end
        end
    end

    if YapperTable.API and type(YapperTable.API.Fire) == "function" then
        YapperTable.API:Fire("STATE_CHANGED", newState, oldState, ...)
    end
end

--- Reset the state machine to IDLE.
function State:Reset()
    self:Transition(self.STATES.IDLE)
end

-- ---------------------------------------------------------------------------
-- Semantic Helpers (Readable State Checks)
-- ---------------------------------------------------------------------------

--- @return boolean
function State:IsInitialising()
    return self._current == self.STATES.INITIALISING
end

--- True once boot has finished (anything but INITIALISING).
--- @return boolean
function State:IsInitialised()
    return self._current ~= self.STATES.INITIALISING
end

--- @return boolean
function State:IsIdle()
    return self._current == self.STATES.IDLE
end

--- @return boolean
function State:IsEditing()
    return self._current == self.STATES.EDITING
end

--- @return boolean
function State:IsMultiline()
    return self._current == self.STATES.MULTILINE
end

--- @return boolean
function State:IsSending()
    return self._current == self.STATES.SENDING
end

--- @return boolean
function State:IsStalled()
    return self._current == self.STATES.STALLED
end

--- @return boolean
function State:IsLockdown()
    return self._current == self.STATES.LOCKDOWN
end

--- @return boolean
function State:IsConfig()
    return self._current == self.STATES.CONFIG
end

--- True while typing in either the overlay or the multiline editor.
--- @return boolean
function State:IsInputActive()
    return self:IsEditing() or self:IsMultiline()
end

--- True while sending, stalled, or in lockdown.
--- @return boolean
function State:IsBusy()
    return self:IsSending() or self:IsStalled() or self:IsLockdown()
end

-- ---------------------------------------------------------------------------
-- Semantic Transitions
-- ---------------------------------------------------------------------------

function State:ToIdle(...)
    self:Transition(self.STATES.IDLE, ...)
end

function State:ToEditing(...)
    self:Transition(self.STATES.EDITING, ...)
end

function State:ToMultiline(...)
    self:Transition(self.STATES.MULTILINE, ...)
end

function State:ToSending(...)
    self:Transition(self.STATES.SENDING, ...)
end

function State:ToStalled(...)
    self:Transition(self.STATES.STALLED, ...)
end

function State:ToLockdown()
    self:Transition(self.STATES.LOCKDOWN)
end

function State:ToConfig()
    self:Transition(self.STATES.CONFIG)
end

-- ---------------------------------------------------------------------------
-- Logging Internals
-- ---------------------------------------------------------------------------

--- Add a transition to the local circular buffer.
--- @param oldState string
--- @param newState string
--- @param file string|nil
--- @param func string|nil
--- @param line string|nil
function State:_PushLog(oldState, newState, file, func, line)
    local entry = {
        time = date("%H:%M:%S"),
        old  = oldState,
        new  = newState,
        file = file,
        func = func,
        line = line,
    }

    table.insert(self._logBuffer, entry)
    
    if #self._logBuffer > self.MAX_LOGS then
        table.remove(self._logBuffer, 1)
    end
end

--- Schedule a save to the persistent YapperDB at the end of the frame.
function State:_ScheduleSave()
    if self._saveScheduled then return end
    self._saveScheduled = true

    C_Timer.After(0, function()
        self._saveScheduled = false
        local config = YapperTable.Config
        if config and config.System then
            -- Mirror the buffer into the DB: wipe + refill keeps only the
            -- latest MAX_LOGS entries instead of appending forever.
            config.System.StateLogs = config.System.StateLogs or {}
            wipe(config.System.StateLogs)
            for i, entry in ipairs(self._logBuffer) do
                config.System.StateLogs[i] = entry
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Public Inspection API
-- ---------------------------------------------------------------------------

--- Get the current number of logs in the buffer.
--- @return number
function State:GetLogCount()
    return #self._logBuffer
end

--- Get a log entry by index.
--- @param index number
--- @return table|nil
function State:GetLog(index)
    return self._logBuffer[index]
end

--- Get the entire log buffer.
--- @return table
function State:GetLogs()
    return self._logBuffer
end
