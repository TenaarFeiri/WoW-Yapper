--[[
        GopherBridge (deprecation notifier)

        Yapper intentionally no longer supports LibGopher/CrossRP send delegation.
        This bridge now serves only this purpose:
            1) Detect LibGopher presence.
            2) Tell the user which addon likely owns it.
            3) Offer to disable that addon (with reload) and warn about breakage.
]]

local YapperName, YapperTable = ...

local GopherBridge       = {}
YapperTable.GopherBridge = GopherBridge

local type = type
local pcall = pcall
local tostring = tostring
local string_lower = string.lower
local string_find = string.find

GopherBridge.present = false
GopherBridge.ownerAddon = nil
GopherBridge._warnShown = false
GopherBridge._initAttempted = false
GopherBridge._sessionCheckDone = false
GopherBridge._preEditboxShowHandle = nil

local POPUP_KEY = "YAPPER_GOPHER_REMOVED_SUPPORT"

local function FindGopher()
    ---@diagnostic disable-next-line: undefined-field
    if _G.LibGopher and type(_G.LibGopher) == "table" then
        return _G.LibGopher
    end
    if _G.LibStub then
        local ok, lib = pcall(function(...) return _G.LibStub(...) end, "Gopher", true)
        if ok and lib then return lib end
    end
    return nil
end

local function IsAddonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded == true
end

local function GetAddonField(name, field)
    if not GetAddOnMetadata or type(name) ~= "string" then return nil end
    local ok, value = pcall(GetAddOnMetadata, name, field)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function FindLikelyOwnerAddon()
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    if not getInfo or not getNum then
        if IsAddonLoaded("CrossRP") then return "CrossRP" end
        return nil
    end

    local bestEmbedded = nil
    local bestMention = nil
    local num = getNum() or 0

    for i = 1, num do
        local name, title, _, loadable, reason = getInfo(i)
        if type(name) == "string" and name ~= "" then
            local loaded = IsAddonLoaded(name)
            local present = loadable == true
                or reason == "DISABLED"
                or reason == "INSECURE"
                or reason == "DEMAND_LOADED"
                or reason == nil

            if loaded and present then
                local embeds = GetAddonField(name, "X-Embeds") or ""
                local deps = GetAddonField(name, "Dependencies") or ""
                local optionalDeps = GetAddonField(name, "OptionalDeps") or ""
                local notes = GetAddonField(name, "Notes") or title or ""

                local haystack = string_lower(table.concat({
                    name,
                    title or "",
                    embeds,
                    deps,
                    optionalDeps,
                    notes,
                }, " "))

                if string_find(haystack, "gopher", 1, true) then
                    if string_find(string_lower(embeds), "gopher", 1, true)
                        or string_find(string_lower(deps), "gopher", 1, true)
                        or string_find(string_lower(optionalDeps), "gopher", 1, true) then
                        bestEmbedded = bestEmbedded or name
                    else
                        bestMention = bestMention or name
                    end
                end
            end
        end
    end

    if bestEmbedded then return bestEmbedded end
    if bestMention then return bestMention end
    if IsAddonLoaded("CrossRP") then return "CrossRP" end
    return nil
end

local function DisableAddon(name)
    if type(name) ~= "string" or name == "" then return end
    local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if disable then
        pcall(disable, name)
    end
end

local function ShowWarningPopup(ownerAddon)
    if GopherBridge._warnShown then return end

    local ownerText = ownerAddon or "Unknown addon"
    if not StaticPopupDialogs[POPUP_KEY] then
        StaticPopupDialogs[POPUP_KEY] = {
            text = "|cFFFF6600Warning: LibGopher detected|r\n\nDetected in: |cFFFFFFFF%s|r\n\nYapper intentionally removed LibGopher support. Keeping this addon active can break posting while using Yapper.\n\nYou can continue, or disable that addon now (requires reload).",
            button1 = "Keep Addon Enabled",
            button2 = "Disable + Reload",
            OnAccept = function()
                if YapperTable and YapperTable.Utils and YapperTable.Utils.Print then
                    YapperTable.Utils:Print("warn", "LibGopher remains enabled. Posting may break while using Yapper.")
                end
            end,
            OnCancel = function(_, data)
                local addon = data
                DisableAddon(addon)
                if ReloadUI then
                    ReloadUI()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show(POPUP_KEY, ownerText, nil, ownerAddon)
    GopherBridge._warnShown = true
end

local function TryDetectAndWarn()
    if GopherBridge._sessionCheckDone then return end
    GopherBridge._sessionCheckDone = true

    local gopher = FindGopher()
    if not gopher then return end

    GopherBridge._initAttempted = true
    GopherBridge.present = true
    GopherBridge.ownerAddon = FindLikelyOwnerAddon()

    local owner = GopherBridge.ownerAddon or "Unknown addon"
    if YapperTable and YapperTable.Utils and YapperTable.Utils.Print then
        YapperTable.Utils:Print("warn", "LibGopher detected (owner: " .. tostring(owner) .. "). Yapper no longer supports it.")
    end

    ShowWarningPopup(GopherBridge.ownerAddon)
end

function GopherBridge:IsPresent()
    return self.present == true
end

function GopherBridge:GetOwnerAddon()
    return self.ownerAddon
end

local function RegisterPreEditboxShowProbe()
    if GopherBridge._preEditboxShowHandle then return end
    if not _G.YapperAPI or type(_G.YapperAPI.RegisterFilter) ~= "function" then return end

    GopherBridge._preEditboxShowHandle = _G.YapperAPI:RegisterFilter("PRE_EDITBOX_SHOW", function(payload)
        TryDetectAndWarn()

        -- Detection is intentionally once per session.
        if GopherBridge._sessionCheckDone and GopherBridge._preEditboxShowHandle then
            _G.YapperAPI:UnregisterFilter(GopherBridge._preEditboxShowHandle)
            GopherBridge._preEditboxShowHandle = nil
        end

        return payload
    end, 1)
end

RegisterPreEditboxShowProbe()





