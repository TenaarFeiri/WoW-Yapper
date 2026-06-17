--[[
    Languages Bridge for WoW-Yapper
    Enables Languages addon integration (prefixes, dialects, morphing) with Yapper.

    Captures Languages' LibChatFilter mutator to apply transformations via Yapper filters.
    Reads state from UI elements and captured mutator.
]]

local _, YapperTable = ...

local LanguagesBridge = {}
YapperTable.LanguagesBridge = LanguagesBridge

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

LanguagesBridge.active = false
LanguagesBridge.filterHandle = nil

-- Cached state to avoid repeated UI reads
LanguagesBridge.cachedLanguage = nil
LanguagesBridge.cachedPrefixState = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function GetLanguagesMainFrame()
    return _G.LanguagesMainFrame
end

local function GetSelectionButton()
    return _G.LanguagesSelectionButton
end

local function GetCharacterKey()
    local realm = GetRealmName()
    local name = UnitName("player")
    return name .. " - " .. realm
end

local function GetActiveProfile()
    if not _G.Languages_DB then return nil end
    if not _G.Languages_DB.profiles then return nil end

    local charKey = GetCharacterKey()
    local profile = _G.Languages_DB.profiles[charKey]

    -- Check for TRP3 profile if enabled
    if profile and profile.TRP3 and _G.TRP3_API then
        local trpProfile = _G.TRP3_API.profile.getPlayerCurrentProfile()
        if trpProfile and trpProfile.profileName then
            local trpKey = "TRP3_" .. trpProfile.profileName
            return _G.Languages_DB.profiles[trpKey] or profile
        end
    end

    return profile
end

-- ---------------------------------------------------------------------------
-- State Reading (from Languages UI elements)
-- ---------------------------------------------------------------------------

--- Check if prefix is enabled by reading LanguagesMainFrame.prefix
local function IsPrefixEnabled()
    local mainFrame = GetLanguagesMainFrame()
    if not mainFrame then
        return LanguagesBridge.cachedPrefixState
    end

    -- Read the prefix state directly from the frame
    local enabled = mainFrame.prefix == true
    LanguagesBridge.cachedPrefixState = enabled
    return enabled
end

--- Get current language name from the selection button text
local function GetCurrentLanguageName()
    local button = GetSelectionButton()
    if not button then
        return LanguagesBridge.cachedLanguage
    end

    local textObj = button.Text
    if not textObj then
        return LanguagesBridge.cachedLanguage
    end

    local langName = textObj:GetText()
    if langName and langName ~= "" then
        LanguagesBridge.cachedLanguage = langName
        return langName
    end

    return LanguagesBridge.cachedLanguage
end

--- Check TRP3 in-character status (mirrors Languages' logic)
local function ShouldProcessLanguage()
    local profile = GetActiveProfile()
    if not profile then return true end

    -- Check TRP3 in-character status
    if C_AddOns.IsAddOnLoaded("totalrp3") and profile.onlyInCharacter then
        if _G.TRP3_API and _G.AddOn_TotalRP3 then
            local user = _G.AddOn_TotalRP3.Player.GetCurrentUser()
            if user and user.IsInCharacter and not user:IsInCharacter() then
                return false
            end
        end
    end

    return true
end

--- Check faction rules (e.g., no prefix for Common on Alliance)
local function FactionCheck()
    if not _G.Languages_DB or not _G.Languages_DB.settings then
        return true
    end

    if _G.Languages_DB.settings.faction ~= true then
        return true
    end

    local currentName = GetCurrentLanguageName()
    if not currentName then
        return true
    end

    -- Get the "default" language for this faction
    local faction = UnitFactionGroup("player")
    local defaultLang = nil

    if faction == "Alliance" then
        defaultLang = "Common"
    elseif faction == "Horde" then
        defaultLang = "Orcish"
    elseif faction == "Neutral" then
        defaultLang = "Pandaren"
    end

    if not defaultLang then
        return true
    end

    -- Check if the current language is the faction default
    -- Try common localized names
    local localizedNames = {
        ["Common"] = "Common",
        ["Orcish"] = "Orcish",
        ["Pandaren"] = "Pandaren"
    }
    local localizedDefault = localizedNames[defaultLang]
    if localizedDefault and currentName == localizedDefault then
        return false
    end

    -- Also check if the raw name matches (fallback)
    if currentName == defaultLang then
        return false
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Dialect & Language Transform (via captured Languages mutator)
-- ---------------------------------------------------------------------------

--- Apply full Languages transformation using captured mutator
--- This calls Languages' actual ParseTokens function with dialects, prefix, and morphing
local function ApplyLanguagesTransform(text, chatType)
    if not LanguagesBridge._languagesMutator then
        return text -- No mutator available, return unchanged
    end

    -- Create a context that mimics what LibChatFilter provides
    local _, defaultLangID = GetDefaultLanguage()
    local context = {
        originalText = text,
        message = text,
        historyText = text,
        chatType = chatType or "SAY",
        target = nil,
        language = defaultLangID,
        editBox = nil
    }

    -- Call Languages' mutator - handles dialects, prefix, and morphing
    local result = LanguagesBridge._languagesMutator(text, context)
    if result and result ~= text then
        return result
    end
    return context.message -- Mutator may have modified context instead of returning
end

-- ---------------------------------------------------------------------------
-- Hook to track state changes
-- ---------------------------------------------------------------------------

local function InstallHooks()
    local mainFrame = GetLanguagesMainFrame()
    if not mainFrame then return end

    -- Hook SetLanguage to update our cache immediately
    if mainFrame.SetLanguage then
        local origSetLanguage = mainFrame.SetLanguage
        mainFrame.SetLanguage = function(self, langKey, ...)
            local result = origSetLanguage(self, langKey, ...)
            -- Force refresh of cache
            C_Timer.After(0, function()
                GetCurrentLanguageName()
            end)
            return result
        end
    end

    -- Hook TogglePrefix to update cache
    if mainFrame.TogglePrefix then
        local origToggle = mainFrame.TogglePrefix
        mainFrame.TogglePrefix = function(self, ...)
            local result = origToggle(self, ...)
            -- Update cache
            C_Timer.After(0, function()
                IsPrefixEnabled()
            end)
            return result
        end
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Called once from Chat:Init, after Router:Init has already cached
--- Router.SendChatMessage. At PLAYER_ENTERING_WORLD all addons are loaded.
---
--- @return boolean  true if Languages was found and the bridge is now active.
function LanguagesBridge:Init()
    if self.active then return true end

    -- Check if Languages is loaded
    if not C_AddOns.IsAddOnLoaded("Languages") then
        YapperTable.Utils:VerbosePrint("LanguagesBridge: Languages addon not found.")
        return false
    end

    -- Check for required global objects
    local mainFrame = GetLanguagesMainFrame()
    local button = GetSelectionButton()

    if not mainFrame then
        YapperTable.Utils:VerbosePrint("LanguagesBridge: LanguagesMainFrame not found. Bridge inactive.")
        return false
    end

    if not button then
        YapperTable.Utils:VerbosePrint("LanguagesBridge: LanguagesSelectionButton not found. Bridge inactive.")
        return false
    end

    -- Check if Yapper API is available
    if not _G.YapperAPI then
        YapperTable.Utils:VerbosePrint("LanguagesBridge: YapperAPI not found.")
        return false
    end

    -- Install hooks to track state changes
    InstallHooks()

    -- Register PRE_SEND filter with priority 20 (after default filters)
    -- This applies Languages' full transformation (dialects, prefix, morphing)
    self.filterHandle = _G.YapperAPI:RegisterFilter("PRE_SEND", function(payload)
        -- Only apply to SAY and YELL (same as Languages)
        if payload.chatType == "SAY" or payload.chatType == "YELL" then
            -- Apply Languages' full transformation via captured mutator
            payload.text = ApplyLanguagesTransform(payload.text, payload.chatType)
        end
        return payload
    end, 20)

    -- Register PRE_CHUNK filter to set continuation prefix
    -- The Languages mutator adds prefix to first chunk; we handle chunks 2+
    self.chunkFilterHandle = _G.YapperAPI:RegisterFilter("PRE_CHUNK", function(payload)
        -- Only apply to SAY and YELL (same as Languages addon)
        local chatType = payload.chatType
        if chatType ~= "SAY" and chatType ~= "YELL" then
            return payload
        end

        -- Check if we should inject language tag for continuation chunks
        if not IsPrefixEnabled() then
            return payload
        end
        if not ShouldProcessLanguage() then
            return payload
        end
        if not FactionCheck() then
            return payload
        end

        local langName = GetCurrentLanguageName()
        if not langName or langName == "" then
            return payload
        end

        -- Don't modify slash commands
        if payload.text:sub(1, 1) == "/" then
            return payload
        end

        -- Set continuation prefix for chunks 2+
        payload.continuationPrefix = "[" .. langName .. "] "

        return payload
    end, 10)

    -- Register with LibChatFilter for draft/preview text transformation
    -- We register at TRANSFORM stage and use the captured Languages mutator
    if LibStub then
        local success, LibChatFilter = pcall(LibStub.GetLibrary, LibStub, "LibChatFilter")
        if success and LibChatFilter then
            -- Register our transform at TRANSFORM stage (before Languages' EXCLUSIVE_TRANSFORM)
            LibChatFilter.RegisterTransform(function(text, context)
                -- Only apply to SAY and YELL
                if context.chatType ~= "SAY" and context.chatType ~= "YELL" then
                    return text
                end

                -- Use captured Languages mutator for full transformation
                if LanguagesBridge._languagesMutator then
                    local result = LanguagesBridge._languagesMutator(text, context)
                    if result and result ~= text then
                        return result
                    end
                    return context.message
                end

                -- No mutator available - return unchanged (Languages won't show in preview)
                return text
            end, LibChatFilter.Track.SEND)
            YapperTable.Utils:VerbosePrint("LanguagesBridge: LibChatFilter transform registered for draft preview.")
        end
    end

    self.active = true
    YapperTable.Utils:VerbosePrint("LanguagesBridge: Active! Language prefix will be applied to Yapper messages.")

    return true
end

--- Returns true if the bridge found Languages and is active.
function LanguagesBridge:IsActive()
    return self.active == true
end

-- ---------------------------------------------------------------------------
-- Event Registration (self-initialising)
-- ---------------------------------------------------------------------------

-- Main init frame - handles immediate and late loading scenarios
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Delay init to ensure both addons are fully loaded
        C_Timer.After(2, function()
            if not LanguagesBridge.active then
                LanguagesBridge:Init()
            end
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Capture Languages' mutator from LibChatFilter
-- ---------------------------------------------------------------------------

local function CaptureLanguagesMutator()
    if not LibStub then return false end

    local success, LibChatFilter = pcall(LibStub.GetLibrary, LibStub, "LibChatFilter")
    if not success or not LibChatFilter or not LibChatFilter.mutators then
        return false
    end

    -- Get the EXCLUSIVE_TRANSFORM stage mutators (where Languages registers ParseTokens)
    local exclusive = LibChatFilter.mutators[LibChatFilter.Stage.EXCLUSIVE_TRANSFORM]
    if exclusive and #exclusive > 0 then
        -- The first (and only) EXCLUSIVE_TRANSFORM mutator should be Languages' ParseTokens
        local languagesMutator = exclusive[1].func
        if languagesMutator then
            LanguagesBridge._languagesMutator = languagesMutator
            YapperTable.Utils:VerbosePrint("LanguagesBridge: Captured Languages LibChatFilter mutator!")
            return true
        end
    end

    return false
end

-- Try immediately, on ADDON_LOADED, and finally on PLAYER_ENTERING_WORLD
C_Timer.After(0, function()
    -- Immediate attempt - might work if Languages loaded before us
    LanguagesBridge:Init()
end)

C_Timer.After(3, CaptureLanguagesMutator)

local grabFrame = CreateFrame("Frame")
grabFrame:RegisterEvent("ADDON_LOADED")
grabFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
grabFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Languages" then
        C_Timer.After(1, function()
            -- Try to init bridge when Languages loads
            if not LanguagesBridge.active then
                LanguagesBridge:Init()
            end
            -- Try to capture mutator
            if CaptureLanguagesMutator() then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Final attempt: PLAYER_ENTERING_WORLD is the last event, all addons should be loaded
        C_Timer.After(2, function()
            if not LanguagesBridge._languagesMutator then
                YapperTable.Utils:VerbosePrint("LanguagesBridge: Final mutator capture attempt on PLAYER_ENTERING_WORLD...")
                if CaptureLanguagesMutator() then
                    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                end
            end
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Debug slash command
-- ---------------------------------------------------------------------------

_G.SLASH_LANGYAPPERBRIDGE1 = "/lyb"
SlashCmdList["LANGYAPPERBRIDGE"] = function()
    if not LanguagesBridge.active then
        print("LanguagesBridge: Not active")
        return
    end

    local dialect = GetCurrentDialect()
    local langName = GetCurrentLanguageName()
    local prefixEnabled = IsPrefixEnabled()

    print("LanguagesBridge Status:")
    print("  Language: " .. tostring(langName))
    print("  Dialect: " .. tostring(dialect))
    print("  Prefix enabled: " .. tostring(prefixEnabled))
    print("  Should process: " .. tostring(ShouldProcessLanguage()))
    print("  Faction check: " .. tostring(FactionCheck()))

    -- Show mutator status (we rely on it for dialects)
    if dialect then
        if LanguagesBridge._languagesMutator then
            print("  Dialect handling: via Languages mutator (live)")
        else
            print("  Dialect handling: NO MUTATOR - dialects will not apply!")
        end
    end

    print("  _languagesMutator captured: " .. tostring(LanguagesBridge._languagesMutator ~= nil))
end
