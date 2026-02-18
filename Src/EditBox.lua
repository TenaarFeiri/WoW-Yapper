--[[
    Taint-free overlay that replaces Blizzard's chat input.

    Since WoW 12.0.0 any addon touching the default EditBox taints it,
    which blocks SendChatMessage during encounters.  We sidestep this by
    hooking Show() (taint-safe), hiding Blizzard's box, and presenting
    our own overlay in the same spot.  The overlay was never part of the
    protected hierarchy so it can send freely even in combat.
    We then defer back to Blizzard's own editbox under lockdown.
]]

local YapperName, YapperTable  = ...

local EditBox                  = {}
YapperTable.EditBox            = EditBox

-- Overlay widgets (created lazily).
EditBox.Overlay                = nil
EditBox.OverlayEdit            = nil
EditBox.ChannelLabel           = nil
EditBox.LabelBg                = nil

-- State.
EditBox.HookedBoxes            = {}
EditBox.OrigEditBox            = nil
EditBox.ChatType               = nil
EditBox.Language               = nil
EditBox.Target                 = nil
EditBox.ChannelName            = nil
EditBox.LastUsed               = {}
EditBox.HistoryIndex           = nil
EditBox.HistoryCache           = nil
EditBox.PreShowCheck           = nil
EditBox._attrCache             = {}
EditBox._lockdownTicker        = nil
EditBox._lockdownHandedOff     = false

-- Slash command → chatType.
local SLASH_MAP                = {
    s           = "SAY",
    say         = "SAY",
    y           = "YELL",
    yell        = "YELL",
    e           = "EMOTE",
    em          = "EMOTE",
    emote       = "EMOTE",
    me          = "EMOTE",
    p           = "PARTY",
    party       = "PARTY",
    i           = "INSTANCE_CHAT",
    instance    = "INSTANCE_CHAT",
    g           = "GUILD",
    guild       = "GUILD",
    o           = "OFFICER",
    officer     = "OFFICER",
    ra          = "RAID",
    raid        = "RAID",
    rw          = "RAID_WARNING",
    raidwarning = "RAID_WARNING",
}

-- Tab-cycle order.
local TAB_CYCLE                = {
    "SAY", "EMOTE", "YELL", "PARTY", "INSTANCE_CHAT",
    "RAID", "RAID_WARNING", "GUILD", "OFFICER",
}

-- Pretty names for the channel label.
local LABEL_PREFIXES           = {
    SAY           = "Say",
    EMOTE         = "Emote",
    YELL          = "Yell",
    PARTY         = "Party",
    PARTY_LEADER  = "Party Leader",
    RAID          = "Raid",
    RAID_LEADER   = "Raid Leader",
    RAID_WARNING  = "Raid Warning",
    INSTANCE_CHAT = "Instance",
    GUILD         = "Guild",
    OFFICER       = "Officer",
    WHISPER       = "Whisper",
    CHANNEL       = "Channel",
}

-- Hot-path locals
local strmatch                 = string.match
local strlower                 = string.lower
local strbyte                  = string.byte

-- Chat types that are always sticky when in a group, even if StickyChannel is off.
local GROUP_CHAT_TYPES         = {
    PARTY         = true,
    PARTY_LEADER  = true,
    INSTANCE_CHAT = true,
    RAID          = true,
    RAID_LEADER   = true,
    RAID_WARNING  = true,
}

local CHATTYPE_TO_OVERRIDE_KEY = {
    SAY = "SAY",
    YELL = "YELL",
    PARTY = "PARTY",
    PARTY_LEADER = "PARTY",
    WHISPER = "WHISPER",
    INSTANCE_CHAT = "INSTANCE_CHAT",
    RAID = "RAID",
    RAID_LEADER = "RAID",
    RAID_WARNING = "RAID_WARNING",
}

local function IsWIMFocusActive()
    ---@diagnostic disable-next-line: undefined-field
    local wim = _G.WIM or nil
    if not wim then
        return false
    end
    local focus = wim.EditBoxInFocus or nil
    if not focus then
        return false
    end

    local shown = focus.IsShown and focus:IsShown()
    local visible = focus.IsVisible and focus:IsVisible()
    local focused = focus.HasFocus and focus:HasFocus()
    return shown == true or visible == true or focused == true
end

local function SetFrameFillColor(frame, r, g, b, a)
    if not frame then return end
    if not frame._yapperSolidFill then
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(frame)
        frame._yapperSolidFill = tex
    end
    frame._yapperSolidFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
end



-- Resolve a numeric channel ID to its display name, or nil.
local function ResolveChannelName(id)
    id = tonumber(id)
    if not id or id == 0 then return nil end
    if not GetChannelName then return nil end

    local cid, cname = GetChannelName(id)
    if tonumber(cid) == 0 then return nil end
    if type(cname) == "string" and cname ~= "" then
        return cname
    end
    return nil
end

-- Build the label string and colour for a given chat mode.
local function BuildLabelText(chatType, target, channelName)
    local label
    if chatType == "WHISPER" and target then
        label = "To: " .. target
    elseif chatType == "EMOTE" then
        -- Show the player's character name for emotes.
        local name = UnitName and UnitName("player") or "You"
        label = name
    elseif chatType == "CHANNEL" then
        if channelName and channelName ~= "" then
            label = channelName
        elseif target then
            label = "Channel #" .. tostring(target)
        else
            label = "Channel"
        end
    else
        local pretty = LABEL_PREFIXES[chatType]
        label = pretty or (chatType or "Say")
    end

    -- Colour from ChatTypeInfo.
    local r, g, b = 1, 0.82, 0 -- gold fallback
    if chatType and ChatTypeInfo and ChatTypeInfo[chatType] then
        local info = ChatTypeInfo[chatType]
        r, g, b = info.r or r, info.g or g, info.b or b
    end

    return label, r, g, b
end

local function GetLabelUsableWidth(self)
    if not self or not self.LabelBg then return 80 end
    local rawWidth = self.LabelBg:GetWidth() or 100
    return math.max(40, rawWidth - 10)
end

local function ResetLabelToBaseFont(self)
    if not self or not self.ChannelLabel then return end
    if self.OverlayEdit and self.OverlayEdit.GetFont then
        local face, size, flags = self.OverlayEdit:GetFont()
        if face and size then
            self.ChannelLabel:SetFont(face, size, flags or "")
            return
        end
    end

    if self.OrigEditBox and self.OrigEditBox.GetFontObject then
        local fontObj = self.OrigEditBox:GetFontObject()
        if fontObj then
            self.ChannelLabel:SetFontObject(fontObj)
        end
    end
end

local function TruncateLabelToWidth(fontString, text, maxWidth)
    if not fontString or type(text) ~= "string" then
        return text
    end

    fontString:SetText(text)
    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return text
    end

    local truncated = text
    while #truncated > 0 do
        truncated = truncated:sub(1, #truncated - 1)
        local candidate = truncated .. "..."
        fontString:SetText(candidate)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            return candidate
        end
    end

    return "..."
end

local function FitLabelFontToWidth(self, text, maxWidth)
    if not self or not self.ChannelLabel then return false end

    local fontString = self.ChannelLabel
    fontString:SetText(text)

    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return true
    end

    local face, size, flags = fontString:GetFont()
    if not face or not size then
        return false
    end

    local minSize = 8
    local targetSize = math.floor(size)
    while targetSize > minSize do
        targetSize = targetSize - 1
        fontString:SetFont(face, targetSize, flags or "")
        fontString:SetText(text)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Overlay creation
-- ---------------------------------------------------------------------------

local function UpdateLabelBackgroundForText(self, text)
    if not self or not self.LabelBg or not self.ChannelLabel then return end
    local cfg = YapperTable.Config.EditBox or {}
    local ebWidth = (self.OrigEditBox and self.OrigEditBox.GetWidth and self.OrigEditBox:GetWidth())
        or (self.Overlay and self.Overlay.GetWidth and self.Overlay:GetWidth())
        or 350
    local maxAllowed = math.floor(ebWidth * 0.28)
    local padding = (cfg.LabelPadding and tonumber(cfg.LabelPadding)) or 20
    -- Temporarily set text to measure raw width using current font settings.
    self.ChannelLabel:SetText(text)
    local rawWidth = (self.ChannelLabel:GetStringWidth() or 0)
    local needed = math.ceil(rawWidth + padding)
    local labelW = math.max(80, math.min(needed, maxAllowed, ebWidth - 80))
    self.LabelBg:SetWidth(labelW)
end


function EditBox:CreateOverlay()
    if self.Overlay then return end

    local cfg = YapperTable.Config.EditBox or {}
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}

    -- Container frame — matches position/size of the original editbox.
    local frame = CreateFrame("Frame", "YapperOverlayFrame", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Container background fill (flat colour only).
    SetFrameFillColor(frame, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)

    -- ── Label background (left portion) ──────────────────────────────
    local labelBg = CreateFrame("Frame", nil, frame)
    SetFrameFillColor(labelBg, labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 0.9)
    labelBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    labelBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    labelBg:SetWidth(100) -- will be recalculated on show

    local labelFs = labelBg:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    labelFs:SetPoint("CENTER", labelBg, "CENTER", 0, 0)
    labelFs:SetJustifyH("CENTER")

    -- ── Input EditBox (right portion) ────────────────────────────────
    local edit = CreateFrame("EditBox", "YapperOverlayEditBox", frame)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(true)
    edit:SetMultiLine(false)
    edit:SetMaxLetters(0)
    edit:SetMaxBytes(0)

    local tc = cfg.TextColor or {}
    edit:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1, tc.a or 1)
    edit:SetTextInsets(6, 6, 0, 0)

    -- Anchor edit to the right of the label.
    edit:SetPoint("TOPLEFT", labelBg, "TOPRIGHT", 1, 0)
    edit:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- Store references.
    self.Overlay      = frame
    self.OverlayEdit  = edit
    self.ChannelLabel = labelFs
    self.LabelBg      = labelBg

    -- ── Wire up scripts ──────────────────────────────────────────────
    self:SetupOverlayScripts()

    -- Hook into SendChatMessage so we can capture and propagate chatType, language and target
    -- to Yapper for synchronisity.
    if not self._cChatInfoSendHooked then
        self._cChatInfoSendHooked = true
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            hooksecurefunc(C_ChatInfo, "SendChatMessage", function(message, chatType, language, target)
                if not chatType or chatType == "BN_WHISPER" then return end
                if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
                    -- Update the LastUsed vars
                    self.LastUsed.chatType = chatType
                    self.LastUsed.target = target
                    self.LastUsed.language = language

                    self.ChatType = chatType
                    self.Target = target
                    self.Language = language
                    if chatType == "CHANNEL" and target then
                        local num = tonumber(target)
                        if num then
                            self.ChannelName = ResolveChannelName(num)
                        else
                            self.ChannelName = nil
                        end
                    else
                        self.ChannelName = nil
                    end

                    self._lastSavedDuringLockdown = true
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Script handlers
-- ---------------------------------------------------------------------------

function EditBox:SetupOverlayScripts()
    local edit         = self.OverlayEdit
    local frame        = self.Overlay

    -- When true, we're changing text programmatically (skip OnTextChanged).
    local updatingText = false

    -- ── OnTextChanged: slash-command channel switches ──────────────────
    edit:SetScript("OnTextChanged", function(box, isUserInput)
        if updatingText then return end
        if not isUserInput then return end

        local text = box:GetText() or ""
        if strbyte(text, 1) ~= 47 then -- '/'
            self.HistoryIndex = nil
            self.HistoryCache = nil
            return
        end

        -- Bare numeric channel: "/2 message"
        local num, rest = strmatch(text, "^/(%d+)%s+(.*)")
        if num then
            local resolved = ResolveChannelName(tonumber(num))
            if resolved then
                self.ChatType    = "CHANNEL"
                self.Target      = num
                self.ChannelName = resolved
                self.Language    = nil
                updatingText     = true
                box:SetText(rest or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest or ""))
            end
            return
        end

        -- "/cmd rest" — need a space before we act.
        local cmd, rest2 = strmatch(text, "^/([%w_]+)%s+(.*)")
        if not cmd then return end
        cmd = strlower(cmd)

        -- /c, /channel — wait for a space after the channel ID too,
        -- so we don't fire while the user is still typing it.
        if cmd == "c" or cmd == "channel" then
            local ch, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if ch then
                local chNum = tonumber(ch)
                if chNum then
                    local resolved = ResolveChannelName(chNum)
                    if not resolved then return end
                    self.ChatType    = "CHANNEL"
                    self.Target      = tostring(chNum)
                    self.ChannelName = resolved
                else
                    self.ChatType    = "CHANNEL"
                    self.Target      = ch
                    self.ChannelName = nil
                end
                self.Language = nil
                updatingText = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t" then
            local target, remainder = strmatch(rest2 or "", "^(%S+)%s+(.*)")
            if target then
                self.ChatType = "WHISPER"
                self.Target   = target
                self.Language = nil
                updatingText  = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        if cmd == "r" or cmd == "reply" then
            local lastTell
            if ChatEdit_GetLastTellTarget then
                lastTell = ChatEdit_GetLastTellTarget()
            end
            if lastTell and lastTell ~= "" then
                self.ChatType = "WHISPER"
                self.Target   = lastTell
                self.Language = nil
                updatingText  = true
                box:SetText(rest2 or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest2 or ""))
            end
            return
        end

        if SLASH_MAP[cmd] then
            self.ChatType = SLASH_MAP[cmd]
            self.Target   = nil
            self.Language = nil
            updatingText  = true
            box:SetText(rest2 or "")
            updatingText = false
            self:RefreshLabel()
            box:SetCursorPosition(#(rest2 or ""))
            return
        end
    end)

    edit:SetScript("OnEnterPressed", function(box)
        local text = box:GetText() or ""
        local trimmed = strmatch(text, "^%s*(.-)%s*$") or ""

        if trimmed == "" then
            if self._openedFromBnetTransition
                and self.ChatType
                and self.ChatType ~= "BN_WHISPER" then
                self._preferStickyAfterBnet = true
            end
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft()
            end
            self:PersistLastUsed()
            self:Hide()
            return
        end

        -- Slash commands: some (/w Name, /r) won't have been consumed by
        -- OnTextChanged because it waits for a trailing space. Handle
        -- those here before forwarding anything unrecognised to Blizzard.
        if strbyte(trimmed, 1) == 47 then -- '/'
            local enterCmd, enterRest = strmatch(trimmed, "^/([%w_]+)%s*(.*)")
            if enterCmd then
                enterCmd = strlower(enterCmd)

                if enterCmd == "w" or enterCmd == "whisper"
                    or enterCmd == "tell" or enterCmd == "t" then
                    local target = strmatch(enterRest or "", "^(%S+)")
                    if target then
                        self.ChatType = "WHISPER"
                        self.Target   = target
                        self.Language = nil
                        -- Fix: Use self.OrigEditBox (eb was undefined here).
                        -- This suppresses the Blizzard UI 'ghost' when switching to whisper modes.
                        local eb      = self.OrigEditBox
                        if eb and eb.Hide and eb:IsShown() then
                            eb:Hide()
                        end
                        box:SetText("")
                        updatingText = false
                        self:RefreshLabel()
                        -- Don't close — user now has an empty whisper box.
                        return
                    end
                end

                if enterCmd == "r" or enterCmd == "reply" then
                    local lastTell
                    if ChatEdit_GetLastTellTarget then
                        lastTell = ChatEdit_GetLastTellTarget()
                    end
                    if lastTell and lastTell ~= "" then
                        self.ChatType = "WHISPER"
                        self.Target   = lastTell
                        self.Language = nil
                        updatingText  = true
                        box:SetText(enterRest or "")
                        updatingText = false
                        self:RefreshLabel()
                        box:SetCursorPosition(#(enterRest or ""))
                        return
                    end
                end

                if enterCmd == "c" or enterCmd == "channel" then
                    local ch = strmatch(enterRest or "", "^(%S+)")
                    if ch then
                        local chNum = tonumber(ch)
                        if chNum then
                            local resolved = ResolveChannelName(chNum)
                            if resolved then
                                self.ChatType    = "CHANNEL"
                                self.Target      = tostring(chNum)
                                self.ChannelName = resolved
                                self.Language    = nil
                                updatingText     = true
                                box:SetText("")
                                updatingText = false
                                self:RefreshLabel()
                                return
                            end
                        else
                            self.ChatType    = "CHANNEL"
                            self.Target      = ch
                            self.ChannelName = nil
                            self.Language    = nil
                            updatingText     = true
                            box:SetText("")
                            updatingText = false
                            self:RefreshLabel()
                            return
                        end
                    end
                end

                if SLASH_MAP[enterCmd] then
                    self.ChatType = SLASH_MAP[enterCmd]
                    self.Target   = nil
                    self.Language = nil
                    updatingText  = true
                    box:SetText(enterRest or "")
                    updatingText = false
                    self:RefreshLabel()
                    box:SetCursorPosition(#(enterRest or ""))
                    if (enterRest or "") == "" then
                        return
                    end
                    -- Text after the command — fall through to send.
                end
            end

            if strbyte(trimmed, 1) == 47 then -- '/'
                self._closedClean = true
                if YapperTable.History then
                    YapperTable.History:ClearDraft()
                    -- Add regular slash commands to history (no channel context).
                    YapperTable.History:AddChatHistory(trimmed, nil, nil)
                end
                self:ForwardSlashCommand(trimmed)
                self:Hide()
                return
            end
        end

        -- If chat is locked down (combat/m+ lockdown), save draft and handoff
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
            self:HandoffToBlizzard()
            return
        end

        if self.OnSend then
            self.OnSend(trimmed, self.ChatType or "SAY", self.Language, self.Target)
        else
            if C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(trimmed, self.ChatType or "SAY", self.Language, self.Target)
            end
        end

        if self.OrigEditBox then
            self.OrigEditBox:AddHistoryLine(text)
        end

        self._closedClean = true
        if YapperTable.History then
            YapperTable.History:ClearDraft()
        end
        self:PersistLastUsed()
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
            YapperTable.TypingTrackerBridge:OnOverlaySent()
        end
        self:Hide()
    end)

    edit:SetScript("OnEscapePressed", function(box)
        local text = box:GetText() or ""
        if text == "" then
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft()
            end
        else
            -- User bailed with text in the box
            -- Draft is saved in OnHide below.
            self._closedClean = false
        end
        box:SetText("")
        self:Hide()
    end)

    edit:HookScript("OnKeyDown", function(box, key)
        if key == "TAB" then
            self:CycleChat(IsShiftKeyDown() and -1 or 1)
        elseif key == "UP" then
            self:NavigateHistory(-1)
        elseif key == "DOWN" then
            self:NavigateHistory(1)
        end
    end)

    frame:SetScript("OnHide", function()
        self.HistoryIndex = nil
        self.HistoryCache = nil

        if not self._closedClean and YapperTable.History then
            local eb = self.OverlayEdit
            if eb then
                local text = eb:GetText() or ""
                if text ~= "" then
                    YapperTable.History:SaveDraft(eb)
                    -- Normal (non-lockdown) saves should not be treated
                    -- as lockdown drafts.
                    self._lastSavedDraftIsLockdown = false
                end
                YapperTable.History:MarkDirty(true)
            end
        end
        self._closedClean = false
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
            YapperTable.TypingTrackerBridge:OnOverlayFocusLost()
        end
    end)

    -- Combat lockdown detection
    -- When InChatMessagingLockdown becomes true mid-typing, hand the
    -- overlay state back to Blizzard's secure editbox.
    -- Lockdown may activate slightly AFTER PLAYER_REGEN_DISABLED, so
    -- we poll briefly via a ticker if the first check is negative.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

    -- Also we want to watch for when the user shows or hides their UI, to close our editbox.
    UIParent:HookScript("OnHide", function()
        -- Make sure we're hidden.
        if EditBox.Overlay and EditBox.Overlay:IsShown() then
            EditBox:Hide()
        end
    end)

    frame:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or event == "CHALLENGE_MODE_START" then
            -- Immediate check.
            if C_ChatInfo.InChatMessagingLockdown
                and C_ChatInfo.InChatMessagingLockdown() then
                self:HandoffToBlizzard()
                return
            end
            -- Not in lockdown yet — poll briefly.
            if self._lockdownTicker then
                self._lockdownTicker:Cancel()
            end
            local ticks = 0
            self._lockdownTicker = C_Timer.NewTicker(0.1, function(ticker)
                ticks = ticks + 1
                if not self.Overlay or not self.Overlay:IsShown() then
                    ticker:Cancel()
                    self._lockdownTicker = nil
                    return
                end
                if C_ChatInfo.InChatMessagingLockdown
                    and C_ChatInfo.InChatMessagingLockdown() then
                    self:HandoffToBlizzard()
                    ticker:Cancel()
                    self._lockdownTicker = nil
                    return
                end
                if ticks >= 20 then -- 2 seconds
                    ticker:Cancel()
                    self._lockdownTicker = nil
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "CHALLENGE_MODE_COMPLETED" then
            -- Combat / M+ over — cancel polling if still running.
            if self._lockdownTicker then
                self._lockdownTicker:Cancel()
                self._lockdownTicker = nil
            end
            -- If we saved a draft during lockdown, poll until lockdown
            -- is truly over (checks every 1s for up to 5s).
            if self._lockdownHandedOff then
                local checks = 0
                C_Timer.NewTicker(1, function(ticker)
                    checks = checks + 1
                    if not C_ChatInfo.InChatMessagingLockdown
                        or not C_ChatInfo.InChatMessagingLockdown() then
                        self._lockdownHandedOff = false
                        -- If Blizzard sends during lockdown changed the channel,
                        -- persist that sticky choice now.
                        if self._lastSavedDuringLockdown then
                            self:PersistLastUsed()
                            self._lastSavedDuringLockdown = nil
                        end
                        -- Allow Show-hook lockdown logic to run again after lockdown.
                        self._lockdownShowHandled = false
                        YapperTable.Utils:Print("info", "Lockdown ended — press Enter to resume typing.")
                        ticker:Cancel()
                        return
                    end
                    if checks >= 5 then
                        ticker:Cancel()
                    end
                end)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------

--- Present the overlay in place of a Blizzard editbox.
--- @param origEditBox table  The Blizzard ChatFrameNEditBox we're replacing.
function EditBox:Show(origEditBox)
    -- Don't want to open the overlay while UI is hidden.
    if not UIParent:IsShown() then
        if EditBox.Overlay and EditBox.Overlay:IsShown() then
            EditBox:Hide()
        end
        return
    end
    self:CreateOverlay()

    local openedFromBnetTransition   = self._nextShowFromBnetTransition == true
    self._nextShowFromBnetTransition = false
    self._openedFromBnetTransition   = openedFromBnetTransition

    self.OrigEditBox                 = origEditBox

    -- Determine chat mode and target
    -- Two paths exist in Blizzard's code:
    --   • BNet whisper: SetAttribute fires BEFORE Show (cache is populated)
    --   • WoW friend whisper: SendTellWithMessage → OpenChat → Show fires
    --     first, then OnUpdate defers SetText + ParseText which sets
    --     attributes one frame later.
    -- For the deferred case our SetAttribute hook performs a live update
    -- of the overlay when the attributes finally arrive (see
    -- HookBlizzardEditBox).  Here we just read whatever is available now.
    --
    -- Priority:
    --   1. SetAttribute cache (chatType, tellTarget, channelTarget)
    --   2. GetAttribute fallback (in case anything was set before we hooked)
    --   3. LastUsed sticky
    --   4. "SAY"

    local cache                      = self._attrCache[origEditBox] or {}
    local blizzType                  = cache.chatType or (origEditBox and origEditBox:GetAttribute("chatType"))
    local blizzTell                  = cache.tellTarget or (origEditBox and origEditBox:GetAttribute("tellTarget"))
    local blizzChan                  = cache.channelTarget or (origEditBox and origEditBox:GetAttribute("channelTarget"))
    local blizzLang                  = cache.language or (origEditBox and origEditBox:GetAttribute("language"))
    local blizzText                  = origEditBox and origEditBox.GetText and origEditBox:GetText()

    -- One-shot BN guard expiry: if we open normally a couple times without
    -- consuming this flag, treat it as stale and clear it.
    if self._ignoreNextBnetLiveUpdateFor then
        if blizzType ~= "BN_WHISPER" then
            self._ignoreNextBnetLiveUpdateOpenCount = (self._ignoreNextBnetLiveUpdateOpenCount or 0) + 1
            if self._ignoreNextBnetLiveUpdateOpenCount >= 2 then
                self._ignoreNextBnetLiveUpdateFor = nil
                self._ignoreNextBnetLiveUpdateOpenCount = 0
            end
        else
            self._ignoreNextBnetLiveUpdateOpenCount = 0
        end
    end

    self._attrCache[origEditBox] = {}

    -- Did Blizzard open with a specific target?  (BN_WHISPER excluded.)
    local blizzHasTarget = (blizzType == "WHISPER" and blizzTell and blizzTell ~= "")
        or (blizzType == "CHANNEL" and blizzChan and blizzChan ~= "")

    -- Priority for picking the channel on open:
    --   1. Blizzard explicitly provided a whisper/channel target (reply key,
    --      name-click, Contacts list, etc.) — always honour it.
    --   2. Lockdown draft — restore the channel the user was on mid-combat.
    --   3. LastUsed sticky — remember the last channel the user chose.
    --   4. Blizzard's editbox type (no specific target) or SAY as fallback.
    if blizzHasTarget and not self._lastSavedDraftIsLockdown then
        self.ChatType = blizzType
        self.Language = blizzLang or nil
        self.Target   = blizzTell or blizzChan or nil
    elseif (self.LastUsed and self.LastUsed.chatType) and not self._lastSavedDraftIsLockdown then
        self.ChatType = self.LastUsed.chatType
        self.Language = self.LastUsed.language or blizzLang or nil
        self.Target   = self.LastUsed.target or blizzTell or blizzChan or nil
    else
        self.ChatType = (self.LastUsed and self.LastUsed.chatType)
            or blizzType
            or "SAY"
        self.Language = (self.LastUsed and self.LastUsed.language)
            or blizzLang
            or nil
        self.Target   = (self.LastUsed and self.LastUsed.target)
            or blizzTell or blizzChan
            or nil
    end

    -- Validate channel (might have been removed since last session).
    if self.ChatType == "CHANNEL" and self.Target then
        local num = tonumber(self.Target)
        if num then
            local resolved = ResolveChannelName(num)
            if resolved then
                self.ChannelName = resolved
            else
                -- Channel gone — fall back to SAY.
                self.ChatType    = "SAY"
                self.Target      = nil
                self.ChannelName = nil
            end
        end
    end

    -- Position & size
    -- Anchor directly on top of the original editbox so it looks identical.
    local overlay = self.Overlay
    local cfg = YapperTable.Config.EditBox or {}
    overlay:SetParent(UIParent)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", origEditBox, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", origEditBox, "BOTTOMRIGHT", 0, 0)

    -- Match scale for addons that resize chat frames.
    local scale = origEditBox:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:SetScale(scale)

    -- Font
    -- Config overrides Blizzard's font; otherwise inherit.
    local cfgFace  = cfg.FontFace
    local cfgSize  = cfg.FontSize or 0
    local cfgFlags = cfg.FontFlags or ""

    if cfgFace or cfgSize > 0 then
        -- Blend config values with Blizzard defaults.
        local baseFace, baseSize, baseFlags = origEditBox:GetFont()
        local face                          = cfgFace or baseFace
        local size                          = cfgSize > 0 and cfgSize or baseSize
        local flags                         = (cfgFlags ~= "") and cfgFlags or baseFlags
        self.OverlayEdit:SetFont(face, size, flags)
        self.ChannelLabel:SetFont(face, size, flags)
    else
        local fontObj = origEditBox:GetFontObject()
        if fontObj then
            self.OverlayEdit:SetFontObject(fontObj)
            self.ChannelLabel:SetFontObject(fontObj)
        end
    end

    -- Label width: dynamically size to fit the label text but cap at
    -- ~28% of the editbox.  Leave a minimum typing area of 80px.
    local ebWidth = origEditBox:GetWidth() or 350
    local labelText = BuildLabelText(self.ChatType, self.Target, self.ChannelName)
    UpdateLabelBackgroundForText(self, labelText)

    -- If you're looking for text colour here, it's set by RefreshLabel() to match the active channel.
    -- CTFL+F, friend.

    -- Vertical scaling
    -- The overlay must be tall enough for the chosen font.  If the font
    -- size (+ padding) exceeds the Blizzard editbox height, grow.
    -- A configured MinHeight also serves as a floor.
    local _, activeSize = self.OverlayEdit:GetFont()
    activeSize          = activeSize or 14
    local fontPad       = cfg.FontPad or 8
    local fontNeeded    = activeSize + fontPad
    local blizzH        = origEditBox:GetHeight() or 32
    local minH          = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
    local finalH        = math.max(minH, fontNeeded)
    if finalH > blizzH then
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", origEditBox, "TOPLEFT", 0, 0)
        overlay:SetPoint("RIGHT", origEditBox, "RIGHT", 0, 0)
        overlay:SetHeight(finalH)
    end

    -- Re-apply background colours from config.
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}
    SetFrameFillColor(overlay, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    SetFrameFillColor(self.LabelBg, labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0)

    -- Stay on top of the original.
    local origLevel = origEditBox:GetFrameLevel() or 0
    overlay:SetFrameLevel(origLevel + 5)

    -- ── Final setup ──────────────────────────────────────────────────
    self._closedClean = false

    -- Draft recovery: restore if the last close was dirty.
    -- Skip if Blizzard set a target (e.g. Friends-list whisper).
    local draftText
    if not blizzHasTarget and YapperTable.History then
        local text, draftType, draftTarget = YapperTable.History:GetDraft()
        if text then
            draftText = text
            if draftType then self.ChatType = draftType end
            if draftTarget then self.Target = draftTarget end
            YapperTable.History:MarkDirty(false)
            YapperTable.Utils:VerbosePrint("Draft recovered: " .. #text .. " chars.")
        end
    end

    -- Carry over any text Blizzard pre-populated (chat links, etc.).
    if not draftText and blizzText and blizzText ~= "" then
        draftText = blizzText
    end

    self.OverlayEdit:SetText(draftText or "")
    if draftText then
        self.OverlayEdit:SetCursorPosition(#draftText)
    end
    self:RefreshLabel()
    overlay:Show()
    self.OverlayEdit:SetFocus()
    if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
        YapperTable.TypingTrackerBridge:OnOverlayFocusGained(self.ChatType)
    end
end

function EditBox:Hide()
    local prevOrig = self.OrigEditBox

    if self.Overlay then
        self.Overlay:Hide()
    end
    self.OverlayEdit:ClearFocus()
    self.OrigEditBox = nil

    -- Suppress one immediate Blizzard Show for the same editbox to avoid
    -- hide/show contention on outside-click dismissals.
    if prevOrig then
        self._suppressNextShowFor = prevOrig
        C_Timer.After(0, function()
            if self._suppressNextShowFor == prevOrig then
                self._suppressNextShowFor = nil
            end
        end)
    end
end

--- Save draft, close overlay, and notify during lockdown.
function EditBox:HandoffToBlizzard()
    if not self.Overlay or not self.Overlay:IsShown() then return end

    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""

    -- Save as dirty draft for recovery on next open.
    if text ~= "" and YapperTable.History then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
        -- Mark that this draft was saved due to lockdown so callers
        -- can decide whether to restore it to Blizzard's editbox.
        self._lastSavedDraftIsLockdown = true
    end

    -- OnHide won't double-save because _closedClean is true.
    self._closedClean = true

    -- Close overlay and mark the draft as handed off to Blizzard's flow.
    if self.OverlayEdit then
        self.OverlayEdit:SetText("")
    end
    self:Hide()

    self._lockdownHandedOff = true
    YapperTable.Utils:Print("info",
        "Chat in lockdown — your message has been saved. Press Enter after lockdown ends to continue.")

    -- Cancel the polling ticker if one is running.
    if self._lockdownTicker then
        self._lockdownTicker:Cancel()
        self._lockdownTicker = nil
    end
end

--- Re-apply current config values to a live overlay (if present/shown).
function EditBox:ApplyConfigToLiveOverlay()
    if not self.Overlay or not self.OverlayEdit then return end

    local localConf = _G.YapperLocalConf
    if type(localConf) ~= "table"
        or type(localConf.System) ~= "table"
        or localConf.System.SettingsHaveChanged ~= true then
        return
    end

    local cfg = YapperTable.Config.EditBox or {}
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}

    SetFrameFillColor(self.Overlay, inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    SetFrameFillColor(self.LabelBg, labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0)

    local cfgFace  = cfg.FontFace
    local cfgSize  = cfg.FontSize or 0
    local cfgFlags = cfg.FontFlags or ""

    if cfgFace or cfgSize > 0 then
        local baseFace, baseSize, baseFlags
        if self.OrigEditBox and self.OrigEditBox.GetFont then
            baseFace, baseSize, baseFlags = self.OrigEditBox:GetFont()
        end

        local _, currentSize = self.OverlayEdit:GetFont()
        local face           = cfgFace or baseFace
        local size           = cfgSize > 0 and cfgSize or baseSize or currentSize or 14
        local flags          = (cfgFlags ~= "") and cfgFlags or baseFlags or ""
        if face then
            self.OverlayEdit:SetFont(face, size, flags)
            if self.ChannelLabel then
                self.ChannelLabel:SetFont(face, size, flags)
            end
        end
    elseif self.OrigEditBox and self.OrigEditBox.GetFontObject then
        local fontObj = self.OrigEditBox:GetFontObject()
        if fontObj then
            self.OverlayEdit:SetFontObject(fontObj)
            if self.ChannelLabel then
                self.ChannelLabel:SetFontObject(fontObj)
            end
        end
    end

    if self.Overlay and self.Overlay:IsShown() and self.OrigEditBox then
        local _, activeSize = self.OverlayEdit:GetFont()
        activeSize          = activeSize or 14
        local fontPad       = cfg.FontPad or 8
        local fontNeeded    = activeSize + fontPad
        local blizzH        = self.OrigEditBox:GetHeight() or 32
        local minH          = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
        local finalH        = math.max(minH, fontNeeded)

        self.Overlay:ClearAllPoints()
        self.Overlay:SetPoint("TOPLEFT", self.OrigEditBox, "TOPLEFT", 0, 0)
        self.Overlay:SetPoint("RIGHT", self.OrigEditBox, "RIGHT", 0, 0)
        self.Overlay:SetHeight(finalH > blizzH and finalH or blizzH)
    end

    self:RefreshLabel()
    localConf.System.SettingsHaveChanged = false
end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

function EditBox:RefreshLabel()
    local label, r, g, b = BuildLabelText(self.ChatType, self.Target, self.ChannelName)
    local cfg = YapperTable.Config.EditBox or {}
    local resolvedR, resolvedG, resolvedB = r, g, b

    local currentKey = CHATTYPE_TO_OVERRIDE_KEY[self.ChatType]
    local masterKey = cfg.ChannelColorMaster
    local overrides = cfg.ChannelColorOverrides
    local channelColors = cfg.ChannelTextColors

    if currentKey and type(channelColors) == "table"
        and type(channelColors[currentKey]) == "table" then
        local own = channelColors[currentKey]
        if type(own.r) == "number" and type(own.g) == "number" and type(own.b) == "number" then
            resolvedR, resolvedG, resolvedB = own.r, own.g, own.b
        end
    end

    if currentKey and type(masterKey) == "string" and type(overrides) == "table"
        and masterKey ~= "" and currentKey ~= masterKey and overrides[currentKey] == true then
        if type(channelColors) == "table"
            and type(channelColors[masterKey]) == "table"
            and type(channelColors[masterKey].r) == "number"
            and type(channelColors[masterKey].g) == "number"
            and type(channelColors[masterKey].b) == "number" then
            resolvedR = channelColors[masterKey].r
            resolvedG = channelColors[masterKey].g
            resolvedB = channelColors[masterKey].b
        elseif ChatTypeInfo and ChatTypeInfo[masterKey] then
            local info = ChatTypeInfo[masterKey]
            resolvedR = info.r or resolvedR
            resolvedG = info.g or resolvedG
            resolvedB = info.b or resolvedB
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
    self.ChannelLabel:SetTextColor(resolvedR, resolvedG, resolvedB)

    -- Labels stay channel-coloured. Input text uses channel colour, or master override.
    if self.OverlayEdit then
        self.OverlayEdit:SetTextColor(resolvedR, resolvedG, resolvedB)
    end
end

--- Save selection for stickiness across show/hide.
function EditBox:PersistLastUsed()
    -- Don't make YELL sticky — but don't clear LastUsed either,
    -- so we restore to whatever was sticky before YELL.
    if self.ChatType == "YELL" then
        return
    end

    local cfg = YapperTable.Config.EditBox or {}
    if cfg.StickyChannel == false then
        -- Group channels stay sticky unless StickyGroupChannel is also off.
        if not GROUP_CHAT_TYPES[self.ChatType]
            or cfg.StickyGroupChannel == false then
            -- Stickiness is off for this channel type.
            -- Actively reset to SAY so the next open doesn't inherit a
            -- stale channel (e.g. if the user disabled sticky mid-session
            -- or the Show-hook seeded LastUsed from Blizzard's editbox).
            self.LastUsed.chatType = "SAY"
            self.LastUsed.target   = nil
            self.LastUsed.language = nil
            return
        end
    end

    self.LastUsed.chatType = self.ChatType
    self.LastUsed.target   = self.Target
    self.LastUsed.language = self.Language
end

-- ---------------------------------------------------------------------------
-- Tab cycling
-- ---------------------------------------------------------------------------

function EditBox:CycleChat(direction)
    local current = self.ChatType or "SAY"
    local idx = 1
    for i, ct in ipairs(TAB_CYCLE) do
        if ct == current then
            idx = i
            break
        end
    end

    -- Skip unavailable modes.
    for _ = 1, #TAB_CYCLE do
        idx = idx + direction
        if idx < 1 then idx = #TAB_CYCLE end
        if idx > #TAB_CYCLE then idx = 1 end

        local candidate = TAB_CYCLE[idx]
        if self:IsChatTypeAvailable(candidate) then
            self.ChatType    = candidate
            self.Target      = nil
            self.ChannelName = nil
            self:RefreshLabel()
            if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.Enabled then
                YapperTable.TypingTrackerBridge:OnChannelChanged(self.ChatType)
            end
            return
        end
    end
end

function EditBox:IsChatTypeAvailable(chatType)
    if chatType == "SAY" or chatType == "EMOTE" or chatType == "YELL" then
        return true
    end
    if chatType == "PARTY" or chatType == "PARTY_LEADER" then
        return IsInGroup()
    end
    if chatType == "RAID" or chatType == "RAID_LEADER" or chatType == "RAID_WARNING" then
        return IsInRaid()
    end
    if chatType == "INSTANCE_CHAT" then
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    if chatType == "GUILD" or chatType == "OFFICER" then
        return IsInGuild()
    end
    return true
end

-- ---------------------------------------------------------------------------
-- History navigation
-- ---------------------------------------------------------------------------

function EditBox:NavigateHistory(direction)
    -- Build history snapshot on first press.
    if not self.HistoryCache then
        self.HistoryCache = {}
        if YapperTable.History and YapperTable.History.GetChatHistory then
            self.HistoryCache = YapperTable.History:GetChatHistory() or {}
        elseif _G.YapperLocalHistory and _G.YapperLocalHistory.chatHistory then
            local saved = _G.YapperLocalHistory.chatHistory
            if type(saved) == "table" then
                if saved.global then
                    for _, v in ipairs(saved.global) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                else
                    for _, v in ipairs(saved) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                end
            end
        end
        self.HistoryIndex = #self.HistoryCache + 1
    end

    local cache = self.HistoryCache
    if #cache == 0 then return end

    local newIdx = (self.HistoryIndex or (#cache + 1)) + direction
    newIdx = math.max(1, math.min(newIdx, #cache + 1))

    if newIdx == self.HistoryIndex then return end
    self.HistoryIndex = newIdx

    if newIdx > #cache then
        self.OverlayEdit:SetText("")
    else
        local item = cache[newIdx]
        local text = ""
        local chatType = nil
        local target = nil

        if type(item) == "table" then
            text = item.text or ""
            chatType = item.chatType
            target = item.target
        else
            text = item or ""
        end

        self.OverlayEdit:SetText(text)
        self.OverlayEdit:SetCursorPosition(#text)

        -- Context switching: restore channel if recorded.
        if chatType then
            self.ChatType = chatType
            self.Target = target

            if chatType == "CHANNEL" and target then
                local num = tonumber(target)
                if num then
                    self.ChannelName = ResolveChannelName(num)
                end
            else
                self.ChannelName = nil
            end
            self:RefreshLabel()
        end
        -- If no chatType (legacy or slash command), keep current channel.
    end
end

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

--- Forward an unrecognised slash command to Blizzard.
function EditBox:ForwardSlashCommand(text)
    if not self.OrigEditBox then return end

    -- If chat is locked down (combat/m+ lockdown), save draft and handoff
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        self:HandoffToBlizzard()
        return
    end

    self.OrigEditBox:SetText(text)
    ChatEdit_SendText(self.OrigEditBox)

    -- Clean up in case ChatEdit_SendText didn't close it.
    if self.OrigEditBox:IsShown() then
        self.OrigEditBox:SetText("")
        self.OrigEditBox:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Hook into Blizzard editboxes (taint-free)
-- ---------------------------------------------------------------------------

function EditBox:HookBlizzardEditBox(blizzEditBox)
    if self.HookedBoxes[blizzEditBox] then return end
    self.HookedBoxes[blizzEditBox] = true
    self._attrCache[blizzEditBox] = {}

    -- Capture chatType / tellTarget / channelTarget as they're set.
    -- BNet whisper: attributes arrive BEFORE Show.
    -- WoW whisper:  attributes arrive one frame AFTER Show (deferred).
    -- The live-update path below handles the deferred case.
    hooksecurefunc(blizzEditBox, "SetAttribute", function(eb, key, value)
        local c = self._attrCache[eb]
        if not c then
            c = {}
            self._attrCache[eb] = c
        end
        if key == "chatType" or key == "tellTarget"
            or key == "channelTarget" or key == "language" then
            c[key] = value
        end

        -- If chat is locked down and Blizzard's untainted editbox is
        -- being manipulated (user changed channel/target/language),
        -- mirror that choice into our sticky `LastUsed` unless we have
        -- a draft saved due to lockdown (the draft should take
        -- precedence).
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and C_ChatInfo.InChatMessagingLockdown() then
            local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
            if ct and ct ~= "BN_WHISPER" then
                local target = nil
                if ct == "WHISPER" then
                    target = c.tellTarget or (eb.GetAttribute and eb:GetAttribute("tellTarget"))
                elseif ct == "CHANNEL" then
                    target = c.channelTarget or (eb.GetAttribute and eb:GetAttribute("channelTarget"))
                end
                local lang = c.language or (eb.GetAttribute and eb:GetAttribute("language"))

                if not self._lastSavedDraftIsLockdown then
                    self.LastUsed.chatType = ct
                    self.LastUsed.target = target
                    self.LastUsed.language = lang
                    -- Persist after lockdown ends if we are still locked.
                    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
                        self._lastSavedDuringLockdown = true
                    else
                        self:PersistLastUsed()
                    end
                end
            end
        end

        -- ── BNet → non-BNet transition ───────────────────────────────
        -- If Blizzard's box was showing for a BNet whisper and the user
        -- typed a slash command that changed chatType, reclaim it.
        if key == "chatType" and value ~= "BN_WHISPER"
            and (not self.Overlay or not self.Overlay:IsShown())
            and eb:IsShown() then
            local prevType = c._prevChatType
            if prevType == "BN_WHISPER" then
                local savedEB = self._bnetEditBox or eb
                local newChatType = value
                -- Defer to next frame; overlay creation needs to be
                -- outside the SetAttribute hook context.
                C_Timer.After(0, function()
                    -- If the editbox was dismissed (Escape) rather than
                    -- channel-switched, it will be hidden by now — bail out.
                    if not savedEB or not savedEB:IsShown() then
                        self._bnetEditBox = nil
                        return
                    end

                    -- If WIM grabbed whisper focus in the meantime, do not
                    -- reclaim this box for Yapper's overlay.
                    if IsWIMFocusActive() then
                        self._bnetEditBox = nil
                        return
                    end

                    -- Read leftover text after ParseText stripped the slash prefix.
                    local leftover = savedEB and savedEB.GetText and savedEB:GetText() or ""
                    leftover = leftover:match("^%s*(.-)%s*$") or ""

                    if savedEB and savedEB.Hide and savedEB:IsShown() then
                        savedEB:Hide()
                    end
                    self._nextShowFromBnetTransition = true
                    self:Show(savedEB)

                    -- Force the correct chat type (cache may hold stale BNet attrs).
                    self.ChatType = newChatType
                    self.Target   = nil
                    if newChatType == "WHISPER" and savedEB.GetAttribute then
                        self.Target = savedEB:GetAttribute("tellTarget")
                    elseif newChatType == "CHANNEL" and savedEB.GetAttribute then
                        local ch         = savedEB:GetAttribute("channelTarget")
                        self.Target      = ch
                        self.ChannelName = ResolveChannelName(tonumber(ch))
                    end
                    self:RefreshLabel()

                    -- Carry over message text if any.
                    if leftover ~= "" and self.OverlayEdit then
                        self.OverlayEdit:SetText(leftover)
                        self.OverlayEdit:SetCursorPosition(#leftover)
                    end
                    self._bnetEditBox = nil
                end)
            end
        end
        if key == "chatType" then
            c._prevChatType = value
        end

        -- ── Live update: attributes arrived after we already showed ────
        if self.OrigEditBox == eb and self.Overlay and self.Overlay:IsShown() then
            local ct = c.chatType
            local tt = c.tellTarget
            local ch = c.channelTarget

            -- BNet arrived late — hand back to Blizzard.
            if ct == "BN_WHISPER" then
                if self._ignoreNextBnetLiveUpdateFor == eb then
                    self._ignoreNextBnetLiveUpdateFor = nil
                    self._ignoreNextBnetLiveUpdateOpenCount = 0
                    return
                end
                if self._preferStickyAfterBnet
                    and self.ChatType
                    and self.ChatType ~= "BN_WHISPER" then
                    self._preferStickyAfterBnet = false
                    return
                end
                self:Hide()
                if eb and eb.Show then
                    eb:Show()
                end
                return
            end

            if ct == "WHISPER" and tt and tt ~= "" then
                self.ChatType = ct
                self.Target   = tt
                self:RefreshLabel()
                -- Clear stale draft (user can't have typed in one frame).
                if self.OverlayEdit then
                    self.OverlayEdit:SetText("")
                end
            elseif ct == "CHANNEL" and ch and ch ~= "" then
                self.ChatType    = "CHANNEL"
                self.Target      = ch
                self.ChannelName = ResolveChannelName(tonumber(ch))
                self:RefreshLabel()
                if self.OverlayEdit then
                    self.OverlayEdit:SetText("")
                end
            end
        end
    end)

    hooksecurefunc(blizzEditBox, "Show", function(eb)
        if self._suppressNextShowFor == eb then
            self._suppressNextShowFor = nil
            return
        end

        -- Re-entrancy guard: hooksecurefunc fires even if already shown,
        -- and SetFocus causes a Show→ActivateChat→Show loop.
        if self.Overlay and self.Overlay:IsShown() then
            return
        end

        -- If the user Escaped out of a BNet whisper, don't re-open ours.
        if self._bnetDismissed then
            self._bnetDismissed = false
            return
        end

        -- In lockdown Blizzard's untainted box can still send; leave it alone.
        if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
            if not self._lockdownShowHandled then
                self._lockdownShowHandled = true
                local chosenCT = self.ChatType or (self.LastUsed and self.LastUsed.chatType) or "SAY"
                eb:SetAttribute("chatType", chosenCT)
                if chosenCT == "WHISPER" then
                    eb:SetAttribute("tellTarget", self.Target)
                    eb:SetAttribute("channelTarget", nil)
                elseif chosenCT == "CHANNEL" then
                    eb:SetAttribute("channelTarget", self.Target)
                    eb:SetAttribute("tellTarget", nil)
                else
                    eb:SetAttribute("tellTarget", nil)
                    eb:SetAttribute("channelTarget", nil)
                end
                if self.Language then
                    eb:SetAttribute("language", self.Language)
                else
                    eb:SetAttribute("language", nil)
                end
            end
            return
        end


        -- If WIM currently owns chat focus, do not present Yapper overlay.
        if IsWIMFocusActive() then
            return
        end

        -- BNet whispers — let Blizzard handle natively.  Save the
        -- editbox ref so SetAttribute can reclaim it on type-switch.
        local c = self._attrCache[eb] or {}
        local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
        if ct == "BN_WHISPER" then
            if self._preferStickyAfterBnet
                and self.LastUsed
                and self.LastUsed.chatType
                and self.LastUsed.chatType ~= "BN_WHISPER" then
                self._preferStickyAfterBnet = false
                self._ignoreNextBnetLiveUpdateFor = eb
                self._ignoreNextBnetLiveUpdateOpenCount = 0

                C_Timer.After(0, function()
                    if eb and eb.Hide and eb:IsShown() then
                        eb:Hide()
                    end
                end)

                -- Respect WIM ownership before forcing an overlay show.
                if not IsWIMFocusActive() then
                    self:Show(eb)
                end
                return
            end
            self._bnetEditBox = eb
            return
        end

        -- Seed LastUsed from Blizzard's editbox so the lockdown fallback
        -- opens on the correct channel. Only seeds when LastUsed is empty —
        -- once the user has made an explicit choice (send or Tab-cycle) we
        -- never overwrite it from here.
        local c = self._attrCache[eb] or {}
        local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
        if ct and ct ~= "BN_WHISPER" and not self.LastUsed.chatType then
            local lastTarget = nil
            if ct == "WHISPER" then
                lastTarget = c.tellTarget or (eb.GetAttribute and eb:GetAttribute("tellTarget"))
            elseif ct == "CHANNEL" then
                lastTarget = c.channelTarget or (eb.GetAttribute and eb:GetAttribute("channelTarget"))
            end
            local lastLang         = c.language or (eb.GetAttribute and eb:GetAttribute("language"))
            self.LastUsed.chatType = ct
            self.LastUsed.target   = lastTarget
            self.LastUsed.language = lastLang
        end

        -- PreShowCheck: lets Queue suppress the overlay to grab the event.
        if self.PreShowCheck and self.PreShowCheck(eb) then
            C_Timer.After(0, function()
                if eb and eb.Hide and eb:IsShown() then
                    eb:Hide()
                end
            end)
            return
        end

        -- Hide Blizzard's box next frame (can't interfere mid-Show).
        C_Timer.After(0, function()
            if eb and eb.Hide and eb:IsShown() then
                eb:Hide()
            end
        end)

        -- Present our overlay.
        self:Show(eb)
    end)

    -- Track when the user Escapes out of a BNet whisper so we don't
    -- immediately re-open Yapper when Blizzard re-shows the editbox.
    hooksecurefunc(blizzEditBox, "Hide", function(eb)
        if self._bnetEditBox == eb then
            self._bnetEditBox   = nil
            self._bnetDismissed = true
            -- Clear on next frame so only the immediately-following Show
            -- is suppressed, not future ones.
            C_Timer.After(0, function()
                self._bnetDismissed = false
            end)
        end
    end)
end

--- Hook all NUM_CHAT_WINDOWS editboxes.  Call once on init.
function EditBox:HookAllChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            self:HookBlizzardEditBox(eb)
        end
    end

    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("EditBox overlays hooked for " .. (NUM_CHAT_WINDOWS or 10) .. " chat frames.")
    end

    -- Shift-click link insertion (items, quests, spells, etc.).
    -- By overriding the "Active Window" detection, Blizzard's native logic
    -- correctly identifies the Yapper overlay as the destination for links.
    if not self._insertLinkHooked then
        self._insertLinkHooked = true

        if _G.ChatEdit_GetActiveWindow then
            local origActive = _G.ChatEdit_GetActiveWindow
            _G["ChatEdit_GetActiveWindow"] = function(...)
                if self.Overlay and self.Overlay:IsShown() and self.OverlayEdit and self.OverlayEdit:HasFocus() then
                    return self.OverlayEdit
                end
                return origActive(...)
            end
        end

        if _G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow then
            local origUtilActive = _G.ChatFrameUtil.GetActiveWindow
            _G.ChatFrameUtil["GetActiveWindow"] = function(...)
                if self.Overlay and self.Overlay:IsShown() and self.OverlayEdit and self.OverlayEdit:HasFocus() then
                    return self.OverlayEdit
                end
                return origUtilActive(...)
            end
        end
    end

    -- ── Chat Reply hotkey ────────────────────────────────────────────────
    -- The WoW Chat Reply keybinding is a secure C++ binding — there is no
    -- hookable Lua function for it.  It works by setting chatType/tellTarget
    -- attributes on the editbox and calling Show(), which our Show hook
    -- already intercepts.  The priority fix in EditBox:Show() (blizzHasTarget
    -- beats LastUsed) is what makes the reply key work correctly.
end

-- ---------------------------------------------------------------------------
-- Public callbacks
-- ---------------------------------------------------------------------------

--- Called when the user sends a non-slash message (Enter).
--- Signature: fn(text, chatType, language, target)
function EditBox:SetOnSend(fn)
    self.OnSend = fn
end

--- If fn(blizzEditBox) returns true, the overlay is suppressed.
--- Used by Queue to consume hardware events for send continuation.
function EditBox:SetPreShowCheck(fn)
    self.PreShowCheck = fn
end
