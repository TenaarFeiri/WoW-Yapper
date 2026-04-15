--[[
===========================================================================
    Yapper Public API  (Src/API.lua)
===========================================================================

    This file creates `_G.YapperAPI`, a safe, public-facing object that
    lets other addons hook into Yapper without touching the internal
    `YapperTable`.  Everything exposed here is sandboxed — external code
    cannot break Yapper's runtime even if it errors.

    Two systems are provided:

      • FILTERS   — fire *before* an action.  Can inspect, modify, or
                     cancel the operation.
      • CALLBACKS — fire *after* something happened (or on state change).
                     Notification only; cannot cancel.

---------------------------------------------------------------------------
1.  FILTERS (pre-hooks)
---------------------------------------------------------------------------

    Filters let you intercept an operation, inspect its data, change it,
    or cancel it entirely.

    Signature:
        local handle = YapperAPI:RegisterFilter(hookPoint, callback, priority)

    • hookPoint  — string name (see list below).
    • callback   — `function(payload) ... return payload end`
                     Receives a single TABLE with named keys.
                     Must return the (possibly modified) payload to continue,
                     or return `false` to cancel the operation.
    • priority   — optional number; lower fires first (default 10).
    • handle     — opaque value you pass to UnregisterFilter later.

    Example — strip custom tags before spellcheck:

        local h = YapperAPI:RegisterFilter("PRE_SPELLCHECK", function(p)
            p.text = p.text:gsub("%[MyTag%]", "")
            return p
        end)

    Example — block sends that contain a keyword:

        YapperAPI:RegisterFilter("PRE_SEND", function(p)
            if p.text:find("FORBIDDEN") then
                return false   -- cancel the send entirely
            end
            return p
        end)

    Example — rewrite outgoing text:

        YapperAPI:RegisterFilter("PRE_SEND", function(p)
            p.text = p.text:gsub("brb", "be right back")
            return p
        end, 5)   -- priority 5 fires before the default 10

    Unregistering:

        YapperAPI:UnregisterFilter(h)

    Available filter hook points
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Hook              Payload keys                   Cancellable?
    ────              ────────────                   ────────────
    PRE_SEND          text, chatType, language,      yes
                      target
    PRE_CHUNK         text, limit                    yes
    PRE_SPELLCHECK    text                           yes

---------------------------------------------------------------------------
2.  CALLBACKS (post-hooks / event notifications)
---------------------------------------------------------------------------

    Callbacks fire *after* something happened.  They receive data but
    cannot modify or cancel the action.

    Signature:
        local handle = YapperAPI:RegisterCallback(event, callback)

    • event    — string name (see list below).
    • callback — `function(...)` called with event-specific arguments.
    • handle   — opaque value you pass to UnregisterCallback later.

    Example — log every sent message:

        YapperAPI:RegisterCallback("POST_SEND", function(text, chatType, target)
            print("Yapper sent:", text, "to", chatType, target)
        end)

    Example — react to settings changes:

        YapperAPI:RegisterCallback("CONFIG_CHANGED", function(path, value)
            -- path is a dot-delimited string like "EditBox.FontSize"
            -- value is the new setting value
            if path == "Spellcheck.Locale" then
                print("Spellcheck locale changed to", value)
            end
        end)

    Example — track overlay visibility:

        YapperAPI:RegisterCallback("EDITBOX_SHOW", function(chatType, target)
            print("Yapper overlay opened on", chatType)
        end)

        YapperAPI:RegisterCallback("EDITBOX_HIDE", function()
            print("Yapper overlay closed")
        end)

    Unregistering:

        YapperAPI:UnregisterCallback(h)

    Available callback events
    ~~~~~~~~~~~~~~~~~~~~~~~~~
    Event                    Arguments
    ─────                    ─────────
    POST_SEND                text, chatType, language, target
    CONFIG_CHANGED           path (string), value
    EDITBOX_SHOW             chatType, target
    EDITBOX_HIDE             (none)
    EDITBOX_CHANNEL_CHANGED  chatType, target
    THEME_CHANGED            themeName
    API_ERROR                kind, hook, handler_info, errorMessage, data, ...

---------------------------------------------------------------------------
3.  READ-ONLY ACCESSORS
---------------------------------------------------------------------------

    YapperAPI:GetVersion()          → "1.3.0" (string)
    YapperAPI:GetCurrentTheme()     → theme name (string) or nil
    YapperAPI:IsOverlayShown()      → boolean
    YapperAPI:GetConfig(path)       → value at dot-path, e.g. "Chat.DELINEATOR"

    These never expose internal tables directly; tables are shallow-copied.

---------------------------------------------------------------------------
4.  NOTES FOR ADDON AUTHORS
---------------------------------------------------------------------------

        • Yapper wraps every external filter and callback in `pcall()`.
            If your handler errors, Yapper emits an `API_ERROR` callback so
            external addons can inspect the failure programmatically and
            optionally take corrective action.  The `API_ERROR` callback has
            the signature `(kind, hook, handler_info, errorMessage, data, ...)`:
                - `kind`: "filter", "callback", or "filter-return"
                - `hook`: the hook or event name where the failure occurred
                - `handler_info`: table `{ handle = <number>, priority = <number?> }` or nil
                - `errorMessage`: the handler's error string
                - `data`: the payload (for filters) or returned value
                - `...`: other args passed to the handler

            If handlers are registered for `API_ERROR`, Yapper will attempt
            to deliver the event only to those handlers that were registered
            by the same addon/module that owns the failing handler (this
            ownership is recorded at registration time from the handler's
            source). If one or more owner-specific handlers exist, only they
            are invoked. If none exist, the event is broadcast to all
            `API_ERROR` handlers as a fallback. If no `API_ERROR` handlers are
            registered at all, Yapper falls back to emitting a concise debug
            line via `YapperTable.Utils:DebugPrint` (or `print()`). These
            messages are informational only and intended to aid debugging; their
            exact formatting may change between releases.

    • Filters MUST return the payload table (or false).  Returning nil
      is treated as "continue unchanged" for safety, but please don't
      rely on it — always return the payload explicitly.

    • Filter payloads are plain tables.  Modify fields in-place; do not
      replace the table itself (return the same reference).

    • Do not cache YapperAPI references across files; the global is
      stable for the entire session.

    • If you need a hook point that doesn't exist yet, open an issue
      or PR on the Yapper repository.

===========================================================================
]]

local YapperName, YapperTable = ...

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local API = {}
YapperTable.API = API

local filters   = {}   -- [hookPoint] = sorted array of {cb, priority, handle}
local callbacks = {}   -- [event]     = array of {cb, handle}
local handleSeq = 0    -- monotonic handle counter

local type   = type
local pairs  = pairs
local ipairs = ipairs
local pcall  = pcall
local table_insert = table.insert
local table_sort   = table.sort
local table_remove = table.remove

-- ===== Debug / error helpers ==============================================================
local function _truncate_string(s, max)
    if type(s) ~= "string" then return s end
    max = max or 200
    if #s > max then
        return s:sub(1, max) .. "...[+" .. tostring(#s - max) .. " bytes]"
    end
    return s
end

local function _serialize_value(val, depth, seen)
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
        local ok, info = pcall(debug.getinfo, val, "nS")
        if ok and info then
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
                parts[#parts+1] = "..."
                break
            end
            parts[#parts+1] = "[" .. _serialize_value(k, depth - 1, seen) .. "]=" .. _serialize_value(v, depth - 1, seen)
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
        parts[#parts+1] = _serialize_value(select(i, ...), 2)
    end
    return table.concat(parts, ", ")
end

-- Emit an `API_ERROR` event to registered handlers.  We call handlers
-- directly here (not via `API:Fire`) to avoid recursive error reporting
-- loops: errors raised by API_ERROR handlers are caught and logged but
-- do not trigger another API_ERROR emission.
local function _emit_error_event(kind, hook, failing_entry, err, payload_or_result, ...)
    local list = callbacks["API_ERROR"]
    if not list or #list == 0 then return false end

    -- Prefer delivering to handlers registered by the same owner as the
    -- failing handler (to avoid confusing unrelated addons).  If no owner-
    -- specific API_ERROR handlers exist, fall back to broadcasting to all
    -- API_ERROR handlers.
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

    for _, ev in ipairs(tocall) do
        local ok, e = pcall(ev.cb,
            kind,
            hook,
            (failing_entry and { handle = failing_entry.handle, priority = failing_entry.priority, owner = failing_entry.owner } or nil),
            err,
            payload_or_result,
            ...)
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
    -- Prefer to publish the structured event so addon authors can respond
    -- programmatically. If no handlers are registered, fall back to a
    -- concise debug print so failures are still visible during development.
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
local YapperAPI = {
    _version = "1.0",   -- API version, independent of addon version
}
_G.YapperAPI = YapperAPI

-- ===== FILTERS =============================================================

--- Register a filter for a hook point.
--- @param hookPoint string  The hook name (e.g. "PRE_SEND").
--- @param callback function  Receives a payload table, must return it or false.
--- @param priority number|nil  Lower fires first; default 10.
--- @return number handle  Pass to UnregisterFilter to remove.
function YapperAPI:RegisterFilter(hookPoint, callback, priority)
    if type(hookPoint) ~= "string" or type(callback) ~= "function" then
        return nil
    end

    priority = type(priority) == "number" and priority or 10
    local handle = NextHandle()

    if not filters[hookPoint] then
        filters[hookPoint] = {}
    end

    -- Capture registration origin so we can attribute errors to the
    -- registering addon/module.  Best-effort: extract an AddOn folder
    -- name from the source path when available, else store the short_src.
    local owner = nil
    local ok, reginfo = pcall(debug.getinfo, 2, "S")
    if ok and reginfo then
        local src = reginfo.source or reginfo.short_src
        if type(src) == "string" then
            local addon = src:match("AddOns[/\\]([^/\\]+)")
            owner = addon or src
        end
    end

    table_insert(filters[hookPoint], {
        cb       = callback,
        priority = priority,
        handle   = handle,
        owner    = owner,
    })

    -- Sort: lower priority fires first; ties broken by registration order.
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
--- @return number handle  Pass to UnregisterCallback to remove.
function YapperAPI:RegisterCallback(event, callback)
    if type(event) ~= "string" or type(callback) ~= "function" then
        return nil
    end

    local handle = NextHandle()

    if not callbacks[event] then
        callbacks[event] = {}
    end

    -- Capture registration origin for callbacks as well.
    local owner = nil
    local ok, reginfo = pcall(debug.getinfo, 2, "S")
    if ok and reginfo then
        local src = reginfo.source or reginfo.short_src
        if type(src) == "string" then
            local addon = src:match("AddOns[/\\]([^/\\]+)")
            owner = addon or src
        end
    end

    table_insert(callbacks[event], {
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

--- Returns the addon version string (e.g. "1.3.0").
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

--- Read a config value by dot-path (e.g. "EditBox.FontSize").
--- Tables are shallow-copied to prevent mutation of live config.
function YapperAPI:GetConfig(path)
    if type(path) ~= "string" then return nil end
    local cfg = YapperTable.Config
    if type(cfg) ~= "table" then return nil end

    for key in path:gmatch("[^%.]+") do
        if type(cfg) ~= "table" then return nil end
        cfg = cfg[key]
    end

    -- Shallow-copy tables so callers can't mutate live config.
    if type(cfg) == "table" then
        local copy = {}
        for k, v in pairs(cfg) do
            copy[k] = v
        end
        return copy
    end

    return cfg
end

-- ===== INTERNAL ENTRY POINTS ===============================================
-- These are called by Yapper's own modules.  Not on the public object.

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
        local ok, result = pcall(entry.cb, payload)
        if not ok then
            -- External code errored — report details and continue.
            _report_api_error("filter", hookPoint, entry, result, payload)
        elseif result == false then
            -- Filter explicitly cancelled the operation.
            return false
        elseif type(result) == "table" then
            payload = result
        elseif result ~= nil then
            -- Unexpected non-table non-false return; report it for debugging but
            -- continue with the current payload to avoid breaking consumers.
            _report_api_error("filter-return", hookPoint, entry, "unexpected return value", result, payload)
        end
        -- nil return = "I didn't change anything", continue with current payload.
    end

    return payload
end

--- Fire all callbacks for an event.  Arguments are passed through.
--- Errors in external code are caught and logged; Yapper is never harmed.
---
--- @param event string
--- @param ... any
function API:Fire(event, ...)
    local list = callbacks[event]
    if not list or #list == 0 then
        return
    end

    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.cb, ...)
        if not ok then
            -- Callback errors shouldn't propagate. Report with argument snapshot.
            _report_api_error("callback", event, entry, err, nil, ...)
        end
    end
end
