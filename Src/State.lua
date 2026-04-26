--[[
    State.lua
    Centralised state machine for Yapper.
    Manages the lifecycle and transitions between different operational modes.
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

-- Current active state.
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
    -- Check session flags first.
    if self._flags[name] ~= nil then
        return self._flags[name]
    end

    -- Check persistent flags in config if available.
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

    -- Stack inspection for 'blame' attribution.
    -- We skip 2 levels: Transition -> ToIdle/etc -> [Real Source]
    local stack = debugstack(2, 1, 0)
    local file, line, func

    if stack then
        -- Peeking: check if we are inside a semantic helper (case-insensitive).
        local s = stack:lower()
        if s:find("idle") or s:find("editing") or s:find("multiline") or 
           s:find("sending") or s:find("stalled") or s:find("lockdown") 
        then
            stack = debugstack(3, 1, 0)
        end
    end

    if stack then
        -- Capture filename, line, and function name from the stack frame.
        -- debugstack often returns: .../File.lua:LINE: in function <.../File.lua:LINE>
        file, line, func = stack:match("(.-%.lua)%]:(%d+):?%s*.-['<]([^'>]+)['>]")
        if not file then
            file, line = stack:match("(.-%.lua)%]:(%d+)")
        end
        if file then
            file = file:match("([^/\\]+)$") or file
        end
        if func then
            -- If func is a file path (common for anonymous functions), strip it to just the basename.
            func = func:match("([^/\\]+)$") or func
        end
    end

    -- Always record the transition in our local history buffer.
    self:_PushLog(oldState, newState, file, func, line)

    -- Deferred save to YapperDB when we return to a resting state.
    if newState == self.STATES.IDLE then
        self:_ScheduleSave()
    end

    -- Optional chat-frame logging if Verbose mode is enabled.
    local config = YapperTable.Config
    if config and config.System and config.System.VERBOSE then
        local utils = YapperTable.Utils
        if utils and type(utils.VerbosePrint) == "function" then
            -- Fetch the latest log from our own API to prove it works.
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

    -- Emit state change event via API if available.
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

--- Is the machine in INITIALISING state?
--- @return boolean
function State:IsInitialising()
    return self._current == self.STATES.INITIALISING
end

--- Has the machine completed initialisation (i.e. not in INITIALISING state)?
--- @return boolean
function State:IsInitialised()
    return self._current ~= self.STATES.INITIALISING
end

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

--- Is the settings/interface window open?
--- @return boolean
function State:IsConfig()
    return self._current == self.STATES.CONFIG
end

--- Helper: is the user currently typing (either overlay or multiline)?
--- @return boolean
function State:IsInputActive()
    return self:IsEditing() or self:IsMultiline()
end

--- Helper: is the addon busy (sending, stalled, or in lockdown)?
--- @return boolean
function State:IsBusy()
    local busy = self:IsSending() or self:IsStalled() or self:IsLockdown()
    
    -- Also check external delivery pipelines (GopherBridge)
    if not busy and YapperTable.GopherBridge and type(YapperTable.GopherBridge.IsBusy) == "function" then
        busy = YapperTable.GopherBridge:IsBusy()
    end
    
    return busy
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
function State:ToLockdown()
    self:Transition(self.STATES.LOCKDOWN)
end

--- Transition to CONFIG (settings) state.
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
            -- Initialise StateLogs table if missing
            config.System.StateLogs = config.System.StateLogs or {}
            
            -- We don't want to just append infinitely in the DB.
            -- We'll mirror our local buffer to the DB.
            -- This ensures the DB always has the LATEST 200 changes.
            -- We wipe and re-fill to keep it clean.
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

-- ---------------------------------------------------------------------------
