--[[
===========================================================================
    Yapper Public API  (Src/API.lua)
===========================================================================
    Full documentation are available on GitHub: https://github.com/TenaarFeiri/WoW-Yapper/tree/main/Documentation
    This will always be up to date.
    I am always looking for new opportunities to expand the API, so if you have need
    for a hook point that doesn't exist yet, please open an issue or PR on the Yapper repository.
    Alternatively, you can DM me on GitHub, CurseForge (Symphicat), or send me an email at symphicat@gmail.com


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
    PRE_EDITBOX_SHOW  chatType, target               yes
      Fires before the overlay opens.  Return false to suppress it.
      Used by WIMBridge to yield focus when WIM owns the whisper window.

    PRE_SEND          text, chatType, language,      yes
                      target
      Fires after the user presses Enter but before the message is routed.
      Modify payload fields to rewrite the message or return false to block.

    PRE_CHUNK         text, limit                    yes
      Fires before the chunker splits a long message.  Modify text or limit,
      or return false to prevent chunking entirely.

    PRE_SPELLCHECK    text                           yes
      Fires before the spellchecker runs on the current input.  Return false
      to skip spellchecking for this particular text.

    PRE_DELIVER       text, chatType, language,      yes
                      target
      Fires in DirectSend just before Router:Send.  A filter may return false
      to "claim" the message — Yapper will not send it via Router and will
      instead start a delegation timer.  The claiming addon receives a
      POST_CLAIMED callback with a handle and must call
      YapperAPI:ResolvePost(handle) within the timeout (default 5 s).
      If the timeout expires, Yapper sends the message itself and prints an
      error attributing the failure to the claiming addon.

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
      Fires after a message has been handed to the WoW send API.

    CONFIG_CHANGED           path (string), value
      Fires when a Yapper setting changes.  path is dot-delimited,
      e.g. "EditBox.FontSize", "Spellcheck.Locale".

    EDITBOX_SHOW             chatType, target
      Fires when the Yapper overlay becomes visible.

    EDITBOX_HIDE             (none)
      Fires when the Yapper overlay is hidden.

    EDITBOX_CHANNEL_CHANGED  chatType, target
      Fires when the user switches chat channel (Tab, slash command, etc.).

    THEME_CHANGED            themeName
      Fires when the active theme is changed.

    API_ERROR                kind, hook, handler_info, errorMessage, data, ...
      Fires when a filter or callback handler errors.  Delivered only to the
      addon that owns the faulting handler (matched by source file path).

    SPELLCHECK_SUGGESTION    word, suggestions (array of strings)
      Fires when the spellcheck suggestion popup is shown for a misspelled word.

    SPELLCHECK_APPLIED       original, replacement
      Fires when the user accepts a spellcheck suggestion.

    SPELLCHECK_WORD_ADDED    word, locale
      Fires when a word is added to the user dictionary (manually or via YALLM).

    SPELLCHECK_WORD_IGNORED  word, locale
      Fires when the user marks a word as "ignored".

    YALLM_WORD_LEARNED       word, locale
      Fires when YALLM auto-promotes a word to the user dictionary after
      persistent usage (reaching the auto-learn threshold).

    POST_CLAIMED             handle, text, chatType, language, target
      Fires when a PRE_DELIVER filter claims a message.  The handle must
      be passed to YapperAPI:ResolvePost(handle) within the delegation
      timeout to confirm delivery.  If not resolved, Yapper sends the
      message itself and blames the claiming addon.

    QUEUE_STALL              chatType, policyClass, chunksRemaining
      Fires when the ack-event stall timer expires before the server
      confirmed a chunk.  Indicates the Continue prompt is now visible.
      `chatType` is the WoW chat type string (e.g. "SAY"), `policyClass`
      is the internal policy class name, `chunksRemaining` is the total
      number of chunks still waiting (including the one that stalled).

    QUEUE_COMPLETE           (no arguments)
      Fires when the queue finishes delivering all chunks (successfully
      or after a cancel).  Paired with QUEUE_STALL for addons that need
      to track active queue sessions.

    ICON_GALLERY_SHOW        query (string)
      Fires when the raid-icon gallery popup opens.  query is the
      partial word the user typed after '{' (may be empty string).

    ICON_GALLERY_HIDE        (no arguments)
      Fires when the raid-icon gallery popup closes.

    ICON_GALLERY_SELECT      index (int), text (string), code (string)
      Fires when the user picks a raid icon.  index is 1-8; text is the
      icon name (e.g. "skull"); code is the shorthand (e.g. "rt8").

---------------------------------------------------------------------------
3.  READ-ONLY ACCESSORS
---------------------------------------------------------------------------

    YapperAPI:GetVersion()          → "1.3.0" (string)
    YapperAPI:GetCurrentTheme()     → theme name (string) or nil
    YapperAPI:IsOverlayShown()      → boolean
    YapperAPI:GetConfig(path)       → value at dot-path, e.g. "Chat.DELINEATOR"

    Theme helpers:

    YapperAPI:RegisterTheme(name, data)
      Register a custom theme. `data` follows the same schema as built-in
      themes: inputBg, labelBg, textColor, borderColor, border, allowRoundedCorners,
      allowDropShadow, font, and optional OnApply.

    YapperAPI:SetTheme(name)
      Activate a registered theme and persist it as the current selection.

    YapperAPI:GetRegisteredThemes() → array
      Return a sorted list of registered theme names.

    YapperAPI:GetTheme(name) → table|nil
      Return the data table for a registered theme, or nil if not found.

    Queue accessors:

    YapperAPI:GetQueueState()       → table with fields:
                                        active (bool), stalled (bool),
                                        chatType (string|nil),
                                        policyClass (string|nil),
                                        pending (int), inFlight (int)
    YapperAPI:CancelQueue()         → int (number of chunks discarded)

    Icon Gallery accessors:

    YapperAPI:ShowIconGallery(editBox, anchorFrame, query)
      Shows the raid-icon gallery anchored to an external EditBox widget.
      editBox must be a raw WoW EditBox; anchorFrame is the frame the popup
      anchors to (defaults to editBox); query is an optional pre-filter string.

    YapperAPI:HideIconGallery()
      Hides the gallery.

    YapperAPI:IsIconGalleryShown()  → boolean

    YapperAPI:GetRaidIconData()     → array of 8 tables, each with:
                                        index (int), text (string), code (string)

    Utility helpers (safe wrappers around Utils.lua):

    YapperAPI:IsChatLockdown()      → boolean
      Returns true if C_ChatInfo.InChatMessagingLockdown() is active.
      Use this to guard sends in bridges the same way Yapper does internally.

    YapperAPI:IsSecret(value)       → boolean
      Returns true if a value should not be logged or persisted (Blizzard
      issecretvalue / canaccessvalue APIs, with a |K token fallback).

    YapperAPI:GetChatParent()       → Frame
      Returns the correct UI parent for chat-related frames, respecting
      fullscreen panels like the housing editor.

    YapperAPI:MakeFullscreenAware(frame)
      Hooks the frame so it re-parents automatically whenever the active
      fullscreen panel changes.  Pass any frame you want to keep visible
      over panels that hide UIParent.

    Spellcheck accessors (safe wrappers — return nil/false if spellcheck is unavailable):

    YapperAPI:IsSpellcheckEnabled() → boolean
    YapperAPI:CheckWord(word)       → boolean (true if word is in dict or user dict)
    YapperAPI:GetSuggestions(word)  → array of suggestion strings, or nil
    YapperAPI:GetSpellcheckLocale() → locale string (e.g. "enUS") or nil
    YapperAPI:AddToDictionary(word) → boolean (true if added)
    YapperAPI:IgnoreWord(word)      → boolean (true if ignored)

    Dictionary / engine registration (for LOD dictionary addons):

    YapperAPI:RegisterDictionary(locale, data)
      Register a dictionary for the given locale (e.g. "enBase", "enGB").
      `data` accepts the same fields as the internal RegisterDictionary call:
        • words          — array of canonical word strings
        • phonetics      — table { [phoneticHash] = { wordId, … } }
        • extends        — string locale this dict inherits from (delta dicts)
        • isDelta        — bool (inferred from extends; can be set explicitly)
        • languageFamily — string family id, e.g. "en". Links this dict to a
                           registered language engine.
        • engine         — optional table (see RegisterLanguageEngine). When
                           present, the engine is registered atomically with
                           the dict so ordering does not matter.
      Returns true on success, false on invalid arguments.

    YapperAPI:RegisterLanguageEngine(familyId, engine)
      Register a language engine for a locale family.
      `familyId` — short string identifier, e.g. "en", "de", "fr".
      `engine`   — table with the following fields:
        • GetPhoneticHash(word) → string   (REQUIRED)
          Must produce the same hash keys used in the dict's phonetics table.
        • NormaliseVowels(word) → string   (optional; falls back to built-in)
        • HasVariantRules — bool           (optional; enables variant swaps)
        • VariantRules    — array of {from, to} pairs  (optional)
        • ScoreWeights    — partial table  (optional; overlays built-in weights)
        • KBLayouts       — table          (optional; same schema as built-in KB_LAYOUTS)
      Returns true on success, false on invalid / missing GetPhoneticHash.

    YapperAPI:IsLanguageEngineRegistered(familyId) → boolean

    Post delegation:

    YapperAPI:ResolvePost(handle)   → boolean (true if the claim was valid and resolved)

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
local API                     = {}
YapperTable.API               = API

local filters                 = {} -- [hookPoint] = sorted array of {cb, priority, handle}
local callbacks               = {} -- [event]     = array of {cb, handle}
local handleSeq               = 0  -- monotonic handle counter

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
    _version = "1.1", -- API version, independent of addon version
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
        _report("FILTER", hookPoint, nil, "registration cap reached (" .. MAX_FILTERS_PER_HOOK .. " filters)")
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

    if not callbacks[event] then
        callbacks[event] = {}
    end

    if #callbacks[event] >= MAX_CALLBACKS_PER_EVT then
        _report("CALLBACK", event, nil, "registration cap reached (" .. MAX_CALLBACKS_PER_EVT .. " callbacks)")
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

--- Register a dictionary via the public API.
--- `locale` — the locale key, e.g. "enBase", "enGB", "enUS".
--- `data`   — table with the same fields accepted by the internal
---             RegisterDictionary call (words, phonetics, extends, etc.).
---             See the header doc comment for the full field list.
--- Returns true if accepted, false on invalid arguments.
function YapperAPI:RegisterDictionary(locale, data)
    if type(locale) ~= "string" or locale == "" then return false end
    if type(data) ~= "table" then return false end
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

--- Run all filters for a hook point.
--- Returns the (possibly modified) payload, or false if cancelled.
--- If no filters are registered, returns the payload unchanged.
---
--- @param hookPoint string
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
