-- ---------------------------------------------------------------------------
-- Total RP 3 Bridge
-- ---------------------------------------------------------------------------
-- Bridges TRP3 features. Can/May be expanded as necessary.
-- ---------------------------------------------------------------------------

local _, YapperTable = ...

local TotalRP3Bridge = {}
YapperTable.TotalRP3Bridge = TotalRP3Bridge
TotalRP3Bridge._initialised = false

--- Call once during startup (self-initialising).
function TotalRP3Bridge:Init()
    -- Prevent multiple initialisations
    if self._initialised then return end
    self._initialised = true

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
