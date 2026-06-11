--[[
    Hooks/Label.lua
    Label refresh, channel cycling, and tab memory.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore
local CHATTYPE_TO_OVERRIDE_KEY = Core.CHATTYPE_TO_OVERRIDE_KEY
local BuildLabelText = Core.BuildLabelText
local GetLabelUsableWidth = Core.GetLabelUsableWidth
local ResetLabelToBaseFont = Core.ResetLabelToBaseFont
local TruncateLabelToWidth = Core.TruncateLabelToWidth
local FitLabelFontToWidth = Core.FitLabelFontToWidth
local UpdateLabelBackgroundForText = Core.UpdateLabelBackgroundForText

-- Re-localise Lua globals.
local type       = type
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_abs   = math.abs
local string     = string

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

function EditBox:RefreshLabel()
    local cfg = YapperTable.Config.EditBox or {}

    -- Detect BN targets: Blizzard may present a plain WHISPER chatType
    -- even when the target is a BNet friend (presence/account ID). When
    -- that is the case prefer BN_WHISPER for label and colour selection
    -- so the overlay uses the Battle.net defaults/config by default.
    local effectiveType = self.ChatType
    local currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    if currentKey == "WHISPER" and self.Target and YapperTable.Router
        and type(YapperTable.Router.ResolveBnetTarget) == "function" then
        local presenceID, bnetAccountID = YapperTable.Router:ResolveBnetTarget(self.Target)
        if presenceID or bnetAccountID then
            effectiveType = "BN_WHISPER"
            currentKey = "BN_WHISPER"
        end
    end

    local label, r, g, b = BuildLabelText(effectiveType, self.Target, self.ChannelName)
    local resolvedR, resolvedG, resolvedB = r, g, b

    -- Prefer user-defined channel text colours for the effective type
    -- (e.g. BN_WHISPER) so user-configured colours always take precedence.
    local channelColors = cfg.ChannelTextColors
    if channelColors and effectiveType and type(channelColors[effectiveType]) == "table" then
        local ucol = channelColors[effectiveType]
        if type(ucol.r) == "number" and type(ucol.g) == "number" and type(ucol.b) == "number" then
            resolvedR, resolvedG, resolvedB = ucol.r, ucol.g, ucol.b
        end
    end

    -- If a theme provides channel text colours and the config doesn't override,
    -- prefer the theme values so themes can style channel labels consistently.
    local theme
    if YapperTable.Theme and type(YapperTable.Theme.GetTheme) == "function" then
        theme = YapperTable.Theme:GetTheme()
    end

    if currentKey == nil then
        currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    end
    if (currentKey == "CHANNEL" or self.ChatType == "CHANNEL") and self.Target and YapperTable.Router
        and YapperTable.Router.DetectCommunityChannel then
        local isClub = YapperTable.Router:DetectCommunityChannel(self.Target)
        if isClub == true then
            currentKey = "CLUB"
        end
    end
    local masterKey = cfg.ChannelColorMaster
    local colorMode = cfg.ChannelColorMode
    local modeResolved = false

    -- Check channel colour mode
    if currentKey and type(colorMode) == "table" and type(colorMode[currentKey]) == "string" then
        local mode = colorMode[currentKey]

        if mode == "blizzard" then
            -- Blizzard mode: use ChatTypeInfo (absolute precedence)
            if currentKey == "CHANNEL" and self.Target then
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(self.Target)]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            elseif currentKey == "CLUB" and self.Target then
                -- Community channels use CHANNEL# ChatTypeInfo
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(self.Target)]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            else
                local info = ChatTypeInfo and ChatTypeInfo[currentKey]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            end
        elseif mode == "master" and currentKey and type(masterKey) == "string"
            and masterKey ~= "" and currentKey ~= masterKey then
            -- Master mode: follow master channel's colour
            if type(channelColors) == "table"
                and type(channelColors[masterKey]) == "table"
                and type(channelColors[masterKey].r) == "number"
                and type(channelColors[masterKey].g) == "number"
                and type(channelColors[masterKey].b) == "number" then
                resolvedR = channelColors[masterKey].r
                resolvedG = channelColors[masterKey].g
                resolvedB = channelColors[masterKey].b
                modeResolved = true
            elseif ChatTypeInfo and ChatTypeInfo[masterKey] then
                local info = ChatTypeInfo[masterKey]
                resolvedR = info.r or resolvedR
                resolvedG = info.g or resolvedG
                resolvedB = info.b or resolvedB
                modeResolved = true
            end
        end
    end

    -- Custom mode (or no mode set, or mode resolution failed): use ChannelTextColors
    if not modeResolved and currentKey and type(channelColors) == "table"
        and type(channelColors[currentKey]) == "table" then
        local own = channelColors[currentKey]
        if type(own.r) == "number" and type(own.g) == "number" and type(own.b) == "number" then
            resolvedR, resolvedG, resolvedB = own.r, own.g, own.b
        end
    end

    UpdateLabelBackgroundForText(self, label)

    local usableWidth = GetLabelUsableWidth(self)
    if self.ChannelLabel.SetWidth then
        self.ChannelLabel:SetWidth(usableWidth)
    end

    ResetLabelToBaseFont(self)

    if cfg.AutoFitLabel == true then
        local fitOk = FitLabelFontToWidth(self, label, usableWidth)
        if not fitOk then
            label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
        end
    else
        label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
    end

    self.ChannelLabel:SetText(label)

    -- Use theme colour *only* when the user's per‑channel config still equals the defaults
    -- (i.e. they haven't overridden that channel).  Otherwise stick with the configured value.
    -- Skip this entirely when mode is "blizzard" or "master" since those have absolute precedence.
    if not modeResolved and theme and type(theme.channelTextColors) == "table" and currentKey then
        local tcol = theme.channelTextColors[effectiveType] or theme.channelTextColors[currentKey]
        if tcol and type(tcol.r) == "number" and type(tcol.g) == "number" and type(tcol.b) == "number" then
            -- Only use theme colour when user's config colour matches defaults.
            local defaults = YapperTable.Core and YapperTable.Core.GetDefaults
                and YapperTable.Core:GetDefaults()
            local defColors = defaults and defaults.EditBox
                and defaults.EditBox.ChannelTextColors
                and defaults.EditBox.ChannelTextColors[currentKey]
            local userColor = channelColors and channelColors[currentKey]
            if defColors and userColor
                and math_abs((userColor.r or 0) - (defColors.r or 0)) < 0.01
                and math_abs((userColor.g or 0) - (defColors.g or 0)) < 0.01
                and math_abs((userColor.b or 0) - (defColors.b or 0)) < 0.01 then
                resolvedR, resolvedG, resolvedB = tcol.r, tcol.g, tcol.b
            end
        end
    end

    -- Debugging aid: log effective type, target, and chosen colours when DEBUG enabled.
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        local whisperCol = (channelColors and channelColors.WHISPER) or nil
        local bnetCol = (channelColors and channelColors.BN_WHISPER) or nil
        local masterKeyStr = cfg.ChannelColorMaster or ""
        local overrideFlag = (cfg.ChannelColorOverrides and cfg.ChannelColorOverrides[currentKey]) or false
        local msg = string.format(
            "RefreshLabel: eff=%s ct=%s tgt=%s -> resolved=(%.2f,%.2f,%.2f) master=%s override=%s whisper=(%s) bn=(%s)",
            tostring(effectiveType), tostring(self.ChatType), tostring(self.Target or ""),
            tonumber(resolvedR) or 0, tonumber(resolvedG) or 0, tonumber(resolvedB) or 0,
            tostring(masterKeyStr), tostring(overrideFlag),
            (whisperCol and string.format("%.2f,%.2f,%.2f", whisperCol.r, whisperCol.g, whisperCol.b) or "nil"),
            (bnetCol and string.format("%.2f,%.2f,%.2f", bnetCol.r, bnetCol.g, bnetCol.b) or "nil"))
        if YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint(msg)
        end
    end

    -- Update label text and colour
    if self.ChannelLabel then
        self.ChannelLabel:SetText(label)
        self.ChannelLabel:SetTextColor(resolvedR, resolvedG, resolvedB, 1)
    end

    -- Update overlay editbox text colour to match
    if self.OverlayEdit then
        self.OverlayEdit:SetTextColor(resolvedR, resolvedG, resolvedB, 1)
    end

    -- Update fill colour if configured
    if cfg.FillColour and type(cfg.FillColour) == "table" then
        self.OverlayEdit:SetTextColor(cfg.FillColour.r, cfg.FillColour.g, cfg.FillColour.b, cfg.FillColour.a or 1)
    end

    -- Fire label updated callback
    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_LABEL_UPDATED", label, resolvedR, resolvedG, resolvedB)
    end
end

--- Cycle through available chat types.
--- @param direction number  1 for next, -1 for previous.
function EditBox:CycleChatType(direction)
    direction = direction or 1
    local current = self.ChatType or "SAY"
    local available = self:GetAvailableChatTypes()
    if #available == 0 then return end

    local currentIndex
    for i, chatType in ipairs(available) do
        if chatType == current then
            currentIndex = i
            break
        end
    end

    if not currentIndex then
        currentIndex = 1
    end

    local nextIndex = ((currentIndex - 1 + direction) % #available) + 1
    local nextType = available[nextIndex]

    -- Reset target when switching types (except whispers)
    if nextType ~= "WHISPER" and nextType ~= "BN_WHISPER" then
        self.Target = nil
        self.ChannelName = nil
    end

    self.ChatType = nextType
    self:RefreshLabel()

    -- Fire channel changed callback
    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", nextType, self.Target)
    end
end

--- Record the current channel for the active tab (session-only).
--- Skips whisper tabs, which are handled by Blizzard's chatTarget.
--- @param entry table|nil  Explicit values to store; defaults to current state.
function EditBox:RecordTabChannel(entry)
    entry = entry or {
        chatType    = self.ChatType,
        target      = self.Target,
        channelName = self.ChannelName,
        language    = self.Language,
    }

    -- Skip whisper tabs (Blizzard handles these via chatTarget)
    if entry.chatType == "WHISPER" or entry.chatType == "BN_WHISPER" then
        return
    end

    local chatFrame = self.OverlayEdit and self.OverlayEdit.chatFrame
    if not chatFrame then return end

    local key = chatFrame.GetName and chatFrame:GetName()
    if not key then return end

    self._tabChannelMemory = self._tabChannelMemory or {}
    self._tabChannelMemory[key] = entry
end

--- Save selection for stickiness across show/hide.
function EditBox:SaveLastUsed()
    if self.ChatType and self.ChatType ~= "" then
        self.LastUsed = {
            chatType = self.ChatType,
            target   = self.Target,
            language = self.Language,
        }
    end

    -- Session-only per-tab channel memory (non-whisper tabs).
    self:RecordTabChannel()
end


-- ---------------------------------------------------------------------------
-- Tab cycling
-- ---------------------------------------------------------------------------

function EditBox:OnTabPressed()
    if not self.Overlay or not self.Overlay:IsShown() then return end

    local text = self.OverlayEdit:GetText() or ""
    local trimmed = text:match("^%s*(.-)%s*$") or ""

    -- If empty, cycle chat types
    if trimmed == "" then
        self:CycleChatType(1)
        return
    end

    -- If text exists, use autocomplete
    local ac = YapperTable.Autocomplete
    if ac and ac.OnTabPressed then
        ac:OnTabPressed()
    end
end
