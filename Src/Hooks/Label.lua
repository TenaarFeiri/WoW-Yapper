--[[
    Hooks/Label.lua
    Label refresh, channel cycling, and tab memory.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local Utils = YapperTable.Utils


-- Resolve locals from Hub.lua
-- Note: Hooks/Label.lua loads before Interface.lua, so use full path for Interface
local Core = YapperTable.EditBoxHooksCore
local CHATTYPE_TO_OVERRIDE_KEY = Core.CHATTYPE_TO_OVERRIDE_KEY
local GROUP_CHAT_TYPES = Core.GROUP_CHAT_TYPES
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

local IsUnambiguousBnetTarget = function(target) return Utils:IsUnambiguousBnetTarget(target) end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

function EditBox:RefreshLabel()
    local cfg = YapperTable.Config.EditBox or {}
    local target = Utils:SanitizeTarget(self.Target)
    if not target and self.Target then
        self.Target = nil
        self._secureReplySource = nil
    end

    -- Blizzard may report a plain WHISPER chatType for a BNet friend
    -- (presence/account ID). Prefer BN_WHISPER for label/colour so the
    -- overlay uses Battle.net defaults.
    local effectiveType = self.ChatType
    local currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    if currentKey == "WHISPER" and target and YapperTable.Router
        and IsUnambiguousBnetTarget(target)
        and type(YapperTable.Router.ResolveBnetTarget) == "function" then
        local presenceID, bnetAccountID = YapperTable.Router:ResolveBnetTarget(target)
        if presenceID or bnetAccountID then
            effectiveType = "BN_WHISPER"
            currentKey = "BN_WHISPER"
        end
    end

    local label, r, g, b = BuildLabelText(effectiveType, target, self.ChannelName)
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
    if (currentKey == "CHANNEL" or self.ChatType == "CHANNEL") and target and YapperTable.Router
        and YapperTable.Router.DetectCommunityChannel then
        local isClub = YapperTable.Router:DetectCommunityChannel(target)
        if isClub == true then
            currentKey = "CLUB"
        end
    end
    local masterKey = cfg.ChannelColorMaster
    local colorMode = cfg.ChannelColorMode
    local modeResolved = false

    if currentKey and type(colorMode) == "table" and type(colorMode[currentKey]) == "string" then
        local mode = colorMode[currentKey]

        if mode == "blizzard" then
            -- Blizzard mode: ChatTypeInfo has absolute precedence.
            if currentKey == "CHANNEL" and target then
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(target)]
                if info and type(info.r) == "number" then
                    resolvedR, resolvedG, resolvedB = info.r, info.g, info.b
                    modeResolved = true
                end
            elseif currentKey == "CLUB" and target then
                -- Community channels use CHANNEL# ChatTypeInfo
                local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. tostring(target)]
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
            -- Master mode: follow the master channel's colour.
            if YapperTable.Interface.IsColourTable(channelColors[masterKey]) then
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
    if not modeResolved and currentKey and YapperTable.Interface.IsColourTable(channelColors[currentKey]) then
        resolvedR, resolvedG, resolvedB = channelColors[currentKey].r, channelColors[currentKey].g, channelColors[currentKey].b
    end

    -- Reset to base font BEFORE measuring the background: UpdateLabel...
    -- measures at ChannelLabel's current font, and a previous AutoFitLabel
    -- refresh may have left it shrunk. Measuring at the leftover size
    -- produces a different LabelBg width each open (resize-on-reopen
    -- jitter); resetting makes width deterministic for a given label.
    ResetLabelToBaseFont(self)

    UpdateLabelBackgroundForText(self, label)

    local usableWidth = GetLabelUsableWidth(self)
    if self.ChannelLabel.SetWidth then
        self.ChannelLabel:SetWidth(usableWidth)
    end

    if cfg.AutoFitLabel == true then
        local fitOk = FitLabelFontToWidth(self, label, usableWidth)
        if not fitOk then
            label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
        end
    else
        label = TruncateLabelToWidth(self.ChannelLabel, label, usableWidth)
    end

    self.ChannelLabel:SetText(label)

    -- Theme colour applies only when the user's config still equals the
    -- defaults for that channel; skipped when "blizzard"/"master" mode
    -- already resolved.
    if not modeResolved and theme and type(theme.channelTextColors) == "table" and currentKey then
        local tcol = theme.channelTextColors[effectiveType] or theme.channelTextColors[currentKey]
        if YapperTable.Interface.IsColourTable(tcol) then
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

    -- Debug aid: log effective type/target/resolved colours.
    if Utils.DebugPrint then
        local whisperCol = (channelColors and channelColors.WHISPER) or nil
        local bnetCol = (channelColors and channelColors.BN_WHISPER) or nil
        local masterKeyStr = cfg.ChannelColorMaster or ""
        local overrideFlag = (cfg.ChannelColorOverrides and cfg.ChannelColorOverrides[currentKey]) or false
        local msg = string.format(
            "RefreshLabel: eff=%s ct=%s tgt=%s -> resolved=(%.2f,%.2f,%.2f) master=%s override=%s whisper=(%s) bn=(%s)",
            tostring(effectiveType), tostring(self.ChatType), tostring(target or ""),
            tonumber(resolvedR) or 0, tonumber(resolvedG) or 0, tonumber(resolvedB) or 0,
            tostring(masterKeyStr), tostring(overrideFlag),
            (whisperCol and string.format("%.2f,%.2f,%.2f", whisperCol.r, whisperCol.g, whisperCol.b) or "nil"),
            (bnetCol and string.format("%.2f,%.2f,%.2f", bnetCol.r, bnetCol.g, bnetCol.b) or "nil"))
        Utils:DebugPrint(msg)
    end

    if self.ChannelLabel then
        self.ChannelLabel:SetText(label)
        self.ChannelLabel:SetTextColor(resolvedR, resolvedG, resolvedB, 1)
    end

    if self.OverlayEdit then
        self.OverlayEdit:SetTextColor(resolvedR, resolvedG, resolvedB, 1)
    end

    if YapperTable.API then
        YapperTable.API:Fire("EDITBOX_LABEL_UPDATED", label, resolvedR, resolvedG, resolvedB)
    end

    -- Sync channel/target back to Blizzard's editbox so the proxy
    -- background (or any visible native chrome) shows the matching outline
    -- colour and channel context. Safe to call repeatedly.
    self:SyncAttributesToBlizzard()

    -- Keep the proxy background visible after attribute sync.
    if self.EnsureProxyBackgroundShown then
        self:EnsureProxyBackgroundShown()
    end
end

--- Push Yapper's current chatType, target, channel and language into Blizzard's
--- native editbox. This keeps the Blizzard frame in sync (outline colour, etc.)
--- whenever Yapper changes channel, not just during lockdown handoffs.
function EditBox:SyncAttributesToBlizzard(allowLockdown)
    local yapperChatType = self.ChatType
    if not yapperChatType then return end

    -- Native attribute writes can taint Blizzard's header path during chat
    -- or combat lockdown; the native editbox stays authoritative unless the
    -- handoff explicitly requests a best-effort safe-state sync.
    local inLockdown = YapperTable.Utils and YapperTable.Utils:IsChatOrCombatLockdown()
    if inLockdown and not allowLockdown then
        return
    end

    local blizzEditBox = self.OrigEditBox
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
        or _G.ChatFrame1EditBox
    if not (blizzEditBox and blizzEditBox.SetAttribute) then return end

    -- Guard against our own SetAttribute hook calling RefreshLabel in a loop.
    self._syncingAttributes = true

    -- Resolve chat type to override key.
    local overrideCT = yapperChatType
    if yapperChatType == "PARTY_LEADER" then
        overrideCT = "PARTY"
    elseif yapperChatType == "RAID_LEADER" then
        overrideCT = "RAID"
    end

    -- Whispers: never write chatType/tellTarget/channelTarget/language to
    -- Blizzard's editbox. Blizzard owns tellTarget and normalises it (e.g.
    -- "Charname" -> "Charname-RealmName"), which can be secret under
    -- Midnight lockdown; a tainted write makes Blizzard's
    -- ClearChat/Deactivate/UpdateHeader chain later error on the secret.
    -- Yapper keeps chatType/target in its own state for the send path.
    if yapperChatType == "WHISPER" or yapperChatType == "BN_WHISPER" then
        self._syncingAttributes = nil
        return
    end

    blizzEditBox:SetAttribute("chatType", overrideCT)

    -- Keep Blizzard's stickyType in sync so its ResetChatTypeToSticky
    -- (called from Deactivate on handoff/ClearChat) reverts to the user's
    -- last channel instead of SAY -- Yapper's sends bypass Blizzard's
    -- pipeline, so stickyType would otherwise sit at the "SAY" default
    -- forever. Whispers are demoted out (matching
    -- ChannelPolicy:BuildPersistedLastUsed) so a transient whisper can't
    -- bleed onto the next non-whisper open. Safe: runs only while the
    -- overlay is open, inside the _syncingAttributes guard; stickyType isn't
    -- mirrored into LastUsed by the SetAttribute hook.
    blizzEditBox:SetAttribute("stickyType", overrideCT)

    if yapperChatType == "CHANNEL" then
        if self.Target then
            blizzEditBox:SetAttribute("channelTarget", self.Target)
        end
        blizzEditBox:SetAttribute("tellTarget", nil)
    else
        blizzEditBox:SetAttribute("tellTarget", nil)
        blizzEditBox:SetAttribute("channelTarget", nil)
    end

    if self.Language then
        blizzEditBox:SetAttribute("language", self.Language)
    else
        blizzEditBox:SetAttribute("language", nil)
    end

    -- UpdateHeader makes the attribute changes visible, as Blizzard does.
    if blizzEditBox.UpdateHeader and not inLockdown then
        pcall(function() blizzEditBox:UpdateHeader() end)
    end

    self._syncingAttributes = nil
end

--- Inverse of SyncAttributesToBlizzard: restore the Blizzard editbox to a neutral
--- sticky state when Yapper closes.
---
--- Why this is needed: GetChatType()/GetTellTarget() read directly from the
--- "chatType"/"tellTarget" secure attributes, which SyncAttributesToBlizzard
--- writes for colour parity while Yapper is open. In *classic* chatStyle,
--- Blizzard's ChatFrameEditBoxMixin:Deactivate() merely Hide()s the editbox and
--- skips ResetChatTypeToSticky (only the "im" branch resets). In proxy mode the
--- editbox stays live as the visible background, so a whisper context Yapper
--- pushed into it bleeds into the next open. Mirror Blizzard's own
--- ResetChatTypeToSticky so the proxy frame returns to its sticky type.
---
--- Dedicated whisper windows are unaffected: their stickyType is WHISPER and the
--- tellTarget is restored from chatFrame.chatTarget on the next activate.
function EditBox:ResetSyncedAttributes()
    local blizzEditBox = self.OrigEditBox
    if not (blizzEditBox and blizzEditBox.SetAttribute and blizzEditBox.GetAttribute) then
        return
    end
    if blizzEditBox == self.OverlayEdit then return end

    local sticky = blizzEditBox:GetAttribute("stickyType") or "SAY"
    if Utils:IsSecret(sticky) then return end

    -- Guard against our own SetAttribute hook looping / mirroring to LastUsed.
    self._syncingAttributes = true
    -- Never write chatType=WHISPER from tainted code: the tainted attribute
    -- makes Blizzard's ClearChat/Deactivate/UpdateHeader chain error on a
    -- secret tellTarget later. Non-whisper stickies still get chatType reset
    -- so the proxy frame returns to the sticky channel.
    if sticky ~= "WHISPER" and sticky ~= "BN_WHISPER" then
        blizzEditBox:SetAttribute("chatType", sticky)
    end
    -- ALWAYS clear tellTarget, even for whisper stickies: the native value
    -- may be Blizzard-normalised and secret under Midnight lockdown, so
    -- leaving it makes the Deactivate/ClearChat/UpdateHeader chain error.
    -- Dedicated whisper windows restore it from chatFrame.chatTarget on the
    -- next activate, so clearing is safe.
    blizzEditBox:SetAttribute("tellTarget", nil)
    if sticky ~= "CHANNEL" then
        blizzEditBox:SetAttribute("channelTarget", nil)
    end
    self._syncingAttributes = nil

    -- Keep the attribute cache consistent so the next Show() doesn't read
    -- a stale whisper target.
    if self._attrCache then
        self._attrCache[blizzEditBox] = {}
    end

    -- Refresh the header; pcall guards against residual secret arithmetic
    -- in Blizzard's UpdateHeader (it refreshes again on next activate).
    if blizzEditBox.UpdateHeader then
        pcall(function() blizzEditBox:UpdateHeader() end)
    end
end

--- Returns the subset of _TAB_CYCLE entries currently available to the player.
--- Pull safe native channel state back into Yapper after lockdown recovery.
function EditBox:ResyncFromBlizzardAfterLockdown()
    local blizzEditBox = self.OrigEditBox
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
        or _G.ChatFrame1EditBox
    if not (blizzEditBox and blizzEditBox.GetAttribute and Utils) then
        return false
    end

    local ok, chatType, tellTarget, channelTarget, language = pcall(function()
        return blizzEditBox:GetAttribute("chatType"),
            blizzEditBox:GetAttribute("tellTarget"),
            blizzEditBox:GetAttribute("channelTarget"),
            blizzEditBox:GetAttribute("language")
    end)
    if not ok or type(chatType) ~= "string" or Utils:IsSecret(chatType) then
        return false
    end

    tellTarget = Utils:SanitizeTarget(tellTarget)
    channelTarget = Utils:SanitizeTarget(channelTarget)
    if language and Utils:IsSecret(language) then
        language = nil
    end

    if (chatType == "WHISPER" or chatType == "BN_WHISPER") and not tellTarget then
        return false
    end
    if chatType == "CHANNEL" and not channelTarget then
        return false
    end

    self.ChatType = chatType
    self.Target = (chatType == "WHISPER" or chatType == "BN_WHISPER") and tellTarget
        or (chatType == "CHANNEL" and channelTarget or nil)
    self._secureReplySource = nil
    self.ChannelName = chatType == "CHANNEL"
        and ResolveChannelName(tonumber(channelTarget)) or nil
    self.Language = language
    self:PersistLastUsed()
    return true
end

function EditBox:GetAvailableChatTypes()
    local result = {}
    for _, chatType in ipairs(self._TAB_CYCLE) do
        if self:IsChatTypeAvailable(chatType) then
            result[#result + 1] = chatType
        end
    end
    return result
end

--- Cycle through available chat types.
--- @param direction number  1 for next, -1 for previous.
function EditBox:CycleChatType(direction)
    direction = direction or 1
    local current = self.ChatType or "SAY"

    -- When already in a whisper, cycle through recent reply targets instead.
    if current == "WHISPER" or current == "BN_WHISPER" then
        local nextName, nextKind = self:NextReplyTarget(self.Target, direction)
        if nextName then
            self.ChatType = nextKind or "WHISPER"
            self.Target   = nextName
            self._secureReplySource = nil
            self:RefreshLabel()
            if YapperTable.API then
                YapperTable.API:Fire("EDITBOX_CHANNEL_CHANGED", self.ChatType, self.Target)
            end
            return
        end
        -- No reply targets available; fall through to normal cycling.
    end

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

    -- Persist immediately under the current frame so the choice survives a tab
    -- switch even if the user never sends. Safe here: no switch is in flight, so
    -- OverlayEdit.chatFrame reliably points at the frame the user is looking at.
    self:RecordTabChannel()

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

    -- GetName can be restricted-adjacent in lockdown contexts.
    local ok, key = pcall(function() return chatFrame.GetName and chatFrame:GetName() end)
    if not ok or not key then return end

    self._tabChannelMemory = self._tabChannelMemory or {}
    self._tabChannelMemory[key] = entry
end

--- Save selection for stickiness across show/hide.
function EditBox:PersistLastUsed()
    local ct = self.ChatType
    local target = YapperTable.Utils and YapperTable.Utils:SanitizeTarget(self.Target) or nil
    local language = self.Language
    local channelName = self.ChannelName

    if (ct == "WHISPER" or ct == "BN_WHISPER") and not target then
        ct = "SAY"
        channelName = nil
    end

    -- NOTE: ChannelPolicy:BuildPersistedLastUsed demotes ALL whispers
    -- (typed and external) to the previous non-whisper sticky, so a whisper
    -- can never become the global LastUsed and bleed onto the general tab.
    -- Dedicated whisper tabs restore from chatTarget/frame context, not
    -- LastUsed, so they're unaffected.

    local policy = YapperTable.ChannelPolicy
    if policy and type(policy.SanitizeCommittedSelection) == "function" then
        local sanitized = policy:SanitizeCommittedSelection({
            chatType = ct,
            target = target,
            language = language,
            channelName = channelName,
        })
        if sanitized then
            ct = sanitized.chatType
            target = sanitized.target
            language = sanitized.language
            channelName = sanitized.channelName
        end
    end

    if ct and ct ~= "" then
        if policy and type(policy.BuildPersistedLastUsed) == "function" then
            local resolved = policy:BuildPersistedLastUsed({
                chatType = ct,
                target = target,
                language = language,
                channelName = channelName,
            }, self.LastUsed, YapperTable.Config and YapperTable.Config.EditBox, GROUP_CHAT_TYPES)
            if resolved then
                self.LastUsed = resolved
            end
        else
            -- Safe fallback mirrors existing sticky semantics.
            self.LastUsed = {
                chatType = ct,
                target   = target,
                language = language,
            }
        end
    end

    -- Session-only per-tab channel memory (non-whisper tabs).
    self:RecordTabChannel()
end


-- ---------------------------------------------------------------------------
-- Tab cycling
-- ---------------------------------------------------------------------------

function EditBox:OnTabPressed()
    if not self.Overlay or not self.Overlay:IsShown() then return end

    local text = YapperTable.Recolour.CanonicalText(self.OverlayEdit)
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
