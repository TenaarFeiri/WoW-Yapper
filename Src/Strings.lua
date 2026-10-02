--[[
    Strings.lua — UI string registry and resolver.

    Yapper ships one complete canonical table: enUS English.  Dictionary
    addons (or any addon) may register sparse per-locale overrides through
    YapperAPI:RegisterStrings(locale, strings).  Lookup order is:

        registered locale table  →  enUS canonical  →  the key itself

    so a missing translation can never render blank — worst case the dot-key
    shows, which is debuggable rather than silently wrong.

    Two locale axes exist and must not be conflated:
      - CLIENT locale (GetLocale()) drives UI strings — what this module
        resolves against.
      - SPELLCHECK dict locale (Spellcheck:GetLocale()) drives dictionary
        selection.  A deDE client may spellcheck in enUS; the UI still
        follows GetLocale().

    Call sites resolve at render/show time (never cache resolved text on the
    frame), because dictionary addons are load-on-demand: their string tables
    can arrive after the UI exists, and a STRINGS_UPDATED event should be
    able to relabel an open panel.
]]

local _, YapperTable = ...

local Strings = {}
YapperTable.Strings = Strings

local type   = type
local pairs  = pairs
local select = select
local pcall  = pcall
local string_format = string.format

-- Registration limits — same bounded-contract posture as language engines.
local MAX_STRINGS_PER_REGISTRATION = 512
local MAX_KEY_LEN                  = 80
local MAX_VALUE_LEN                = 500
local MAX_REGISTERED_LOCALES       = 24

-- ---------------------------------------------------------------------------
-- Canonical English table (enUS / enGB).  Every key referenced anywhere in
-- the codebase MUST exist here; the string-coverage tool enforces this.
-- Addon-registered locales may only override keys that exist in this table.
-- ---------------------------------------------------------------------------
Strings._enUS = {

    -- Suggestion popup chrome (Spellcheck/UI.lua + Spellcheck/Engine.lua).
    ["ui.spellcheck.more"]        = "%d. More Suggestions »",
    ["ui.spellcheck.backtotop"]   = "%d. « Back to Top",
    ["ui.spellcheck.add"]         = "%d. Add \"%s\" to dictionary",
    ["ui.spellcheck.ignore"]      = "%d. Ignore \"%s\"",
    ["ui.spellcheck.split"]       = "%d. Split: %s",
    ["ui.spellcheck.revert"]      = "%d. Restore \"%s\"",
    ["ui.spellcheck.row"]         = "%d. %s",
    ["ui.spellcheck.row.empty"]   = "%d. -",

    -- Toast notifications (Toast.lua): autocorrect undo + learned-word card.
    ["ui.toast.autocorrected"]    = "Autocorrected",
    ["ui.toast.autocorrectBody"]  = "\"%s\" -> \"%s\"",
    ["ui.toast.undo"]             = "Undo",
    ["ui.toast.learned"]          = "Yapper learned a word",
    ["ui.toast.learnedBody"]      = "\"%s\" added to your %s dictionary",
    ["ui.toast.keep"]             = "Keep",
    ["ui.toast.unlearn"]          = "Unlearn",
    ["ui.toast.ignore"]           = "Ignore",

    -- Emote picker (Emotes.lua).  Emote commands themselves come from
    -- Blizzard's locale-bound globals and are already client-localised.
    ["ui.emotes.hint"]            = "Tab: browse emotes",

    -- Icon gallery (IconGallery.lua): cell labels are numeric and the
    -- {star}/{rt1} codes are protocol tokens — intentionally untranslated.
}

-- ---------------------------------------------------------------------------
-- Registration storage.  Per locale we keep an ordered list of
-- { owner = <addon>, keys = { [key] = text } } slots; _merged is the resolved
-- view.  Iterating slots in registration order makes collisions
-- deterministic: a later registration wins.
-- ---------------------------------------------------------------------------
Strings._registrations = {}    -- [locale] = { {owner=..., keys={...}}, ... }
Strings._merged        = {}    -- [locale][key] = text
Strings._registeredCount = 0   -- number of distinct registered locales

--- Active UI locale.  `_forceLocale` is a test hook; production resolves the
--- client locale lazily so headless test runs without GetLocale still work.
---@return string
function Strings:_ActiveLocale()
    if self._forceLocale then return self._forceLocale end
    if type(GetLocale) == "function" then return GetLocale() end
    return "enUS"
end

--- Resolve a string key for the active client locale.
--- Missing locale entries fall back to enUS; missing keys return the key
--- itself (never nil).  Extra args feed string.format; a malformed format
--- string degrades to the raw text rather than erroring.
---@param key string
---@return string
function Strings:Get(key, ...)
    local s
    if type(key) == "string" then
        local locale = self:_ActiveLocale()
        local merged = (locale ~= "enUS") and self._merged[locale] or nil
        s = (merged and merged[key]) or self._enUS[key]
    end
    if s == nil then
        s = tostring(key)
    end
    if select("#", ...) > 0 then
        local ok, out = pcall(string_format, s, ...)
        if ok then return out end
    end
    return s
end

--- Register a sparse locale string table.  Owner-captured by the API layer;
--- re-registration by the same owner replaces its contribution wholesale
--- (and moves it to the end, so the newest registration wins collisions).
--- The enUS table itself is core-owned and cannot be overridden.
---@param locale string
---@param tbl table  Sparse map of key → translated text.
---@param owner string|nil  Captured caller addon name.
---@return boolean ok, string|nil err
function Strings:Register(locale, tbl, owner)
    if type(locale) ~= "string" or locale == "" then
        return false, "locale must be a non-empty string"
    end
    if locale == "enUS" then
        return false, "enUS strings are core-owned and cannot be overridden"
    end
    if type(tbl) ~= "table" then
        return false, "strings must be a table"
    end
    owner = (type(owner) == "string" and owner ~= "") and owner or "unknown"

    -- Validate fully before applying — a rejected registration changes nothing.
    local validated = {}
    local count = 0
    for key, value in pairs(tbl) do
        if type(key) ~= "string" or key == "" or #key > MAX_KEY_LEN then
            return false, "invalid string key"
        end
        if type(value) ~= "string" or #value == 0 or #value > MAX_VALUE_LEN then
            return false, "invalid value for key \"" .. key .. "\""
        end
        if self._enUS[key] == nil then
            return false, "unknown string key \"" .. key .. "\""
        end
        count = count + 1
        if count > MAX_STRINGS_PER_REGISTRATION then
            return false, "string registration cap exceeded (" .. MAX_STRINGS_PER_REGISTRATION .. ")"
        end
        validated[key] = value
    end

    local slots = self._registrations[locale]
    if not slots then
        if self._registeredCount >= MAX_REGISTERED_LOCALES then
            return false, "registered locale cap reached (" .. MAX_REGISTERED_LOCALES .. ")"
        end
        slots = {}
        self._registrations[locale] = slots
        self._registeredCount = self._registeredCount + 1
    end

    -- Wholesale replace: drop this owner's previous slot (ordered traversal —
    -- slot order is load-bearing for collision determinism), append the new.
    local compacted = {}
    for i = 1, #slots do
        if slots[i].owner ~= owner then
            compacted[#compacted + 1] = slots[i]
        end
    end
    compacted[#compacted + 1] = { owner = owner, keys = validated }
    self._registrations[locale] = compacted

    -- Rebuild the merged view deterministically (registration order wins).
    local merged = {}
    for _, slot in pairs(compacted) do
        for key, value in pairs(slot.keys) do
            merged[key] = value
        end
    end
    self._merged[locale] = merged

    -- Live-refresh hook: dict addons are load-on-demand, so strings can
    -- arrive after the UI is built.  Widgets resolve at render time; this
    -- event lets anything else (open panels, external addons) re-render.
    if YapperTable.API and YapperTable.API.Fire then
        YapperTable.API:Fire("STRINGS_UPDATED", locale)
    end
    return true
end

--- Enumerate canonical keys — used by tooling and tests.
---@return table array of enUS keys (unsorted)
function Strings:CanonicalKeys()
    local out = {}
    for key in pairs(self._enUS) do
        out[#out + 1] = key
    end
    return out
end
