-- ---------------------------------------------------------------------------
-- Total RP 3 Bridge
-- ---------------------------------------------------------------------------
-- Bridges TRP3 features. Can/May be expanded as necessary.
-- ---------------------------------------------------------------------------

local _, YapperTable = ...

local TotalRP3Bridge = {}
YapperTable.TotalRP3Bridge = TotalRP3Bridge
TotalRP3Bridge._initialised = false

local function IsTRP3Loaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("totalRP3")
    end
    return _G.TRP3_API ~= nil or _G.AddOn_TotalRP3 ~= nil
end

local function IsUsableName(name)
    return type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT
end

local function PickRPNameFromTRP3API(unit)
    if not _G.TRP3_API then return nil end
    unit = unit or "player"

    -- Preferred: register API (current shown RP name for a unit)
    local registerAPI = _G.TRP3_API.register
    if registerAPI and type(registerAPI.getUnitRPName) == "function" then
        local ok, name = pcall(registerAPI.getUnitRPName, unit)
        if ok and IsUsableName(name) then
            return name
        end
    end

    -- Fallback: profile API first-name field (player profile only)
    if unit ~= "player" then
        return nil
    end
    local profileAPI = _G.TRP3_API.profile
    if profileAPI and type(profileAPI.getData) == "function" then
        local ok, firstName = pcall(profileAPI.getData, "player", "characteristics", "FN")
        if ok and IsUsableName(firstName) then
            return firstName
        end
    end

    return nil
end

local function PickRPNameFromTRP3User()
    if not (_G.AddOn_TotalRP3 and _G.AddOn_TotalRP3.Player and _G.AddOn_TotalRP3.Player.GetCurrentUser) then
        return nil
    end

    local okUser, user = pcall(_G.AddOn_TotalRP3.Player.GetCurrentUser)
    if not okUser or not user then return nil end

    if type(user.GetCustomColoredRoleplayingName) == "function" then
        local ok, name = pcall(function() return user:GetCustomColoredRoleplayingName() end)
        if ok and IsUsableName(name) then
            -- Strip color escapes if present so label text stays plain.
            name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if IsUsableName(name) then
                return name
            end
        end
    end

    return nil
end

function TotalRP3Bridge:GetUnitDisplayName(unit)
    unit = unit or "player"
    local fallback = UnitName and UnitName(unit) or "You"
    if not IsTRP3Loaded() then
        return fallback
    end

    local name = PickRPNameFromTRP3API(unit)
    if not name and unit == "player" then
        name = PickRPNameFromTRP3User()
    end
    return name or fallback
end

--- Returns the best available RP display name for the player when TRP3 is loaded.
--- Falls back to UnitName("player") if no TRP3 name can be resolved.
function TotalRP3Bridge:GetPlayerDisplayName()
    return self:GetUnitDisplayName("player")
end

--- Call once during startup (self-initialising).
function TotalRP3Bridge:Init()
    -- Prevent multiple initialisations
    if self._initialised then return end
    self._initialised = true

    if _G.YapperAPI and type(_G.YapperAPI.RegisterFilter) == "function" then
        self._labelFilterHandle = _G.YapperAPI:RegisterFilter("PRE_EDITBOX_LABEL", function(payload)
            if type(payload) ~= "table" then return payload end
            if payload.chatType ~= "EMOTE" then return payload end

            local unit = payload.unit or "player"
            local rpName = TotalRP3Bridge:GetUnitDisplayName(unit)
            if IsUsableName(rpName) then
                payload.label = rpName
            end
            return payload
        end, 10)
    end

    -- We only need to register the protocols if Yapper API is available.
    if not _G.YapperAPI then return end

    -- Declare the TRP3 link protocol as a known, first-class link type in Yapper.
    _G.YapperAPI:RegisterLinkProtocol("addon:totalrp3")

    -- Register the unformatted TRP3 text format as an atomic token.
    -- This prevents Yapper's chunker from splitting "[TRP3:Identifier]" links.
    _G.YapperAPI:RegisterAtomicPattern("%[TRP3:[^%]]+%]")

    -- Hook into TRP3's language system to catch their language changes
    if _G.AddOn_TotalRP3 and _G.AddOn_TotalRP3.Languages then
        local TRP3Languages = _G.AddOn_TotalRP3.Languages
        if TRP3Languages.setLanguage then
            hooksecurefunc(TRP3Languages, "setLanguage", function(language)
                if not language then return end

                -- Extract language ID from TRP3's Language object
                local languageID = language.GetID and language:GetID()
                local languageName = language.GetName and language:GetName()

                if languageID then
                    -- Check if this language is in our cache, rebuild if not
                    local foundInCache = false
                    for _, cachedID in pairs(YapperTable.SpokenLanguages or {}) do
                        if cachedID == languageID then
                            foundInCache = true
                            break
                        end
                    end

                    if not foundInCache then
                        YapperTable.Utils:VerbosePrint("TRP3 language " .. tostring(languageName) .. " not in cache, rebuilding")
                        if YapperTable.Core and YapperTable.Core.BuildLanguageCache then
                            YapperTable.Core:BuildLanguageCache()
                        end
                    end

                    -- Update Yapper's language state
                    if YapperTable.EditBox then
                        YapperTable.EditBox.Language = languageID
                        if YapperTable.EditBox.LastUsed then
                            YapperTable.EditBox.LastUsed.language = languageID
                        end
                    end

                    YapperTable.Utils:VerbosePrint("TRP3 language change: " .. tostring(languageName) .. " (ID: " .. tostring(languageID) .. ")")
                end
            end)
        end
    end
end

-- Defer initialisation until PLAYER_LOGIN to ensure Yapper is fully loaded
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local C_AddOns = C_AddOns or {}
        if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("totalRP3") then
            TotalRP3Bridge:Init()
        end
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "totalRP3" then
            TotalRP3Bridge:Init()
        end
    end
end)
