--[[
===========================================================================
    Yapper Public API  (Src/API.lua)
===========================================================================
    This file creates `_G.YapperAPI`, a safe, public-facing object that
    lets other addons hook into Yapper without touching internal tables.

    Full documentation is available in:
    Src/API_Documentation.txt

    Or on GitHub:
    https://github.com/TenaarFeiri/WoW-Yapper/tree/main/Documentation
===========================================================================
]]

local YapperName, YapperTable = ...

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local API                     = {}
YapperTable.API               = API

local filters                 = {} -- [hookPoint] = sorted array of {cb, priority, handle}
local callbacks               = {} -- [event]     = array of {cb, handle}
local handleSeq               = 0  -- monotonic handle counter
local registeredLinkProtocols = {} -- [prefix] = true; populated by RegisterLinkProtocol

-- Deprecated event name aliases for backward compatibility
local EVENT_ALIASES = {
    ["YALLM_WORD_LEARNED"] = "YAS_WORD_LEARNED",
}

local type                    = type
local pairs                   = pairs
local ipairs                  = ipairs
local pcall                   = pcall
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
local YapperAPI             = {
    _version = "1.2", -- API version, independent of addon version
}
_G.YapperAPI                = YapperAPI

-- Per-hook / per-event registration cap to prevent runaway leaks.
local MAX_FILTERS_PER_HOOK  = 50
local MAX_CALLBACKS_PER_EVT = 50

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

    if not filters[hookPoint] then
        filters[hookPoint] = {}
    end

    if #filters[hookPoint] >= MAX_FILTERS_PER_HOOK then
        _report_api_error("FILTER", hookPoint, nil, "registration cap reached (" .. MAX_FILTERS_PER_HOOK .. " filters)")
        return nil
    end

    priority = type(priority) == "number" and priority or 10
    local handle = NextHandle()

    -- Capture registration origin so we can attribute errors to the
    -- registering addon/module.  Best-effort: extract an AddOn folder
    -- name from the source path when available, else store the short_src.
    local owner = nil
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        -- Level 3: pcall(1) → RegisterFilter(2) → caller(3)
        local ok, reginfo = pcall(debug.getinfo, 3, "S")
        if ok and reginfo then
            local src = reginfo.source or reginfo.short_src
            if type(src) == "string" then
                local addon = src:match("AddOns[/\\]([^/\\]+)")
                owner = addon or src
            end
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
--- @return number|nil handle  Pass to UnregisterCallback to remove.
function YapperAPI:RegisterCallback(event, callback)
    if type(event) ~= "string" or type(callback) ~= "function" then
        return nil
    end

    -- Map deprecated event names to current equivalents
    local resolvedEvent = EVENT_ALIASES[event] or event

    if not callbacks[resolvedEvent] then
        callbacks[resolvedEvent] = {}
    end

    if #callbacks[resolvedEvent] >= MAX_CALLBACKS_PER_EVT then
        _report_api_error("CALLBACK", resolvedEvent, nil, "registration cap reached (" .. MAX_CALLBACKS_PER_EVT .. " callbacks)")
        return nil
    end

    local handle = NextHandle()

    -- Capture registration origin for callbacks as well.
    local owner = nil
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        -- Level 3: pcall(1) → RegisterCallback(2) → caller(3)
        local ok, reginfo = pcall(debug.getinfo, 3, "S")
        if ok and reginfo then
            local src = reginfo.source or reginfo.short_src
            if type(src) == "string" then
                local addon = src:match("AddOns[/\\]([^/\\]+)")
                owner = addon or src
            end
        end
    end

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

--- Force Yapper to close and open the original Blizzard editbox.
--- Equivalent to the "Bypass Yapper" keybind (Shift-Enter).
function YapperAPI:OpenBlizzardChat()
    if YapperTable.EditBox and YapperTable.EditBox.OpenBlizzardChat then
        YapperTable.EditBox:OpenBlizzardChat()
    end
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

--- SPECIFICALLY for chat-tracking addons like Eavesdropper,
--- get the delineator from the config.
--- We also use this API in-program so we will know quickly
--- if we move it and break it.
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
        return YapperTable.State:GetLogs()
    end
    return {}
end

--- Get a specific state change log by index.
--- @param index number
--- @return table|nil
function YapperAPI:GetStateLog(index)
    if YapperTable.State and YapperTable.State.GetLog then
        return YapperTable.State:GetLog(index)
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

--- Transition the state machine to a new state.
--- Use with caution: forcing states may bypass safety logic or cause UI desync.
--- @param stateName string  One of "IDLE", "EDITING", "MULTILINE", etc.
--- @param ... any          Metadata to pass to the state machine and observers.
function YapperAPI:SetState(stateName, ...)
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

    -- Also return the full categorized registry as a sub-table for advanced usage.
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
--- `locale` — the locale key, e.g. "enBase", "enGB", "enUS".
--- `data`   — table with the same fields accepted by the internal
---             RegisterDictionary call (words, phonetics, extends, etc.).
---             See the header doc comment for the full field list.
--- Returns true if accepted, false on invalid arguments.
function YapperAPI:RegisterDictionary(locale, data)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(data) ~= "table" and type(data) ~= "function" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.RegisterDictionary then return false end
    local ok, err = pcall(sc.RegisterDictionary, sc, locale, data)
    if not ok then
        _report_api_error("RegisterDictionary", locale, nil, err, { locale = locale })
        return false
    end
    return true
end

--- Register a language engine for a locale family.
--- `familyId` — short string id, e.g. "en", "de", "fr".
--- `engine`   — table; GetPhoneticHash is the only required field.
--- Returns true on success, false on invalid arguments.
function YapperAPI:RegisterLanguageEngine(familyId, engine)
    if type(familyId) ~= "string" or familyId == "" then return false end
    if type(engine) ~= "table" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc._RegisterLanguageEngine then return false end
    local ok, result = pcall(sc._RegisterLanguageEngine, sc, familyId, engine)
    if not ok then
        _report_api_error("RegisterLanguageEngine", familyId, nil, result, { familyId = familyId })
        return false
    end
    return result == true
end

--- Returns true if a language engine for `familyId` is registered.
function YapperAPI:IsLanguageEngineRegistered(familyId)
    if type(familyId) ~= "string" then return false end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.LanguageEngines then return false end
    return sc.LanguageEngines[familyId] ~= nil
end

--- Returns the language engine for `familyId`, or nil.
function YapperAPI:GetLanguageEngine(familyId)
    if type(familyId) ~= "string" then return nil end
    local sc = YapperTable.Spellcheck
    if not sc or not sc.LanguageEngines then return nil end
    return sc.LanguageEngines[familyId]
end

--- Map a Load-On-Demand addon to a specific locale so Yapper knows what to load
--- when tracking dictionaries for that region.
--- `locale` — e.g. "ptBR", "esES"
--- `addonName` — e.g. "Yapper_Dict_pt"
function YapperAPI:RegisterLocaleAddon(locale, addonName)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(addonName) ~= "string" or addonName == "" then return false end

    local sc = YapperTable.Spellcheck
    if not sc then return false end

    sc.LocaleAddons = sc.LocaleAddons or {}
    sc.LocaleAddons[locale] = addonName

    -- If a dictionary for this locale was requested before the mapping existed,
    -- or if the user is currently using this locale, try to ensure it again.
    if sc.GetLocale and sc:GetLocale() == locale then
        sc:EnsureLocale(locale)
    end
    return true
end

--- Declare a |H link protocol prefix as a known, first-class link type.
--- Plugins that inject custom |H<prefix>:...|h[...]|h links into Yapper
--- call this once on load so the pipeline knows to treat those tokens as
--- atomic hyperlinks (chunker already does this for all |H forms; this
--- API is the public signal surface for tooling and future features).
--- Returns true on success, false if prefix is not a non-empty string.
function YapperAPI:RegisterLinkProtocol(prefix)
    if type(prefix) ~= "string" or prefix == "" then return false end
    registeredLinkProtocols[prefix] = true
    return true
end

--- Returns a shallow copy of all registered link protocol prefixes as an
--- array of strings.  Ordered alphabetically.
function YapperAPI:GetRegisteredLinkProtocols()
    local out = {}
    for prefix in pairs(registeredLinkProtocols) do
        out[#out + 1] = prefix
    end
    table_sort(out)
    return out
end

--- Returns true if `prefix` has been registered via RegisterLinkProtocol.
function YapperAPI:IsLinkProtocolRegistered(prefix)
    if type(prefix) ~= "string" then return false end
    return registeredLinkProtocols[prefix] == true
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

--- Returns an array of all registered atomic patterns.
function YapperAPI:GetRegisteredAtomicPatterns()
    return registeredAtomicPatterns
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

    -- Fall back to the single-line overlay.
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
--- font ({path,size,flags}), and an optional OnApply hook.
--- Returns true on success, false if name or data is invalid.
function YapperAPI:RegisterTheme(name, data)
    if type(name) ~= "string" or type(data) ~= "table" then return false end
    local th = YapperTable.Theme
    if not th then return false end
    return th:RegisterTheme(name, data) == true
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

--- Return a shallow copy of a registered theme's data table, or nil.
--- Pass no argument (or nil) to get the currently active theme.
function YapperAPI:GetTheme(name)
    local th = YapperTable.Theme
    if not th then return nil end
    local data = th:GetTheme(name)
    if type(data) ~= "table" then return nil end
    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    return copy
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
--- Uses Blizzard's issecretvalue/canaccessvalue APIs with a |K token fallback.
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

-- Active claims: claimHandle → { text, chatType, language, target, owner, timer }
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

            -- Timeout: send the message ourselves and blame the addon.
            if YapperTable.Router then
                YapperTable.Router:Send(claim.text, claim.chatType, claim.language, claim.target)
            elseif C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(claim.text, claim.chatType, claim.language, claim.target)
            end

            -- Fire POST_SEND since we sent the message.
            API:Fire("POST_SEND", claim.text, claim.chatType, claim.language, claim.target)

            -- Blame the addon that failed to resolve.
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

    -- Cancel the timeout timer.
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
--- editBox    — the raw WoW EditBox whose text the gallery writes into.
--- anchorFrame — frame the popup anchors to (defaults to editBox when nil).
--- query       — optional pre-filter string (the word typed after "{").
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
--- Each entry has: index (1-8), text (name), code ("rt1"…"rt8").
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

    -- Temporarily bind to this EditBox if it's different from current.
    local prevEB = ac._activeEditBox
    ac._activeEditBox = editBox

    -- In manual mode, if no prefix is provided, we treat the entire text
    -- as the ghost suffix.
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
        local ok, result = pcall(entry.cb, payload)
        if not ok then
            -- External code errored — report details and continue.
            _report_api_error("filter", hookPoint, entry, result, payload)
        elseif result == false then
            -- Filter explicitly cancelled the operation.
            -- Store cancelling entry's owner for delegation tracking.
            self._lastCancelOwner = entry.owner
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

    self._lastCancelOwner = nil
    return payload
end

--- Fire all callbacks for an event.  Arguments are passed through.
--- Errors in external code are caught and logged; Yapper is never harmed.
---
--- @param event string
--- @param ... any
function API:Fire(event, ...)
    -- Resolve event aliases for backward compatibility
    local resolvedEvent = EVENT_ALIASES[event] or event
    local list = callbacks[resolvedEvent]
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
