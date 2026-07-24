--[[
    Languages Bridge for WoW-Yapper

    Reproduces Languages' outgoing dialect and tag behavior through LanguagesAPI.
    Does not register with or intercept LibChatFilter.

    Division of labour:
      PRE_SEND  → rewrites the text (dialect + tag), per paragraph
      PRE_CHUNK → supplies the continuation prefix for chunks 2+
    Both decisions come from one resolver, so the head chunk and the
    continuation chunks can never disagree.

    Every chunk carries the tag because Languages' receive filter only matches
    `^(%A*)%[Name%]%s*`; untagged chunks pass through unchanged.

    The `(%A*)` capture permits only non-alphabetic text before the tag. WoW Lua
    treats bytes 128-255 as alphabetic, so "»" does not qualify. The bridge
    checks the delineator with `%a` and sets `continuationPrefixFirst` as needed.

    Tags use the English key. Languages resolves the displayed name locally and
    registers the enUS names as receive patterns on every client.
]]

local _, YapperTable = ...

local LanguagesBridge = {}
YapperTable.LanguagesBridge = LanguagesBridge

LanguagesBridge.active = false

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Languages only acts on say-like channels.
local SAY_LIKE = {
    SAY  = true,
    YELL = true,
}

local FACTION_DEFAULT_LANGUAGE = {
    Alliance = "Common",
    Horde    = "Orcish",
    Neutral  = "Pandaren",
}

-- ---------------------------------------------------------------------------
-- Languages state (read through the public API wherever one exists)
-- ---------------------------------------------------------------------------

local function LangAPI()
    local api = _G.LanguagesAPI
    if type(api) ~= "table" then return nil end
    return api
end

--- Mirrors Languages' `mainFrame.prefix` toggle.
local function IsPrefixEnabled()
    local frame = _G.LanguagesMainFrame
    return frame ~= nil and frame.prefix == true
end

--- Mirrors Languages' in-character restriction when TRP3 is available.
local function ShouldProcessLanguage()
    local api = LangAPI()
    if not api or type(api.GetActiveProfileData) ~= "function" then return true end

    local profile = api.GetActiveProfileData()
    if type(profile) ~= "table" or not profile.onlyInCharacter then return true end

    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("totalRP3")) then
        return true
    end

    local TRP3 = _G.AddOn_TotalRP3
    if not (TRP3 and TRP3.Player and TRP3.Player.GetCurrentUser) then return true end

    local user = TRP3.Player.GetCurrentUser()
    if user and user.IsInCharacter and not user:IsInCharacter() then
        return false
    end

    return true
end

--- Mirrors Languages' faction check using its SavedVariable setting.
--- @param activeLanguage string
--- @return boolean allowed
local function FactionCheck(activeLanguage)
    local db       = _G.Languages_DB
    local settings = type(db) == "table" and db.settings or nil
    if type(settings) ~= "table" or settings.faction ~= true then
        return true
    end

    local default = FACTION_DEFAULT_LANGUAGE[UnitFactionGroup("player") or ""]
    if not default then return true end

    return activeLanguage ~= default
end

-- ---------------------------------------------------------------------------
-- Resolver
-- ---------------------------------------------------------------------------

--- Decide what Languages wants done with an outgoing message.
---
--- Dialect and tag are independent: a suppressed tag does not suppress dialect.
---
--- @param chatType   string|nil
--- @param languageID number|nil  Numeric in-game language id the message is sent with.
--- @return boolean applyDialect
--- @return string|nil tag  Language name to tag with, or nil for no tag.
local function ResolveContext(chatType, languageID)
    if not SAY_LIKE[chatType] then return false, nil end
    if not LangAPI() then return false, nil end

    -- Languages skips processing in combat.
    if UnitAffectingCombat("player") then return false, nil end

    -- Leave non-default language messages untouched.
    if languageID ~= nil then
        local _, defaultID = GetDefaultLanguage()
        if languageID ~= defaultID then return false, nil end
    end

    -- Dialect remains active when tag gating fails.
    if not IsPrefixEnabled()       then return true, nil end
    if not ShouldProcessLanguage() then return true, nil end

    local api    = LangAPI()
    local active = type(api.GetActiveLanguage) == "function" and api.GetActiveLanguage() or nil
    if type(active) ~= "string" or active == "" then return true, nil end
    if not FactionCheck(active) then return true, nil end

    return true, active
end

--- Return whether the delineator can precede the tag on continuation chunks.
--- @return boolean
local function DelineatorAllowsLeadingTag()
    local API = _G.YapperAPI
    local marker = API and type(API.GetDelineator) == "function" and API:GetDelineator() or nil
    if type(marker) ~= "string" or marker == "" then return true end
    return marker:find("%a") == nil
end

-- ---------------------------------------------------------------------------
-- Text transformation
-- ---------------------------------------------------------------------------

local function TransformParagraph(line, applyDialect, tag)
    local api = LangAPI()
    if applyDialect and api and type(api.ApplyDialectToText) == "function" then
        local ok, result = pcall(api.ApplyDialectToText, line)
        if ok and type(result) == "string" then
            line = result
        end
    end

    if tag then
        local lead = "[" .. tag .. "] "
        -- Avoid duplicating a recalled tag.
        if line:sub(1, #lead) ~= lead then
            line = lead .. line
        end
    end

    return line
end

--- Transform each paragraph independently.
local function TransformText(text, applyDialect, tag)
    if not text:find("\n", 1, true) then
        return TransformParagraph(text, applyDialect, tag)
    end

    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:find("%S") then
            out[#out + 1] = TransformParagraph(line, applyDialect, tag)
        end
    end

    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Register the Yapper filters once both APIs are available.
function LanguagesBridge:Init()
    if self.active then return end
    if not LangAPI() then return end

    local API = _G.YapperAPI
    if not API or type(API.RegisterFilter) ~= "function" then return end

    -- Run after the default filters so they see untagged text first.
    self._sendHandle = API:RegisterFilter("PRE_SEND", function(payload)
        if type(payload) ~= "table" or type(payload.text) ~= "string" then
            return payload
        end

        local applyDialect, tag = ResolveContext(payload.chatType, payload.language)
        if applyDialect then
            payload.text = TransformText(payload.text, applyDialect, tag)
        end

        return payload
    end, 20)

    self._chunkHandle = API:RegisterFilter("PRE_CHUNK", function(payload)
        if type(payload) ~= "table" then return payload end

        local _, tag = ResolveContext(payload.chatType, payload.language)
        if tag then
            -- PRE_SEND tags the head; this prefix covers chunks 2+.
            payload.continuationPrefix = "[" .. tag .. "] "

            -- Put the tag first when the delineator would break detection.
            payload.continuationPrefixFirst = not DelineatorAllowsLeadingTag()
        end


        return payload
    end, 20)

    self.active = true
end

--- Unregister the filters and go dormant.
function LanguagesBridge:Shutdown()
    local API = _G.YapperAPI
    if API and type(API.UnregisterFilter) == "function" then
        if self._sendHandle  then API:UnregisterFilter(self._sendHandle) end
        if self._chunkHandle then API:UnregisterFilter(self._chunkHandle) end
    end

    self._sendHandle  = nil
    self._chunkHandle = nil
    self.active       = false
end

--- @return boolean
function LanguagesBridge:IsActive()
    return self.active
end

-- ---------------------------------------------------------------------------
-- Bootstrap (self-initialising — bridges are never wired into core)
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Languages") then
            LanguagesBridge:Init()
        end
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Languages" then
            LanguagesBridge:Init()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Debug slash command
-- ---------------------------------------------------------------------------

_G.SLASH_LANGYAPPERBRIDGE1 = "/lyb"
SlashCmdList["LANGYAPPERBRIDGE"] = function()
    if not LanguagesBridge.active then
        print("LanguagesBridge: not active (Languages or YapperAPI unavailable)")
        return
    end

    local api         = LangAPI()
    local activeLang  = api and type(api.GetActiveLanguage)     == "function" and api.GetActiveLanguage()     or nil
    local dialect     = api and type(api.GetActiveDialect)      == "function" and api.GetActiveDialect()      or nil
    local profileName = api and type(api.GetActiveProfileName)  == "function" and api.GetActiveProfileName()  or nil

    local applyDialect, tag = ResolveContext("SAY", select(2, GetDefaultLanguage()))

    print("LanguagesBridge status:")
    print("  Profile:        " .. tostring(profileName))
    print("  Language:       " .. tostring(activeLang))
    print("  Dialect:        " .. tostring(dialect))
    print("  Prefix enabled: " .. tostring(IsPrefixEnabled()))
    print("  In character:   " .. tostring(ShouldProcessLanguage()))
    print("  Faction allows: " .. tostring(activeLang and FactionCheck(activeLang)))
    print("  ---- resolved for a SAY right now ----")
    print("  Apply dialect:  " .. tostring(applyDialect))
    print("  Tag:            " .. tostring(tag and ("[" .. tag .. "]") or "none"))

    -- The delineator before the tag must contain no letters.
    local marker = _G.YapperAPI and _G.YapperAPI:GetDelineator() or ""
    if DelineatorAllowsLeadingTag() then
        print("  Split layout:   " .. tostring(marker) .. " [Lang] text")
    else
        print("  Split layout:   [Lang] " .. tostring(marker) ..
              " text |cffffcc00(delineator contains a letter; tag moved to the front)|r")
    end
end
