--[[
===========================================================================
    Yapper Public API  (Src/API.lua)
===========================================================================
    This file creates `_G.YapperAPI`, a safe, public-facing object that
    lets other addons hook into Yapper without touching internal tables.

    Technical documentation is available in:
    https://github.com/TenaarFeiri/WoW-Yapper/tree/main/Documentation

    A plain-text reference is also available in:
    Src/API_Documentation.txt
===========================================================================
]]

local _, YapperTable = ...

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local API                     = {}
YapperTable.API               = API

local filters                 = {} -- [hookPoint] = sorted array of {cb, priority, handle}
local callbacks               = {} -- [event]     = array of {cb, handle}
local handleSeq               = 0  -- monotonic handle counter
-- Canonical filter hook points; unknown names are rejected (aliases resolve first).
local VALID_FILTERS = {
    PRE_EDITBOX_SHOW        = true, -- {chatType, target} -> payload|false; suppress overlay open
    PRE_EDITBOX_LABEL       = true, -- {chatType, target, channelName, label, unit} -> payload|false; mutate label text
    PRE_MULTILINE_SHOW      = true, -- {text, chatType, language, target} -> payload|false; block/modify multiline open
    PRE_SEND                = true, -- {text, chatType, language, target} -> payload|false; rewrite or block send
    PRE_CHUNK               = true, -- {text, limit, chatType, language}; may set continuationPrefix[First]
    PRE_SPELLCHECK          = true, -- {text} -> payload|false; skip spellcheck for this text
    PRE_SPELLCHECK_SUGGESTIONS = true, -- {word, suggestions, locale} -> payload|false; reorder/filter suggestions
    PRE_DELIVER             = true, -- {text, chatType, language, target} -> payload|false; claim message (delegation)
    PRE_ICON_GALLERY_SHOW   = true, -- {rawEditBox, query} -> payload|false; suppress or alter gallery open
}

-- Canonical callback event names; unknown names are rejected (aliases resolve first).
local VALID_CALLBACKS = {
    POST_SEND                       = true, -- (text, chatType, language, target) after message sent
    POST_CLAIMED                    = true, -- (handle, text, chatType, language, target) PRE_DELIVER claimed a msg
    CONFIG_CHANGED                  = true, -- (path, value) a Yapper setting changed
    STATE_CHANGED                   = true, -- (newState, oldState, ...) state machine transitioned
    EDITBOX_SHOW                    = true, -- (chatType, target) overlay became visible
    EDITBOX_HIDE                    = true, -- () overlay hidden
    EDITBOX_TEXT_CHANGED            = true, -- (text, isUserInput, box) editbox content modified
    EDITBOX_CHANNEL_CHANGED         = true, -- (chatType, target) user switched chat channel
    EDITBOX_LABEL_UPDATED           = true, -- (label, r, g, b) UI label refreshed
    THEME_CHANGED                   = true, -- (themeName) active theme changed
    SPELLCHECK_SUGGESTION           = true, -- (word, suggestions) suggestion popup shown
    SPELLCHECK_SUGGESTION_HIGHLIGHTED = true, -- (text, index, total) suggestion highlighted
    SPELLCHECK_APPLIED              = true, -- (original, replacement) user accepted a suggestion
    SPELLCHECK_CLOSED               = true, -- () suggestion tooltip closed
    SPELLCHECK_WORD_ADDED           = true, -- (word, locale) word added to user dictionary
    SPELLCHECK_WORD_IGNORED         = true, -- (word, locale) word marked as ignored
    YAS_WORD_LEARNED                = true, -- (word, locale) YAS auto-promoted a word
    AUTOCORRECT_APPLIED             = true, -- (original, replacement) autocorrect rewrote a word
    QUEUE_STALL                     = true, -- (chatType, policyClass, chunksRemaining) ack stall detected
    QUEUE_COMPLETE                  = true, -- () queue finished delivering all chunks
    ICON_GALLERY_SHOW               = true, -- (query) raid-icon gallery opened
    ICON_GALLERY_HIDE               = true, -- () raid-icon gallery closed
    ICON_GALLERY_SELECT             = true, -- (index, text, code) user picked a raid icon
    STRINGS_UPDATED                 = true, -- (locale) an addon registered/overwrote locale strings
    API_ERROR                       = true, -- (kind, hook, handler_info, errorMessage, data, ...) handler faulted
}

-- Deprecated aliases: old name -> canonical name.
local FILTER_ALIASES = {}

local EVENT_ALIASES = {
    ["YALLM_WORD_LEARNED"] = "YAS_WORD_LEARNED",
}

-- Deprecated config dot-paths resolved by GetConfig (with a warning).
local CONFIG_KEY_ALIASES = {
    ["Spellcheck.UnderlineColor"] = "Spellcheck.MisspellingColour",
}

local type                    = type
local pairs                   = pairs
local ipairs                  = ipairs
local pcall                   = pcall
local unpack                  = unpack
local table_insert            = table.insert
local table_sort              = table.sort
local table_remove            = table.remove

-- ===== Debug / error helpers ==============================================================
local function _truncate_string(s, max)
    if type(s) ~= "string" then return s end
    max = max or 200
    if #s > max then
        return s:sub(1, max) .. "...[+" .. tostring(#s - max) .. " bytes]"
    end
    return s
end

-- Treat secret values as opaque in API error callbacks and debug output.
local function _is_secret_value(value)
    if value == nil then return false end

    local utils = YapperTable and YapperTable.Utils
    if utils and type(utils.IsSecret) == "function" then
        local ok, result = pcall(utils.IsSecret, utils, value)
        if ok and result == true then
            return true
        end
    end

    return type(value) == "string" and value:find("|K", 1, true) ~= nil
end

-- Deep-copy data crossing the API boundary. Functions and scalars stay
-- shared; nested tables don't.
local function _copy_value(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[key] = _copy_value(nested, seen)
    end
    return copy
end

-- Bounded, redacted snapshot for API_ERROR handlers: never pass live frames
-- or secret-bearing tables through the error channel.
local function _sanitize_error_value(value, depth, seen)
    if _is_secret_value(value) then return "<secret>" end

    local valueType = type(value)
    if valueType ~= "table" then return value end
    depth = depth or 2
    if depth <= 0 then return "<table>" end

    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true

    local copy = {}
    local count = 0
    for key, nested in pairs(value) do
        count = count + 1
        if count > 12 then
            copy["..."] = "truncated"
            break
        end
        copy[key] = _sanitize_error_value(nested, depth - 1, seen)
    end

    seen[value] = nil
    return copy
end

local function _serialize_value(val, depth, seen)
    if _is_secret_value(val) then return "<secret>" end
    depth = depth or 2
    seen = seen or {}
    local t = type(val)
    if t == "string" then
        return '"' .. _truncate_string(val, 200) .. '"'
    end
    if t == "number" or t == "boolean" or t == "nil" then
        return tostring(val)
    end
    if t == "function" then
        local info = nil
        if type(debug) == "table" and type(debug.getinfo) == "function" then
            local ok, info2 = pcall(debug.getinfo, val, "nS")
            if ok and info2 then info = info2 end
        end
        if info then
            return "<function:" .. (info.name or "?") .. ":" .. (info.short_src or "?") .. ">"
        end
        return "<function>"
    end
    if t == "table" then
        if seen[val] then return "<cycle>" end
        if depth <= 0 then return "<table>" end
        seen[val] = true
        local parts = {}
        local n = 0
        for k, v in pairs(val) do
            n = n + 1
            if n > 12 then
                parts[#parts + 1] = "..."
                break
            end
            parts[#parts + 1] = "[" ..
                _serialize_value(k, depth - 1, seen) .. "]=" .. _serialize_value(v, depth - 1, seen)
        end
        seen[val] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "<" .. t .. ">"
end

local function _format_args(...)
    local n = select('#', ...)
    if n == 0 then return "" end
    local parts = {}
    for i = 1, n do
        parts[#parts + 1] = _serialize_value(select(i, ...), 2)
    end
    return table.concat(parts, ", ")
end

-- Emit `API_ERROR` directly (not via API:Fire) so a failing API_ERROR
-- handler can't trigger recursive error emissions.
local function _emit_error_event(kind, hook, failing_entry, err, payload_or_result, ...)
    local list = callbacks["API_ERROR"]
    if not list or #list == 0 then return false end

    -- Prefer handlers from the same owner as the failing handler, so
    -- unrelated addons aren't confused; fall back to all handlers.
    local targetOwner = failing_entry and failing_entry.owner or nil
    local candidates = {}
    if targetOwner then
        for _, ev in ipairs(list) do
            if ev.owner and ev.owner == targetOwner then
                table_insert(candidates, ev)
            end
        end
    end

    local tocall = candidates
    if not tocall or #tocall == 0 then
        tocall = list
    end

    local safePayload = _sanitize_error_value(payload_or_result, 2)
    local argCount = select('#', ...)
    local safeArgs = {}
    for i = 1, argCount do
        safeArgs[i] = _sanitize_error_value(select(i, ...), 2)
    end

    for _, ev in ipairs(tocall) do
        local ok, e = pcall(ev.cb,
            kind,
            hook,
            (failing_entry and { handle = failing_entry.handle, priority = failing_entry.priority, owner = failing_entry.owner } or nil),
            err,
            safePayload,
            unpack(safeArgs, 1, argCount))
        if not ok then
            if YapperTable and YapperTable.Utils and YapperTable.Utils.DebugPrint then
                YapperTable.Utils:DebugPrint("YapperAPI: API_ERROR handler error: " .. tostring(e))
            else
                print("YapperAPI: API_ERROR handler error: " .. tostring(e))
            end
        end
    end

    return true
end

local function _report_api_error(kind, hook, entry, err, payload_or_result, ...)
    -- Prefer the structured API_ERROR event; fall back to a debug print when
    -- no handlers are registered so failures stay visible during development.
    local handled = _emit_error_event(kind, hook, entry, err, payload_or_result, ...)
    if handled then return end

    local msg = kind .. " error on '" .. tostring(hook) .. "'"
    if entry and type(entry.handle) ~= "nil" then
        msg = msg .. " (handle=" .. tostring(entry.handle) .. ", priority=" .. tostring(entry.priority) .. ")"
    end
    msg = msg .. ": " .. tostring(err)
    if payload_or_result ~= nil then
        msg = msg .. " | data=" .. _serialize_value(payload_or_result, 2)
    end
    local args = _format_args(...)
    if args ~= "" then
        msg = msg .. " | args=" .. args
    end
    if YapperTable and YapperTable.Utils and YapperTable.Utils.DebugPrint then
        YapperTable.Utils:DebugPrint("YapperAPI: " .. msg)
    else
        print("YapperAPI: " .. msg)
    end
end

-- ---------------------------------------------------------------------------
-- Handle allocator
-- ---------------------------------------------------------------------------
local function NextHandle()
    handleSeq = handleSeq + 1
    return handleSeq
end

-- ---------------------------------------------------------------------------
-- Public object (sandbox)
-- ---------------------------------------------------------------------------
local YapperAPI             = {}
_G.YapperAPI                = YapperAPI

-- Per-hook / per-event registration cap to prevent runaway leaks.
local MAX_FILTERS_PER_HOOK  = 50
local MAX_CALLBACKS_PER_EVT = 50

local function _optional_type(value, expected)
    return value == nil or type(value) == expected
end

local function _target_is_valid(value)
    local valueType = type(value)
    return value == nil or valueType == "string" or valueType == "number"
end

-- Filter callbacks run in pcall, but their returned payload is consumed
-- afterwards. Validate the fields each consumer relies on so malformed addon
-- output can't escape the sandbox and break the send/UI path.
local FILTER_VALIDATORS = {
    PRE_EDITBOX_SHOW = function(payload)
        return type(payload) == "table"
            and _optional_type(payload.chatType, "string")
            and _target_is_valid(payload.target)
    end,
    PRE_EDITBOX_LABEL = function(payload)
        return type(payload) == "table"
            and _optional_type(payload.chatType, "string")
            and _target_is_valid(payload.target)
            and _optional_type(payload.channelName, "string")
            and _optional_type(payload.label, "string")
            and _optional_type(payload.unit, "string")
    end,
    PRE_MULTILINE_SHOW = function(payload)
        return type(payload) == "table"
            and type(payload.text) == "string"
            and type(payload.chatType) == "string"
            and _target_is_valid(payload.target)
    end,
    PRE_SEND = function(payload)
        return type(payload) == "table"
            and type(payload.text) == "string"
            and type(payload.chatType) == "string"
            and _target_is_valid(payload.target)
    end,
    PRE_CHUNK = function(payload)
        return type(payload) == "table"
            and type(payload.text) == "string"
            and type(payload.limit) == "number"
            and _optional_type(payload.chatType, "string")
            and _optional_type(payload.continuationPrefix, "string")
            and _optional_type(payload.continuationPrefixFirst, "boolean")
    end,
    PRE_SPELLCHECK = function(payload)
        return type(payload) == "table" and type(payload.text) == "string"
    end,
    PRE_SPELLCHECK_SUGGESTIONS = function(payload)
        return type(payload) == "table"
            and type(payload.word) == "string"
            and type(payload.suggestions) == "table"
            and _optional_type(payload.locale, "string")
    end,
    PRE_DELIVER = function(payload)
        return type(payload) == "table"
            and type(payload.text) == "string"
            and type(payload.chatType) == "string"
            and _target_is_valid(payload.target)
    end,
    PRE_ICON_GALLERY_SHOW = function(payload)
        return type(payload) == "table"
            and type(payload.rawEditBox) == "table"
            and _optional_type(payload.query, "string")
    end,
}

local function _is_valid_filter_payload(hookPoint, payload)
    local validator = FILTER_VALIDATORS[hookPoint]
    return not validator or validator(payload)
end

-- Best-effort owner attribution: extract the AddOn folder name from the
-- caller's source path via debug.getinfo, else store short_src.  This is an
-- attribution aid, not a security boundary (Lua addons share one VM).
-- `stackLevel` is measured from INSIDE this helper: pcall(1) ->
-- _capture_caller_owner(2) -> registration method(3) -> caller(4).
local function _capture_caller_owner(stackLevel)
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
        return nil
    end
    local ok, reginfo = pcall(debug.getinfo, stackLevel, "S")
    if ok and reginfo then
        local src = reginfo.source or reginfo.short_src
        if type(src) == "string" then
            return src:match("AddOns[/\\]([^/\\]+)") or src
        end
    end
    return nil
end

-- Most payloads are scalar routing fields. Frame identity is preserved, but
-- nested suggestion data is copied so an erroring filter can't leave the
-- active suggestion list half-mutated.
local function _snapshot_filter_payload(hookPoint, payload)
    local snapshot = {}
    for key, value in pairs(payload) do
        if hookPoint == "PRE_SPELLCHECK_SUGGESTIONS" and key == "suggestions" then
            snapshot[key] = _copy_value(value)
        else
            snapshot[key] = value
        end
    end
    return snapshot
end

-- ===== FILTERS =============================================================

--- Register a filter for a hook point.
--- @param hookPoint string  The hook name (e.g. "PRE_SEND").
--- @param callback function  Receives a payload table, must return it or false.
--- @param priority number|nil  Lower fires first; default 10.
--- @return number|nil handle  Pass to UnregisterFilter to remove.
function YapperAPI:RegisterFilter(hookPoint, callback, priority)
    if type(hookPoint) ~= "string" or type(callback) ~= "function" then
        return nil
    end

    if not VALID_FILTERS[hookPoint] then
        local aliasTarget = FILTER_ALIASES[hookPoint]
        if aliasTarget then
            if YapperTable.Utils and YapperTable.Utils.Print then
                YapperTable.Utils:Print("warn", "RegisterFilter: \"" .. hookPoint .. "\" is deprecated, use \"" .. aliasTarget .. "\" instead.")
            end
            hookPoint = aliasTarget
        else
            if YapperTable.Utils and YapperTable.Utils.Print then
                YapperTable.Utils:Print("error", "RegisterFilter: unknown hook point \"" .. hookPoint .. "\". Registration rejected.")
            end
            return nil
        end
    end

    if not filters[hookPoint] then
        filters[hookPoint] = {}
    end

    if #filters[hookPoint] >= MAX_FILTERS_PER_HOOK then
        _report_api_error("FILTER", hookPoint, nil, "registration cap reached (" .. MAX_FILTERS_PER_HOOK .. " filters)")
        return nil
    end

    priority = type(priority) == "number" and priority or 10
    local handle = NextHandle()

    -- Owner attribution: level 4 reaches the caller through this helper.
    local owner = _capture_caller_owner(4)

    table_insert(filters[hookPoint], {
        cb       = callback,
        priority = priority,
        handle   = handle,
        owner    = owner,
    })

    -- Lower priority fires first; ties break on registration order.
    table_sort(filters[hookPoint], function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.handle < b.handle
    end)

    return handle
end

--- Remove a previously registered filter.
--- @param handle number  The handle returned by RegisterFilter.
function YapperAPI:UnregisterFilter(handle)
    if not handle then return end
    for _, list in pairs(filters) do
        for i = #list, 1, -1 do
            if list[i].handle == handle then
                table_remove(list, i)
                return
            end
        end
    end
end

-- ===== CALLBACKS ===========================================================

--- Register a callback for an event.
--- @param event string  The event name (e.g. "POST_SEND").
--- @param callback function  Receives event-specific arguments.
--- @return number|nil handle  Pass to UnregisterCallback to remove.
function YapperAPI:RegisterCallback(event, callback)
    if type(event) ~= "string" or type(callback) ~= "function" then
        return nil
    end

    local resolvedEvent = event
    if not VALID_CALLBACKS[event] then
        local aliasTarget = EVENT_ALIASES[event]
        if aliasTarget then
            if YapperTable.Utils and YapperTable.Utils.Print then
                YapperTable.Utils:Print("warn", "RegisterCallback: \"" .. event .. "\" is deprecated, use \"" .. aliasTarget .. "\" instead.")
            end
            resolvedEvent = aliasTarget
        else
            if YapperTable.Utils and YapperTable.Utils.Print then
                YapperTable.Utils:Print("error", "RegisterCallback: unknown event \"" .. event .. "\". Registration rejected.")
            end
            return nil
        end
    end

    if not callbacks[resolvedEvent] then
        callbacks[resolvedEvent] = {}
    end

    if #callbacks[resolvedEvent] >= MAX_CALLBACKS_PER_EVT then
        _report_api_error("CALLBACK", resolvedEvent, nil, "registration cap reached (" .. MAX_CALLBACKS_PER_EVT .. " callbacks)")
        return nil
    end

    local handle = NextHandle()

    -- Same owner capture as RegisterFilter.
    local owner = _capture_caller_owner(4)

    table_insert(callbacks[resolvedEvent], {
        cb     = callback,
        handle = handle,
        owner  = owner,
    })

    return handle
end

--- Remove a previously registered callback.
--- @param handle number  The handle returned by RegisterCallback.
function YapperAPI:UnregisterCallback(handle)
    if not handle then return end
    for _, list in pairs(callbacks) do
        for i = #list, 1, -1 do
            if list[i].handle == handle then
                table_remove(list, i)
                return
            end
        end
    end
end

-- ===== READ-ONLY ACCESSORS =================================================

--- Returns the addon metadata version string, or "unknown" if unavailable.
--- API compatibility should be feature-detected rather than inferred from it.
function YapperAPI:GetVersion()
    if YapperTable.Core and YapperTable.Core.GetVersion then
        return YapperTable.Core:GetVersion()
    end
    return "unknown"
end

--- Returns the name of the currently active theme, or nil.
function YapperAPI:GetCurrentTheme()
    if YapperTable.Theme and YapperTable.Theme.GetCurrentName then
        return YapperTable.Theme:GetCurrentName()
    end
    if YapperTable.Theme and YapperTable.Theme._current then
        return YapperTable.Theme._current
    end
    return nil
end

--- Returns true if the Yapper overlay editbox is currently shown.
function YapperAPI:IsOverlayShown()
    local eb = YapperTable.EditBox
    if eb and eb.Overlay and eb.Overlay.IsShown then
        return eb.Overlay:IsShown() == true
    end
    return false
end

--- Force Yapper to close and open the original Blizzard editbox.
--- Equivalent to the "Bypass Yapper" keybind (Shift-Enter).
function YapperAPI:OpenBlizzardChat()
    if YapperTable.EditBox and YapperTable.EditBox.OpenBlizzardChat then
        YapperTable.EditBox:OpenBlizzardChat()
    end
end

--- Read a config value by dot-path (e.g. "EditBox.FontSize").
--- Tables are deep-copied to prevent mutation of live config.
function YapperAPI:GetConfig(path)
    if type(path) ~= "string" then return nil end
    local aliasTarget = CONFIG_KEY_ALIASES[path]
    if aliasTarget then
        -- Deprecated alias: allow with a warning (same as EVENT_ALIASES).
        if YapperTable.Utils and YapperTable.Utils.Print then
            YapperTable.Utils:Print("warn", "GetConfig: \"" .. path .. "\" is deprecated, use \"" .. aliasTarget .. "\" instead.")
        end
        path = aliasTarget
    end
    local cfg = YapperTable.Config
    if type(cfg) ~= "table" then return nil end

    for key in path:gmatch("[^%.]+") do
        if type(cfg) ~= "table" then return nil end
        cfg = cfg[key]
    end

    -- Deep-copy so callers can't mutate live config (incl. nested tables).
    if type(cfg) == "table" then
        return _copy_value(cfg)
    end

    return cfg
end

--- Delineator accessor for chat-tracking addons (e.g. Eavesdropper).
--- Used internally too, so a break here gets noticed fast.
function YapperAPI:GetDelineator()
    local chat = YapperTable.Config and YapperTable.Config.Chat
    if type(chat) ~= "table" then return nil end
    return chat.DELINEATOR or chat.PREFIX
end

-- ===== STATE ACCESSORS =====================================================

--- Returns the current state name (e.g. "IDLE", "SENDING").
function YapperAPI:GetState()
    if YapperTable.State and YapperTable.State.Get then
        return YapperTable.State:Get()
    end
    return "UNKNOWN"
end

--- Returns true if the machine is in the specified state.
--- @param state string
function YapperAPI:IsState(state)
    if type(state) ~= "string" then return false end
    if YapperTable.State and YapperTable.State.Is then
        return YapperTable.State:Is(state)
    end
    return false
end

--- Returns a list of all valid state names.
function YapperAPI:GetStates()
    if YapperTable.State and YapperTable.State.STATES then
        local out = {}
        for name in pairs(YapperTable.State.STATES) do
            table_insert(out, name)
        end
        table_sort(out)
        return out
    end
    return {}
end

--- Get the full history of state changes (capped at 200).
--- @return table
function YapperAPI:GetStateLogs()
    if YapperTable.State and YapperTable.State.GetLogs then
        return _copy_value(YapperTable.State:GetLogs())
    end
    return {}
end

--- Get a specific state change log by index.
--- @param index number
--- @return table|nil
function YapperAPI:GetStateLog(index)
    if YapperTable.State and YapperTable.State.GetLog then
        return _copy_value(YapperTable.State:GetLog(index))
    end
    return nil
end

--- Get the number of logs currently in the buffer.
--- @return number
function YapperAPI:GetStateLogCount()
    if YapperTable.State and YapperTable.State.GetLogCount then
        return YapperTable.State:GetLogCount()
    end
    return 0
end

local setStateDeprecationWarned = false

local function _is_internal_yapper_call()
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
        return false
    end

    local ok, info = pcall(debug.getinfo, 2, "S")
    local source = ok and info and (info.source or info.short_src) or nil
    if type(source) ~= "string" then return false end

    return source:find("[/\\\\]Src[/\\\\]") ~= nil
        or source:find("[/\\\\]WoW%-Yapper[/\\\\]") ~= nil
end

--- Transition the state machine to a new state.
--- Deprecated: direct state mutation is retained for compatibility only.
--- Use with caution: forcing states may bypass safety logic or cause UI desync.
--- @param stateName string  One of "IDLE", "EDITING", "MULTILINE", etc.
--- @param ... any          Metadata to pass to the state machine and observers.
function YapperAPI:SetState(stateName, ...)
    if not _is_internal_yapper_call() and not setStateDeprecationWarned then
        setStateDeprecationWarned = true
        local message = "YapperAPI:SetState is deprecated and will be removed from the stable API; avoid new usage and prefer feature detection."
        if YapperTable.Utils and YapperTable.Utils.Print then
            YapperTable.Utils:Print("warn", message)
        end
        _report_api_error("deprecated", "SetState", nil, message)
    end

    if type(stateName) ~= "string" then return false end
    local s = YapperTable.State
    if s and s.STATES and s.STATES[stateName] and type(s.Transition) == "function" then
        s:Transition(stateName, ...)
        return true
    end
    return false
end

--- Returns a table mapping internal frame names to their WoW frame objects.
--- Useful for addons that need to re-parent or
--- restyle Yapper's UI components without relying on global names.
function YapperAPI:ListFrames()
    local out = {}
    local registry = YapperTable.Core and YapperTable.Core.UI and YapperTable.Core.UI.Frames
    if not registry then return out end

    -- Map categorized registry to the flat API keys for backward compatibility.
    if registry.Overlay then
        out.Overlay     = registry.Overlay.Frame
        out.OverlayEdit = registry.Overlay.EditBox
        out.LabelBg     = registry.Overlay.LabelBg
    end

    if registry.Spellcheck then
        out.SuggestionFrame        = registry.Spellcheck.SuggestionFrame
        out.HintFrame              = registry.Spellcheck.HintFrame
        out.SuggestionClickCatcher = registry.Spellcheck.SuggestionClickCatcher
    end

    if registry.Multiline then
        out.MultilineFrame  = registry.Multiline.Frame
        out.MultilineEdit   = registry.Multiline.EditBox
        out.MultilineScroll = registry.Multiline.ScrollFrame
    end

    -- Full categorized registry for advanced usage.
    out.All = registry

    return out
end

-- ===== SPELLCHECK ACCESSORS ================================================

--- Returns true if the spellcheck system is loaded and enabled.
function YapperAPI:IsSpellcheckEnabled()
    local sc = YapperTable.Spellcheck
    if sc and sc.IsEnabled then
        return sc:IsEnabled() == true
    end
    return false
end

--- Returns true if `word` is recognised by the active dictionary or user dict.
function YapperAPI:CheckWord(word)
    if type(word) ~= "string" or word == "" then return false end
    local sc = YapperTable.Spellcheck
    if sc and sc.IsWordCorrect then
        return sc:IsWordCorrect(word) == true
    end
    return false
end

--- Returns an array of suggestion strings for a misspelled word, or nil.
function YapperAPI:GetSuggestions(word)
    if type(word) ~= "string" or word == "" then return nil end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.GetSuggestions then return nil end

    local ok, results = pcall(sc.GetSuggestions, sc, word)
    if not ok or type(results) ~= "table" then return nil end

    -- Return only the word strings, not internal scoring data.
    local out = {}
    for i, entry in ipairs(results) do
        if type(entry) == "table" then
            out[i] = entry.word or entry.value or tostring(entry)
        else
            out[i] = tostring(entry)
        end
    end
    return #out > 0 and out or nil
end

--- Returns the current spellcheck locale (e.g. "enUS"), or nil.
function YapperAPI:GetSpellcheckLocale()
    local sc = YapperTable.Spellcheck
    if sc and sc.GetLocale then
        return sc:GetLocale()
    end
    return nil
end

--- Adds a word to the user dictionary for the current locale.
--- Returns true on success.
function YapperAPI:AddToDictionary(word)
    if type(word) ~= "string" or word == "" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.AddUserWord or not sc.GetLocale then return false end
    local locale = sc:GetLocale()
    if not locale then return false end
    sc:AddUserWord(locale, word)
    -- SPELLCHECK_WORD_ADDED is fired by AddUserWord internally.
    return true
end

--- Marks a word as ignored for the current locale.
--- Returns true on success.
function YapperAPI:IgnoreWord(word)
    if type(word) ~= "string" or word == "" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.IgnoreWord or not sc.GetLocale then return false end
    local locale = sc:GetLocale()
    if not locale then return false end
    sc:IgnoreWord(locale, word)
    -- SPELLCHECK_WORD_IGNORED is fired by IgnoreWord internally.
    return true
end

--- Returns true if the spellcheck suggestion panel is currently visible.
function YapperAPI:IsSuggestionOpen()
    local sc = YapperTable.Spellcheck
    if sc and sc.IsSuggestionOpen then
        return sc:IsSuggestionOpen() == true
    end
    return false
end

--- Closes the spellcheck suggestion panel.
function YapperAPI:HideSuggestions()
    local sc = YapperTable.Spellcheck
    if sc and sc.HideSuggestions then
        sc:HideSuggestions()
        return true
    end
    return false
end

--- Applies a suggestion from the current list by its 1-indexed row.
--- @param index number  1-6
function YapperAPI:ApplySuggestion(index)
    if type(index) ~= "number" then return false end
    local sc = YapperTable.Spellcheck
    if sc and sc.ApplySuggestion then
        sc:ApplySuggestion(index)
        return true
    end
    return false
end

--- Scans a block of text and returns a list of misspelled word ranges.
--- @param text string  The text to scan.
--- @return table[]|nil  Array of { startPos, endPos, word } or nil.
function YapperAPI:FindMisspellings(text)
    if type(text) ~= "string" or text == "" then return nil end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.IsEnabled or not sc:IsEnabled() then return nil end

    local dict = sc:GetDictionary()
    if not dict then return nil end

    local ok, results = pcall(sc.CollectMisspellings, sc, text, dict)
    if not ok or type(results) ~= "table" then return nil end

    return #results > 0 and results or nil
end

--- Register a dictionary via the public API.
--- `locale` -- locale key, e.g. "enBase", "enGB", "enUS".
--- `data`   -- dictionary table or lazy builder function. Tables accept the
---             fields used by RegisterDictionary (words, phonetics, extends,
---             languageFamily, affixRules, and an optional embedded engine).
--- Every dictionary must resolve to a languageFamily whose engine is
--- already registered and contract-valid; there is no silent default.
--- Returns true when dispatch completes without a Lua error. Internal
--- contract/security validation may still reject the dictionary data.
function YapperAPI:RegisterDictionary(locale, data)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(data) ~= "table" and type(data) ~= "function" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.RegisterDictionary then return false end
    local owner = _capture_caller_owner(4)
    local ok, err = pcall(sc.RegisterDictionary, sc, locale, data, owner)
    if not ok then
        _report_api_error("RegisterDictionary", locale, nil, err, { locale = locale })
        return false
    end
    return true
end

--- Register a language engine for a locale family.
--- `familyId` -- short string id, e.g. "en", "de", "fr".
--- `engine`   -- table implementing the engine contract (see
---             Documentation/Dictionaries.md): NormaliseWord, NormaliseVowels,
---             GetPhoneticHash, HashWord, BlockedHashes, WordBytes and
---             WordStartBytes are required; StripAffixes, ShouldCheckWord,
---             MatchCase, IsSaneWord, VariantRules, ScoreWeights, KBLayouts,
---             DefaultLayout, Locales and DisplayName are optional.
--- The engine table is deep-copied, strictly validated (type, shape and
--  limit checks plus runtime probes), and owner-locked: once a family is
--- claimed by an addon, only that addon may re-register it. A runtime error
--- inside engine code purges the engine and all bound dictionaries.
--- Returns true on success, false on invalid arguments or failed validation.
function YapperAPI:RegisterLanguageEngine(familyId, engine)
    if type(familyId) ~= "string" or familyId == "" then return false end
    if type(engine) ~= "table" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc._RegisterLanguageEngine then return false end
    local owner = _capture_caller_owner(4)
    local engineCopy = _copy_value(engine)
    local ok, result = pcall(sc._RegisterLanguageEngine, sc, familyId, engineCopy, owner)
    if not ok then
        _report_api_error("RegisterLanguageEngine", familyId, nil, result, { familyId = familyId })
        return false
    end
    return result == true
end

--- Register UI strings for a locale.  `tbl` is a sparse map of canonical
--- string keys (see Src/Strings.lua `Strings._enUS` for the key list) to
--- translated text; missing keys fall back to English.  Owner-captured like
--- engine registration: re-registering from the same addon replaces that
--- addon's contribution wholesale.  Fires STRINGS_UPDATED on success.
--- enUS itself is core-owned and cannot be overridden.
--- Returns true on success, false on invalid input or failed validation.
function YapperAPI:RegisterStrings(locale, tbl)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(tbl) ~= "table" then return false end
    local strings = YapperTable.Strings
    if not strings or not strings.Register then return false end
    local owner = _capture_caller_owner(4)
    local ok, result, err = pcall(strings.Register, strings, locale, tbl, owner)
    if not ok then
        _report_api_error("RegisterStrings", locale, nil, result, { locale = locale })
        return false
    end
    if result ~= true and type(err) == "string" and YapperTable.Utils and YapperTable.Utils.Print then
        YapperTable.Utils:Print("error", "RegisterStrings: " .. err)
    end
    return result == true
end

--- Resolve a UI string for the active client locale, with enUS fallback.
--- Extra args feed string.format.  Never returns nil: an unknown key
--- resolves to the key itself.
function YapperAPI:GetString(key, ...)
    local strings = YapperTable.Strings
    if not strings or not strings.Get then return tostring(key) end
    return strings:Get(key, ...)
end

--- Returns true if a language engine for `familyId` is registered.
function YapperAPI:IsLanguageEngineRegistered(familyId)
    if type(familyId) ~= "string" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.LanguageEngines then return false end
    return sc.LanguageEngines[familyId] ~= nil
end

--- Returns a copy of the language engine for `familyId`, or nil.
function YapperAPI:GetLanguageEngine(familyId)
    if type(familyId) ~= "string" then return nil end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.LanguageEngines then return nil end
    return _copy_value(sc.LanguageEngines[familyId])
end

--- Map a Load-On-Demand addon to a locale so Yapper knows what to load.
--- `locale`    -- e.g. "ptBR", "esES"
--- `addonName` -- e.g. "Yapper_Dict_pt"
function YapperAPI:RegisterLocaleAddon(locale, addonName)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(addonName) ~= "string" or addonName == "" then return false end

    local sc = YapperTable.Spellcheck
    if not sc then return false end

    sc.LocaleAddons = sc.LocaleAddons or {}
    sc.LocaleAddons[locale] = addonName

    -- Re-ensure if this locale was requested before the mapping existed or
    -- is currently active.
    if sc.GetLocale and sc:GetLocale() == locale then
        sc:EnsureLocale(locale)
    end
    return true
end

local registeredAtomicPatterns = {}

--- Register a custom Lua string pattern that the Yapper chunker should
--- treat as an unbreakable, atomic sequence (similar to a WoW hyperlink).
--- This is useful for plugins that inject raw pseudo-link text
--- (like [TRP3:Identifier]) that shouldn't be split across messages.
--- Returns true on success.
function YapperAPI:RegisterAtomicPattern(pattern)
    if type(pattern) ~= "string" or pattern == "" then return false end
    registeredAtomicPatterns[#registeredAtomicPatterns + 1] = pattern
    return true
end

--- Returns a copy of all registered atomic patterns.
function YapperAPI:GetRegisteredAtomicPatterns()
    return _copy_value(registeredAtomicPatterns)
end

--- Insert `text` at the current cursor position in the active Yapper
--- editbox.  The state machine is consulted to decide which box to target:
---   1. Multiline editor (when State:IsMultiline() is true)
---   2. Single-line overlay (when the overlay frame is visible)
--- Returns true if the text was inserted, false if no editbox is active.
function YapperAPI:InsertText(text)
    if type(text) ~= "string" or text == "" then return false end

    -- Multiline editor has priority: when active, the overlay is hidden.
    local ml = YapperTable.Multiline
    if ml and ml.EditBox and ml.Frame and ml.Frame:IsShown() then
        ml.EditBox:Insert(text)
        return true
    end

    local eb = YapperTable.EditBox
    if eb and eb.Overlay and eb.Overlay:IsShown() and eb.OverlayEdit then
        eb.OverlayEdit:Insert(text)
        return true
    end

    return false
end

--- Returns a snapshot of the current delivery queue state.
--- Fields: active (bool), stalled (bool), chatType (string|nil),
--- policyClass (string|nil), pending (int), inFlight (int).
function YapperAPI:GetQueueState()
    local q = YapperTable.Queue
    if not q or not q.GetActivePolicySnapshot then
        return { active = false, stalled = false, pending = 0, inFlight = 0 }
    end
    local snap = q:GetActivePolicySnapshot()
    snap.expectedAckEvent = nil -- internal event name; not part of the public contract
    return snap
end

--- Cancel the active delivery queue, discarding all pending chunks.
--- Prints a chat-frame notice matching the built-in cancel behaviour.
--- Returns the number of chunks that were discarded.
function YapperAPI:CancelQueue()
    local q = YapperTable.Queue
    if not q then return 0 end
    local count = #q.Entries + (q.PendingEntry and 1 or 0)
    if count == 0 then return 0 end
    q:Cancel()
    return count
end

-- ===== THEME MANAGEMENT ===================================================

--- Register a named theme.  `data` follows the same structure as Yapper's
--- built-in themes: inputBg, labelBg, textColor, borderColor (each {r,g,b,a}),
--- border (bool), allowRoundedCorners (bool), allowDropShadow (bool),
--- font ({path,size,flags}), and an optional OnApply hook.  The data is
--- copied before it enters the registry.
--- Returns true on success, false if name or data is invalid.
function YapperAPI:RegisterTheme(name, data)
    if type(name) ~= "string" or type(data) ~= "table" then return false end
    local th = YapperTable.Theme
    if not th then return false end
    return th:RegisterTheme(name, _copy_value(data)) == true
end

--- Activate a registered theme by name.  Persists the selection to
--- YapperLocalConf (same as selecting it in the Settings dialog).
--- Returns true on success.
function YapperAPI:SetTheme(name)
    if type(name) ~= "string" then return false end
    local th = YapperTable.Theme
    if not th then return false end
    return th:SetTheme(name) == true
end

--- Return an array of all registered theme names, sorted alphabetically.
function YapperAPI:GetRegisteredThemes()
    local th = YapperTable.Theme
    if not th then return {} end
    return th:GetRegisteredNames()
end

--- Return a deep copy of a registered theme's data table, or nil.
--- Pass no argument (or nil) to get the currently active theme.
function YapperAPI:GetTheme(name)
    local th = YapperTable.Theme
    if not th then return nil end
    local data = th:GetTheme(name)
    if type(data) ~= "table" then return nil end
    return _copy_value(data)
end

-- ===== UTILITY HELPERS =====================================================

--- Returns true if C_ChatInfo.InChatMessagingLockdown() is active.
function YapperAPI:IsChatLockdown()
    local u = YapperTable.Utils
    if u and u.IsChatLockdown then
        return u:IsChatLockdown() == true
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        return C_ChatInfo.InChatMessagingLockdown() == true
    end
    return false
end

--- Returns true if value should not be logged or persisted.
--- Uses Blizzard's secret value/table predicates with a |K token fallback.
function YapperAPI:IsSecret(value)
    local u = YapperTable.Utils
    if u and u.IsSecret then
        return u:IsSecret(value) == true
    end
    return false
end

--- Convert leetspeak characters back to their base alphabet equivalents.
--- @param word string
--- @return string
function YapperAPI:Deleet(word)
    local u = YapperTable.Utils
    if u and u.Deleet then
        return u.Deleet(word)
    end
    return word
end

--- Returns the correct UI parent frame for chat-related UI.
--- Respects fullscreen panels such as the housing editor.
function YapperAPI:GetChatParent()
    local u = YapperTable.Utils
    if u and u.GetChatParent then
        return u:GetChatParent()
    end
    return UIParent
end

--- Hooks frame so it re-parents automatically when the active fullscreen panel changes.
--- Keeps your frame visible over panels that hide UIParent (e.g. housing editor).
function YapperAPI:MakeFullscreenAware(frame)
    if type(frame) ~= "table" then return end
    local u = YapperTable.Utils
    if u and u.MakeFullscreenAware then
        u:MakeFullscreenAware(frame)
    end
end

-- ===== POST DELEGATION =====================================================

local DELEGATION_TIMEOUT = 5 -- seconds

-- claimHandle -> { text, chatType, language, target, owner, timer }
local activeClaims       = {}
local claimSeq           = 0

--- Internal: create a delegation claim when a PRE_DELIVER filter cancels.
--- Returns the claim handle.
local function _create_claim(text, chatType, language, target, owner)
    claimSeq = claimSeq + 1
    local handle = claimSeq

    local timer
    if C_Timer and C_Timer.NewTimer then
        timer = C_Timer.NewTimer(DELEGATION_TIMEOUT, function()
            local claim = activeClaims[handle]
            if not claim then return end
            activeClaims[handle] = nil

            -- Timeout: send it ourselves, then blame the addon.
            if YapperTable.Router then
                YapperTable.Router:Send(claim.text, claim.chatType, claim.language, claim.target)
            elseif C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(claim.text, claim.chatType, claim.language, claim.target)
            end

            API:Fire("POST_SEND", claim.text, claim.chatType, claim.language, claim.target)

            local blame = claim.owner or "unknown addon"
            local msg = "|cffff6666Yapper:|r Post delegation timed out — " ..
                "\"" .. blame .. "\" claimed a message but did not resolve within " ..
                DELEGATION_TIMEOUT .. "s.  Message was sent by Yapper."
            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage(msg)
            else
                print(msg)
            end

            _report_api_error("delegation-timeout", "PRE_DELIVER",
                { handle = handle, owner = claim.owner },
                "addon failed to resolve claimed post within timeout",
                { text = claim.text, chatType = claim.chatType })
        end)
    end

    activeClaims[handle] = {
        text     = text,
        chatType = chatType,
        language = language,
        target   = target,
        owner    = owner,
        timer    = timer,
    }

    return handle
end

--- Internal bridge: lets Chat.lua create delegation claims.
function API:_createClaim(text, chatType, language, target, owner)
    return _create_claim(text, chatType, language, target, owner)
end

--- Resolve a previously claimed post.  Call this from the addon that claimed
--- a message via a PRE_DELIVER filter returning false.
--- Returns true if the claim existed and was cleared.
function YapperAPI:ResolvePost(handle)
    if type(handle) ~= "number" then return false end
    local claim = activeClaims[handle]
    if not claim then return false end

    if claim.timer and claim.timer.Cancel then
        claim.timer:Cancel()
    end
    activeClaims[handle] = nil
    return true
end

-- ===== INTERNAL ENTRY POINTS ===============================================
-- These are called by Yapper's own modules.  Not on the public object.

-- ===== ICON GALLERY ========================================================

--- Show the raid-icon gallery anchored to an external EditBox widget.
--- editBox     -- the raw WoW EditBox the gallery writes into.
--- anchorFrame -- popup anchor (defaults to editBox when nil).
--- query       -- optional pre-filter (the word typed after "{").
function YapperAPI:ShowIconGallery(editBox, anchorFrame, query)
    local ig = YapperTable.IconGallery
    if not ig then return end
    if type(editBox) ~= "table" then return end
    ig:Show(editBox, anchorFrame or editBox, query or "")
end

--- Hide the raid-icon gallery.
function YapperAPI:HideIconGallery()
    local ig = YapperTable.IconGallery
    if ig then ig:Hide() end
end

--- Returns true when the raid-icon gallery is currently visible.
function YapperAPI:IsIconGalleryShown()
    local ig = YapperTable.IconGallery
    return ig ~= nil and ig.Active == true
end

--- Returns a copy of the raid-icon metadata table.
--- Each entry has: index (1-8), text (name), code ("rt1"..."rt8").
function YapperAPI:GetRaidIconData()
    local ig = YapperTable.IconGallery
    if not ig or not ig._GetIconMeta then return {} end
    local result = {}
    for i = 1, 8 do
        result[i] = ig:_GetIconMeta(i)
    end
    return result
end

-- ===== AUTOCOMPLETE & GHOST TEXT ============================================

--- Returns the best autocomplete suggestion for the given partial word.
---@param word string
---@return string|nil
function YapperAPI:GetAutocompleteSuggestion(word)
    local ac = YapperTable.Autocomplete
    if not ac or not ac.GetSuggestion then return nil end
    return ac:GetSuggestion(word)
end

--- Returns the current pixel offset of the cursor/caret within an EditBox.
--- Requires the EditBox to be one managed by Yapper (Overlay, Multiline, or hooked).
---@param editBox table
---@return number x, number y, number height (in logical pixels)
function YapperAPI:GetCaretOffset(editBox)
    local ac = YapperTable.Autocomplete
    if not ac then return 0, 0, 0 end

    -- If this is our hooked EditBox, we have cached coordinates.
    if ac._hookedEditBox == editBox then
        local uiScale = UIParent and UIParent:GetEffectiveScale() or 1
        local ebScale = editBox:GetEffectiveScale()
        local toUI    = ebScale / uiScale
        return (ac._caretX or 0) * toUI, (ac._caretY or 0) * toUI, (ac._caretH or 0) * toUI
    end

    return 0, 0, 0
end

--- Returns the shared FontString used for ghost text rendering.
---@return table|nil
function YapperAPI:GetGhostFrame()
    local ac = YapperTable.Autocomplete
    if not ac or not ac.GetGhostFS then return nil end
    return ac:GetGhostFS()
end

--- Manually show ghost text on a specific EditBox.
--- Useful for external addons that want to leverage Yapper's ghost renderer.
---@param text string
---@param editBox table
---@param prefix string|nil
---@param textUpToCursor string|nil
function YapperAPI:ShowGhostText(text, editBox, prefix, textUpToCursor)
    local ac = YapperTable.Autocomplete
    if not ac or not ac.ShowGhost then return end

    -- Temporarily bind this EditBox if it differs from the current one.
    local prevEB = ac._activeEditBox
    ac._activeEditBox = editBox

    -- No prefix: treat the entire text as the ghost suffix.
    ac:ShowGhost(text, prefix or "", textUpToCursor or prefix or "")

    ac._activeEditBox = prevEB
end

--- Hide the ghost text.
function YapperAPI:HideGhostText()
    local ac = YapperTable.Autocomplete
    if ac and ac.HideGhost then ac:HideGhost() end
end

--- Set a manual pixel offset for ghost text alignment.
--- Fixes vertical "dipping" or horizontal overlap in mutated EditBoxes.
---@param offsetX number
---@param offsetY number
function YapperAPI:SetGhostTextOffset(offsetX, offsetY)
    local ac = YapperTable.Autocomplete
    if ac and ac.SetOffset then
        ac:SetOffset(offsetX, offsetY)
    end
end

--- Force the ghost text to synchronise its font with its current parent EditBox.
function YapperAPI:SyncGhostTextFont()
    local ac = YapperTable.Autocomplete
    if ac and ac.SyncFont then
        ac:SyncFont()
    end
end

--- Set manual pixel offsets for spellcheck tooltips (hints and suggestion dropdowns).
---@param hintX number?
---@param hintY number?
---@param suggestX number?
---@param suggestY number?
function YapperAPI:SetSpellcheckTooltipOffset(hintX, hintY, suggestX, suggestY)
    local sc = YapperTable.Spellcheck
    if sc and sc.SetSpellcheckOffset then
        sc:SetSpellcheckOffset(hintX, hintY, suggestX, suggestY)
    end
end

--- Clear the spellcheck suggestion cache, forcing re-generation (and re-filtering)
--- on the next request. Useful for plugins that dynamically change suggestion lists.
function YapperAPI:ClearSuggestionCache()
    local sc = YapperTable.Spellcheck
    if sc and sc.ClearSuggestionCache then
        sc:ClearSuggestionCache()
        return true
    end
    return false
end

--- Run all filters for a hook point.
--- Returns the (possibly modified) payload, or false if cancelled.
--- If no filters are registered, returns the payload unchanged.
---
--- @param hookPoint string
--- @param payload table
--- @return table|false
function API:RunFilter(hookPoint, payload)
    local list = filters[hookPoint]
    if not list or #list == 0 then
        return payload
    end

    for _, entry in ipairs(list) do
        local snapshot = _snapshot_filter_payload(hookPoint, payload)
        local ok, result = pcall(entry.cb, payload)
        if not ok then
            -- Handler errored: restore the pre-handler payload, report, and
            -- continue with remaining filters.
            payload = snapshot
            _report_api_error("filter", hookPoint, entry, result, payload)
        elseif result == false then
            -- Explicit cancel; remember the owner for delegation tracking.
            self._lastCancelOwner = entry.owner
            return false
        elseif type(result) == "table" then
            if _is_valid_filter_payload(hookPoint, result) then
                payload = result
            else
                payload = snapshot
                _report_api_error("filter-return", hookPoint, entry,
                    "invalid payload returned by filter", result, payload)
            end
        elseif result ~= nil then
            -- Unexpected non-table return: restore in-place mutations and
            -- report without breaking the filter chain.
            payload = snapshot
            _report_api_error("filter-return", hookPoint, entry, "unexpected return value", result, payload)
        end
        -- nil return = "no change"; continue with the current payload.
    end

    self._lastCancelOwner = nil
    return payload
end

--- Fire all callbacks for an event.  Arguments are passed through.
--- Errors in external code are caught and logged; Yapper is never harmed.
---
--- @param event string
--- @param ... any
function API:Fire(event, ...)
    local resolvedEvent = EVENT_ALIASES[event] or event
    local list = callbacks[resolvedEvent]
    if not list or #list == 0 then
        return
    end

    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.cb, ...)
        if not ok then
            -- Handler errors must not propagate into Yapper.
            _report_api_error("callback", event, entry, err, nil, ...)
        end
    end
end

-- ===== SETTINGS CATEGORY API ================================================

local settingsCategories = {}
local MAX_SETTINGS_CATEGORIES = 20

--- Register a settings category in Yapper's settings window.
--- @param id string Unique identifier for the category
--- @param label string Display label for the sidebar button
--- @param options table Options table with optional fields:
---   - render: function(contentFrame, cursor) - Custom render callback
---   - schema: table - Schema of controls for Yapper to render
---   - internal: boolean - If true, marks as internal (hidden from plugin listing)
--- @return boolean success
function YapperAPI:RegisterSettingsCategory(id, label, options)
    if type(id) ~= "string" or id == "" then return false end
    if type(label) ~= "string" or label == "" then return false end
    if type(options) ~= "table" then return false end

    for _, cat in ipairs(settingsCategories) do
        if cat.id == id then return false end
    end

    if #settingsCategories >= MAX_SETTINGS_CATEGORIES then
        _report_api_error("SETTINGS", "RegisterSettingsCategory", nil, "category cap reached (" .. MAX_SETTINGS_CATEGORIES .. ")")
        return false end

    if options.render and type(options.render) ~= "function" then return false end
    if options.schema and type(options.schema) ~= "table" then return false end
    if not options.render and not options.schema and not options._internal then return false end

    table_insert(settingsCategories, {
        id = id,
        label = label,
        render = options.render,
        schema = options.schema,
        internal = options.internal == true,
        _internal = options._internal,
    })

    -- Interface shares this same table.
    local Interface = YapperTable.Interface
    if Interface then
        Interface._ALL_CATEGORIES = settingsCategories
    end

    return true
end

--- Unregister a previously registered settings category.
--- @param id string Category ID to unregister
function YapperAPI:UnregisterSettingsCategory(id)
    if type(id) ~= "string" then return end

    for i, cat in ipairs(settingsCategories) do
        if cat.id == id then
            table_remove(settingsCategories, i)
            local Interface = YapperTable.Interface
            if Interface then
                Interface._ALL_CATEGORIES = settingsCategories
            end
            return
        end
    end
end

--- Get a list of registered settings categories (excludes internal ones).
--- @return table[] Array of {id, label} tables
function YapperAPI:GetRegisteredSettingsCategories()
    local result = {}
    for _, cat in ipairs(settingsCategories) do
        if not cat.internal then
            table_insert(result, { id = cat.id, label = cat.label })
        end
    end
    return result
end

--- Open Yapper's settings window to a specific category.
--- @param id string Category ID to open
--- @return boolean success
function YapperAPI:OpenSettingsCategory(id)
    if type(id) ~= "string" then return false end

    local Interface = YapperTable.Interface
    if not Interface or not Interface.OpenToCategory then return false end

    Interface:OpenToCategory(id)
    return true
end

-- ===== GROUPED ALIASES =====================================================
-- Feature-detection-friendly aliases to the flat methods above. They share
-- the same function references rather than wrapping them.
YapperAPI.Filters = {
    RegisterFilter   = YapperAPI.RegisterFilter,
    UnregisterFilter = YapperAPI.UnregisterFilter,
}

YapperAPI.Callbacks = {
    RegisterCallback   = YapperAPI.RegisterCallback,
    UnregisterCallback = YapperAPI.UnregisterCallback,
}

YapperAPI.State = {
    GetState        = YapperAPI.GetState,
    IsState         = YapperAPI.IsState,
    GetStates       = YapperAPI.GetStates,
    GetStateLogs    = YapperAPI.GetStateLogs,
    GetStateLog     = YapperAPI.GetStateLog,
    GetStateLogCount = YapperAPI.GetStateLogCount,
    SetState        = YapperAPI.SetState,
}

YapperAPI.Chat = {
    GetDelineator   = YapperAPI.GetDelineator,
    InsertText      = YapperAPI.InsertText,
    GetQueueState   = YapperAPI.GetQueueState,
    CancelQueue     = YapperAPI.CancelQueue,
    ResolvePost     = YapperAPI.ResolvePost,
    RegisterAtomicPattern = YapperAPI.RegisterAtomicPattern,
    GetRegisteredAtomicPatterns = YapperAPI.GetRegisteredAtomicPatterns,
    OpenBlizzardChat = YapperAPI.OpenBlizzardChat,
}

YapperAPI.Spellcheck = {
    IsSpellcheckEnabled       = YapperAPI.IsSpellcheckEnabled,
    CheckWord                = YapperAPI.CheckWord,
    GetSuggestions           = YapperAPI.GetSuggestions,
    GetSpellcheckLocale      = YapperAPI.GetSpellcheckLocale,
    AddToDictionary          = YapperAPI.AddToDictionary,
    IgnoreWord               = YapperAPI.IgnoreWord,
    IsSuggestionOpen         = YapperAPI.IsSuggestionOpen,
    HideSuggestions          = YapperAPI.HideSuggestions,
    ApplySuggestion          = YapperAPI.ApplySuggestion,
    FindMisspellings         = YapperAPI.FindMisspellings,
    ClearSuggestionCache     = YapperAPI.ClearSuggestionCache,
    RegisterDictionary       = YapperAPI.RegisterDictionary,
    RegisterLanguageEngine   = YapperAPI.RegisterLanguageEngine,
    IsLanguageEngineRegistered = YapperAPI.IsLanguageEngineRegistered,
    GetLanguageEngine        = YapperAPI.GetLanguageEngine,
    RegisterLocaleAddon      = YapperAPI.RegisterLocaleAddon,
}

YapperAPI.Themes = {
    GetCurrentTheme    = YapperAPI.GetCurrentTheme,
    RegisterTheme      = YapperAPI.RegisterTheme,
    SetTheme           = YapperAPI.SetTheme,
    GetRegisteredThemes = YapperAPI.GetRegisteredThemes,
    GetTheme           = YapperAPI.GetTheme,
}

YapperAPI.UI = {
    IsOverlayShown       = YapperAPI.IsOverlayShown,
    ListFrames           = YapperAPI.ListFrames,
    RegisterStrings      = YapperAPI.RegisterStrings,
    GetString            = YapperAPI.GetString,
    ShowIconGallery      = YapperAPI.ShowIconGallery,
    HideIconGallery      = YapperAPI.HideIconGallery,
    IsIconGalleryShown   = YapperAPI.IsIconGalleryShown,
    GetRaidIconData      = YapperAPI.GetRaidIconData,
    GetAutocompleteSuggestion = YapperAPI.GetAutocompleteSuggestion,
    GetCaretOffset       = YapperAPI.GetCaretOffset,
    GetGhostFrame        = YapperAPI.GetGhostFrame,
    ShowGhostText        = YapperAPI.ShowGhostText,
    HideGhostText        = YapperAPI.HideGhostText,
    SetGhostTextOffset   = YapperAPI.SetGhostTextOffset,
    SyncGhostTextFont    = YapperAPI.SyncGhostTextFont,
    SetSpellcheckTooltipOffset = YapperAPI.SetSpellcheckTooltipOffset,
    GetChatParent        = YapperAPI.GetChatParent,
    MakeFullscreenAware  = YapperAPI.MakeFullscreenAware,
}

YapperAPI.Settings = {
    RegisterSettingsCategory   = YapperAPI.RegisterSettingsCategory,
    UnregisterSettingsCategory = YapperAPI.UnregisterSettingsCategory,
    GetRegisteredSettingsCategories = YapperAPI.GetRegisteredSettingsCategories,
    OpenSettingsCategory       = YapperAPI.OpenSettingsCategory,
}

YapperAPI.Utility = {
    GetConfig       = YapperAPI.GetConfig,
    IsChatLockdown  = YapperAPI.IsChatLockdown,
    IsSecret        = YapperAPI.IsSecret,
    Deleet          = YapperAPI.Deleet,
}
