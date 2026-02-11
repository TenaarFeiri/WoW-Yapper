--[[
    EditBox.lua — Yapper 1.0.0
    Taint-free overlay that replaces Blizzard's chat input.

    Since WoW 12.0.0 any addon touching the default EditBox taints it,
    which blocks SendChatMessage during encounters.  We sidestep this by
    hooking Show() (taint-safe), hiding Blizzard's box, and presenting
    our own overlay in the same spot.  The overlay was never part of the
    protected hierarchy so it can send freely even in combat.
]]

local YapperName, YapperTable = ...

local EditBox = {}
YapperTable.EditBox = EditBox

-- Overlay widgets (created lazily).
EditBox.Overlay       = nil
EditBox.OverlayEdit   = nil
EditBox.ChannelLabel  = nil
EditBox.LabelBg       = nil

-- State.
EditBox.HookedBoxes   = {}
EditBox.OrigEditBox   = nil
EditBox.ChatType      = nil
EditBox.Language      = nil
EditBox.Target        = nil
EditBox.ChannelName   = nil
EditBox.LastUsed      = {}
EditBox.HistoryIndex  = nil
EditBox.HistoryCache  = nil
EditBox.PreShowCheck  = nil
EditBox._attrCache    = {}
EditBox._lockdownTicker    = nil
EditBox._lockdownHandedOff = false

-- Slash command → chatType.
local SLASH_MAP = {
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
local TAB_CYCLE = {
    "SAY", "EMOTE", "YELL", "PARTY", "INSTANCE_CHAT",
    "RAID", "RAID_WARNING", "GUILD", "OFFICER",
}

-- Pretty names for the channel label.
local LABEL_PREFIXES = {
    SAY            = "Say",
    EMOTE          = "Emote",
    YELL           = "Yell",
    PARTY          = "Party",
    PARTY_LEADER   = "Party Leader",
    RAID           = "Raid",
    RAID_LEADER    = "Raid Leader",
    RAID_WARNING   = "Raid Warning",
    INSTANCE_CHAT  = "Instance",
    GUILD          = "Guild",
    OFFICER        = "Officer",
    WHISPER        = "Whisper",
    CHANNEL        = "Channel",
}

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

    -- Truncate long labels.
    if #label > 25 then
        label = label:sub(1, 22) .. "..."
    end

    -- Colour from ChatTypeInfo.
    local r, g, b = 1, 0.82, 0  -- gold fallback
    if chatType and ChatTypeInfo and ChatTypeInfo[chatType] then
        local info = ChatTypeInfo[chatType]
        r, g, b = info.r or r, info.g or g, info.b or b
    end

    return label, r, g, b
end

-- ---------------------------------------------------------------------------
-- Overlay creation (one-time)
-- ---------------------------------------------------------------------------

function EditBox:CreateOverlay()
    if self.Overlay then return end

    local cfg = YapperTable.Config.EditBox or {}
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}

    -- Container frame — matches position/size of the original editbox.
    local frame = CreateFrame("Frame", "YapperOverlayFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Container backdrop (visible background for the input area).
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    frame:SetBackdropBorderColor(inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)

    -- ── Label background (left portion) ──────────────────────────────
    local labelBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    labelBg:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    labelBg:SetBackdropColor(labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 0.9)
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
end

-- ---------------------------------------------------------------------------
-- Script handlers
-- ---------------------------------------------------------------------------

function EditBox:SetupOverlayScripts()
    local edit  = self.OverlayEdit
    local frame = self.Overlay

    -- When true, we're changing text programmatically (skip OnTextChanged).
    local updatingText = false

    -- ── OnTextChanged: slash-command channel switches ──────────────────
    edit:SetScript("OnTextChanged", function(box, isUserInput)
        if updatingText then return end
        if not isUserInput then return end

        local text = box:GetText() or ""
        if text:sub(1, 1) ~= "/" then
            self.HistoryIndex = nil
            self.HistoryCache = nil
            return
        end

        -- Bare numeric channel: "/2 message"
        local num, rest = text:match("^/(%d+)%s+(.*)")
        if num then
            local resolved = ResolveChannelName(tonumber(num))
            if resolved then
                self.ChatType    = "CHANNEL"
                self.Target      = num
                self.ChannelName = resolved
                self.Language    = nil
                updatingText = true
                box:SetText(rest or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest or ""))
            end
            return
        end

        -- "/cmd rest" — need a space before we act.
        local cmd, rest2 = text:match("^/([%w_]+)%s+(.*)")
        if not cmd then return end
        cmd = cmd:lower()

        -- /c, /channel — wait for a space after the channel ID too,
        -- so we don't fire while the user is still typing it.
        if cmd == "c" or cmd == "channel" then
            local ch, remainder = (rest2 or ""):match("^(%S+)%s+(.*)")
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

        -- /w, /whisper, /tell, /t — wait for a space after the target name.
        if cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t" then
            local target, remainder = (rest2 or ""):match("^(%S+)%s+(.*)")
            if target then
                self.ChatType = "WHISPER"
                self.Target   = target
                self.Language = nil
                updatingText = true
                box:SetText(remainder or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(remainder or ""))
            end
            return
        end

        -- /r, /reply
        if cmd == "r" or cmd == "reply" then
            local lastTell
            if ChatEdit_GetLastTellTarget then
                lastTell = ChatEdit_GetLastTellTarget()
            end
            if lastTell and lastTell ~= "" then
                self.ChatType = "WHISPER"
                self.Target   = lastTell
                self.Language = nil
                updatingText = true
                box:SetText(rest2 or "")
                updatingText = false
                self:RefreshLabel()
                box:SetCursorPosition(#(rest2 or ""))
            end
            return
        end

        -- Standard chat-type switch (/s, /e, /p, etc.).
        if SLASH_MAP[cmd] then
            self.ChatType = SLASH_MAP[cmd]
            self.Target   = nil
            self.Language = nil
            updatingText = true
            box:SetText(rest2 or "")
            updatingText = false
            self:RefreshLabel()
            box:SetCursorPosition(#(rest2 or ""))
            return
        end

        -- Unknown — leave as-is; forwarded to Blizzard on Enter.
    end)

    -- ── OnEnterPressed: send or forward ──────────────────────────────
    edit:SetScript("OnEnterPressed", function(box)
        local text = box:GetText() or ""
        local trimmed = text:match("^%s*(.-)%s*$") or ""

        -- Empty input — remember channel and close (clean).
        if trimmed == "" then
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft()
            end
            self:PersistLastUsed()
            self:Hide()
            return
        end

        -- Slash commands: some (/w Name, /r) won't have been consumed by
        -- OnTextChanged because it waits for a trailing space.  Handle
        -- those here before forwarding anything unrecognised to Blizzard.
        if trimmed:sub(1, 1) == "/" then
            local enterCmd, enterRest = trimmed:match("^/([%w_]+)%s*(.*)")
            if enterCmd then
                enterCmd = enterCmd:lower()

                -- /w, /t, /whisper, /tell — switch to whisper.
                if enterCmd == "w" or enterCmd == "whisper"
                   or enterCmd == "tell" or enterCmd == "t" then
                    local target = (enterRest or ""):match("^(%S+)")
                    if target then
                        self.ChatType = "WHISPER"
                        self.Target   = target
                        self.Language = nil
                        updatingText = true
                        box:SetText("")
                        updatingText = false
                        self:RefreshLabel()
                        -- Don't close — user now has an empty whisper box.
                        return
                    end
                end

                -- /r, /reply — switch to whisper-reply.
                if enterCmd == "r" or enterCmd == "reply" then
                    local lastTell
                    if ChatEdit_GetLastTellTarget then
                        lastTell = ChatEdit_GetLastTellTarget()
                    end
                    if lastTell and lastTell ~= "" then
                        self.ChatType = "WHISPER"
                        self.Target   = lastTell
                        self.Language = nil
                        updatingText = true
                        box:SetText(enterRest or "")
                        updatingText = false
                        self:RefreshLabel()
                        box:SetCursorPosition(#(enterRest or ""))
                        return
                    end
                end

                -- /c, /channel — switch to a channel.
                if enterCmd == "c" or enterCmd == "channel" then
                    local ch = (enterRest or ""):match("^(%S+)")
                    if ch then
                        local chNum = tonumber(ch)
                        if chNum then
                            local resolved = ResolveChannelName(chNum)
                            if resolved then
                                self.ChatType    = "CHANNEL"
                                self.Target      = tostring(chNum)
                                self.ChannelName = resolved
                                self.Language    = nil
                                updatingText = true
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
                            updatingText = true
                            box:SetText("")
                            updatingText = false
                            self:RefreshLabel()
                            return
                        end
                    end
                end

                -- Other known slash commands (e.g. "/e" alone — switch mode).
                if SLASH_MAP[enterCmd] then
                    self.ChatType = SLASH_MAP[enterCmd]
                    self.Target   = nil
                    self.Language = nil
                    updatingText = true
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

            -- Unrecognised — forward to Blizzard.
            if trimmed:sub(1, 1) == "/" then
                self._closedClean = true
                if YapperTable.History then
                    YapperTable.History:ClearDraft()
                end
                self:ForwardSlashCommand(trimmed)
                self:Hide()
                return
            end
        end

        -- Normal message — fire OnSend callback or send directly.
        if self.OnSend then
            self.OnSend(trimmed, self.ChatType or "SAY", self.Language, self.Target)
        else
            local sendFn = YapperTable.SendChatMessageOverride or C_ChatInfo.SendChatMessage
            if sendFn then
                sendFn(trimmed, self.ChatType or "SAY", self.Language, self.Target)
            end
        end

        -- Add to Blizzard's history so Up/Down works across reloads.
        if self.OrigEditBox then
            self.OrigEditBox:AddHistoryLine(text)
        end

        -- Clean close — message handed off successfully.
        self._closedClean = true
        if YapperTable.History then
            YapperTable.History:ClearDraft()
        end
        self:PersistLastUsed()
        self:Hide()
    end)

    -- ── OnEscapePressed: close overlay ───────────────────────────────
    edit:SetScript("OnEscapePressed", function(box)
        local text = box:GetText() or ""
        if text == "" then
            -- Nothing to lose — clean close.
            self._closedClean = true
            if YapperTable.History then
                YapperTable.History:ClearDraft()
            end
        else
            -- User bailed with text in the box — dirty close.
            -- Draft is saved in OnHide below.
            self._closedClean = false
        end
        box:SetText("")
        self:Hide()
    end)

    -- ── OnKeyDown: Tab cycling + history ───────────────────────────
    edit:HookScript("OnKeyDown", function(box, key)
        if key == "TAB" then
            self:CycleChat(IsShiftKeyDown() and -1 or 1)
        elseif key == "UP" then
            self:NavigateHistory(-1)
        elseif key == "DOWN" then
            self:NavigateHistory(1)
        end
    end)

    -- ── OnHide: save draft if dirty ───────────────────────────────
    frame:SetScript("OnHide", function()
        self.HistoryIndex = nil
        self.HistoryCache = nil

        -- Draft tracking: dirty close → save text.
        if not self._closedClean and YapperTable.History then
            local eb = self.OverlayEdit
            if eb then
                local text = eb:GetText() or ""
                if text ~= "" then
                    YapperTable.History:SaveDraft(eb)
                end
                YapperTable.History:MarkDirty(true)
            end
        end
        -- Reset for next open.
        self._closedClean = false
    end)

    -- ── Combat lockdown detection ────────────────────────────────────
    -- When InChatMessagingLockdown becomes true mid-typing, hand the
    -- overlay state back to Blizzard's secure editbox.
    -- Lockdown may activate slightly AFTER PLAYER_REGEN_DISABLED, so
    -- we poll briefly via a ticker if the first check is negative.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

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
                if ticks >= 20 then  -- 2 seconds
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
                        print("|cFFFFAA00Yapper:|r Lockdown ended — press Enter to resume typing.")
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
    self:CreateOverlay()

    self.OrigEditBox = origEditBox

    -- ── Determine chat mode and target ───────────────────────────────
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

    local cache     = self._attrCache[origEditBox] or {}
    local blizzType = cache.chatType    or (origEditBox and origEditBox:GetAttribute("chatType"))
    local blizzTell = cache.tellTarget  or (origEditBox and origEditBox:GetAttribute("tellTarget"))
    local blizzChan = cache.channelTarget or (origEditBox and origEditBox:GetAttribute("channelTarget"))
    local blizzLang = cache.language    or (origEditBox and origEditBox:GetAttribute("language"))
    local blizzText = origEditBox and origEditBox.GetText and origEditBox:GetText()

    self._attrCache[origEditBox] = {}

    -- Did Blizzard open with a specific target?  (BN_WHISPER excluded.)
    local blizzHasTarget = (blizzType == "WHISPER" and blizzTell and blizzTell ~= "")
                        or (blizzType == "CHANNEL" and blizzChan and blizzChan ~= "")

    if blizzHasTarget then
        self.ChatType = blizzType
        self.Language = blizzLang or nil
        self.Target   = blizzTell or blizzChan or nil
    else
        -- Fall back to sticky → Blizzard → SAY.
        self.ChatType = (self.LastUsed.chatType)
                     or blizzType
                     or "SAY"
        self.Language = (self.LastUsed.language)
                     or blizzLang
                     or nil
        self.Target   = (self.LastUsed.target)
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

    -- ── Position & size ──────────────────────────────────────────────
    -- Anchor directly on top of the original editbox so it looks identical.
    local overlay = self.Overlay
    local cfg = YapperTable.Config.EditBox or {}
    overlay:SetParent(UIParent)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT",  origEditBox, "TOPLEFT",  0, 0)
    overlay:SetPoint("BOTTOMRIGHT", origEditBox, "BOTTOMRIGHT", 0, 0)

    -- Match scale for addons that resize chat frames.
    local scale = origEditBox:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:SetScale(scale)

    -- Label width: ~28% of the editbox, clamped.
    local ebWidth = origEditBox:GetWidth() or 350
    local labelW  = math.max(80, math.min(math.floor(ebWidth * 0.28), ebWidth - 80))
    self.LabelBg:SetWidth(labelW)

    -- ── Font ─────────────────────────────────────────────────────────
    -- Config overrides Blizzard's font; otherwise inherit.
    local cfgFace  = cfg.FontFace
    local cfgSize  = cfg.FontSize or 0
    local cfgFlags = cfg.FontFlags or ""

    if cfgFace or cfgSize > 0 then
        -- Blend config values with Blizzard defaults.
        local baseFace, baseSize, baseFlags = origEditBox:GetFont()
        local face  = cfgFace or baseFace
        local size  = cfgSize > 0 and cfgSize or baseSize
        local flags = (cfgFlags ~= "") and cfgFlags or baseFlags
        self.OverlayEdit:SetFont(face, size, flags)
        self.ChannelLabel:SetFont(face, size, flags)
    else
        local fontObj = origEditBox:GetFontObject()
        if fontObj then
            self.OverlayEdit:SetFontObject(fontObj)
            self.ChannelLabel:SetFontObject(fontObj)
        end
    end

    -- Text colour is set by RefreshLabel() to match the active channel.

    -- ── Vertical scaling ────────────────────────────────────────────
    -- The overlay must be tall enough for the chosen font.  If the font
    -- size (+ padding) exceeds the Blizzard editbox height, grow.
    -- A configured MinHeight also serves as a floor.
    local _, activeSize = self.OverlayEdit:GetFont()
    activeSize = activeSize or 14
    local fontPad    = cfg.FontPad or 8
    local fontNeeded = activeSize + fontPad
    local blizzH     = origEditBox:GetHeight() or 32
    local minH       = (cfg.MinHeight and cfg.MinHeight > 0) and cfg.MinHeight or blizzH
    local finalH     = math.max(minH, fontNeeded)
    if finalH > blizzH then
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", origEditBox, "TOPLEFT", 0, 0)
        overlay:SetPoint("RIGHT",   origEditBox, "RIGHT",   0, 0)
        overlay:SetHeight(finalH)
    end

    -- Re-apply backdrop from config.
    local inputBg = cfg.InputBg or {}
    local labelCfg = cfg.LabelBg or {}
    if overlay.SetBackdropColor then
        overlay:SetBackdropColor(inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    end
    if overlay.SetBackdropBorderColor then
        overlay:SetBackdropBorderColor(inputBg.r or 0.05, inputBg.g or 0.05, inputBg.b or 0.05, inputBg.a or 1.0)
    end
    self.LabelBg:SetBackdropColor(labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 1.0)

    -- Inherit backdrop structure from the parent for the label border.
    local parent = origEditBox:GetParent()
    if parent and parent.GetBackdrop and parent:GetBackdrop() then
        local bd = parent:GetBackdrop()
        self.LabelBg:SetBackdrop(bd)
        self.LabelBg:SetBackdropColor(labelCfg.r or 0.06, labelCfg.g or 0.06, labelCfg.b or 0.06, labelCfg.a or 0.9)
        if parent.GetBackdropBorderColor then
            self.LabelBg:SetBackdropBorderColor(parent:GetBackdropBorderColor())
        end
    end

    -- Stay on top of the original.
    local origLevel = origEditBox:GetFrameLevel() or 0
    overlay:SetFrameLevel(origLevel + 5)

    -- ── Final setup ──────────────────────────────────────────────────
    self._closedClean = false

    -- Draft recovery: restore if the last close was dirty.
    -- Skip if Blizzard set a target (e.g. Friends-list whisper) — stale.
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
end

function EditBox:Hide()
    if self.Overlay then
        self.Overlay:Hide()
    end
    self.OverlayEdit:ClearFocus()
    self.OrigEditBox = nil
end

--- Save draft, close overlay, and notify during lockdown.
function EditBox:HandoffToBlizzard()
    if not self.Overlay or not self.Overlay:IsShown() then return end

    local text = self.OverlayEdit and self.OverlayEdit:GetText() or ""

    -- Save as dirty draft for recovery on next open.
    if text ~= "" and YapperTable.History then
        YapperTable.History:SaveDraft(self.OverlayEdit)
        YapperTable.History:MarkDirty(true)
    end

    -- OnHide won't double-save because _closedClean is true.
    self._closedClean = true
    self.OverlayEdit:SetText("")
    self:Hide()

    self._lockdownHandedOff = true
    print("|cFFFFAA00Yapper:|r Chat in lockdown — your message has been saved. Press Enter after lockdown ends to continue.")

    -- Cancel the polling ticker if one is running.
    if self._lockdownTicker then
        self._lockdownTicker:Cancel()
        self._lockdownTicker = nil
    end
end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

function EditBox:RefreshLabel()
    local label, r, g, b = BuildLabelText(self.ChatType, self.Target, self.ChannelName)
    self.ChannelLabel:SetText(label)
    self.ChannelLabel:SetTextColor(r, g, b)
    -- Text colour matches the channel.
    if self.OverlayEdit then
        self.OverlayEdit:SetTextColor(r, g, b)
    end
end

--- Save selection for stickiness across show/hide.
function EditBox:PersistLastUsed()
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
        self.OverlayEdit:SetText(cache[newIdx] or "")
        self.OverlayEdit:SetCursorPosition(#(cache[newIdx] or ""))
    end
end

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

--- Forward an unrecognised slash command to Blizzard.
function EditBox:ForwardSlashCommand(text)
    if not self.OrigEditBox then return end

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

                    -- Read leftover text after ParseText stripped the slash prefix.
                    local leftover = savedEB and savedEB.GetText and savedEB:GetText() or ""
                    leftover = leftover:match("^%s*(.-)%s*$") or ""

                    if savedEB and savedEB.Hide and savedEB:IsShown() then
                        savedEB:Hide()
                    end
                    self:Show(savedEB)

                    -- Force the correct chat type (cache may hold stale BNet attrs).
                    self.ChatType = newChatType
                    self.Target   = nil
                    if newChatType == "WHISPER" and savedEB.GetAttribute then
                        self.Target = savedEB:GetAttribute("tellTarget")
                    elseif newChatType == "CHANNEL" and savedEB.GetAttribute then
                        local ch = savedEB:GetAttribute("channelTarget")
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
            return
        end

        -- BNet whispers — let Blizzard handle natively.  Save the
        -- editbox ref so SetAttribute can reclaim it on type-switch.
        local c = self._attrCache[eb] or {}
        local ct = c.chatType or (eb.GetAttribute and eb:GetAttribute("chatType"))
        if ct == "BN_WHISPER" then
            self._bnetEditBox = eb
            return
        end

        -- PreShowCheck: lets Queue suppress the overlay to grab the event.
        if self.PreShowCheck and self.PreShowCheck(eb) then
            C_Timer.After(0, function()
                if eb and eb.Hide and eb:IsShown() then eb:Hide() end
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
    -- Blizzard checks for a focused editbox in C before calling
    -- ChatEdit_InsertLink, so that hook never fires when our overlay
    -- is up (Blizzard's box is hidden).  Hook HandleModifiedItemClick
    -- instead — it's the Lua entry point for all shift-clicks.
    if not self._insertLinkHooked then
        self._insertLinkHooked = true
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if link and IsModifiedClick("CHATLINK")
               and self.Overlay and self.Overlay:IsShown()
               and self.OverlayEdit then
                -- WoW caps chat messages at 2 hyperlinks.
                local current = self.OverlayEdit:GetText() or ""
                local _, count = current:gsub("|H", "|H")
                if count >= 2 then
                    YapperTable.Utils:Print(
                        "|cFFFF4444Only 2 links allowed per message.|r")
                    return
                end
                self.OverlayEdit:Insert(link)
            end
        end)
    end
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
