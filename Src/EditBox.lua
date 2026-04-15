--[[
    Taint-free overlay that replaces Blizzard's chat input.

    Since WoW 12.0.0 any addon touching the default EditBox taints it,
    which blocks SendChatMessage during encounters.  We sidestep this by
    hooking Show() (taint-safe), hiding Blizzard's box, and presenting
    our own overlay in the same spot.  The overlay was never part of the
    protected hierarchy so it can send freely even in combat.
    We then defer back to Blizzard's own editbox under lockdown.
]]

local _, YapperTable      = ...

local EditBox             = {}
YapperTable.EditBox       = EditBox

-- User bypass flag
local UserBypassingYapper = false
local BypassEditBox       = nil



-- Overlay widgets (created lazily).
EditBox.Overlay            = nil
EditBox.OverlayEdit        = nil
EditBox.ChannelLabel       = nil
EditBox.LabelBg            = nil

-- State.
EditBox.HookedBoxes        = {}
EditBox.OrigEditBox        = nil
EditBox.ChatType           = nil
EditBox.Language           = nil
EditBox.Target             = nil
EditBox.ChannelName        = nil
EditBox.LastUsed           = {}
EditBox.HistoryIndex       = nil
EditBox.HistoryCache       = nil
EditBox.PreShowCheck       = nil
EditBox._attrCache         = {}
EditBox._lockdownTicker    = nil
EditBox._lockdownHandedOff = false
EditBox._lockdownIdleTimer = nil   -- Defers handoff until user stops typing
EditBox._overlayUnfocused  = false -- True when overlay is visible but unfocused
-- Reply queue for recent whisper targets (most-recent at index 1)
EditBox.ReplyQueue         = {}
local REPLY_QUEUE_MAX      = 20

-- Reply-queue helpers
-- Reply-queue helpers

function EditBox:AddReplyTarget(name, kind)
    if not name or name == "" then return end
    -- Is it a secret? Then don't add it.
    if YapperTable and YapperTable.Utils and type(YapperTable.Utils.IsSecret) == "function" then
        if YapperTable.Utils:IsSecret(name) then return end
    end
    kind = kind or "WHISPER"
    -- Normalize short kinds
    if kind == "BN" then kind = "BN_WHISPER" end

    -- Remove existing matching entry (same name & kind) to avoid duplicates
    for i = #self.ReplyQueue, 1, -1 do
        local e = self.ReplyQueue[i]
        if e and e.name == name and e.kind == kind then
            table.remove(self.ReplyQueue, i)
            break
        end
    end

    -- Insert at front
    table.insert(self.ReplyQueue, 1, { name = name, kind = kind })

    -- Trim tail
    while #self.ReplyQueue > REPLY_QUEUE_MAX do
        table.remove(self.ReplyQueue)
    end
end

-- Get next reply target given current name and direction.
-- Behaviour: if current equals queue front, advance by direction (wrap).
-- Otherwise select front. Returns name, kind or nil.
function EditBox:NextReplyTarget(currentName, direction)
    if not self.ReplyQueue or #self.ReplyQueue == 0 then return nil end
    direction = direction or 1
    local q = self.ReplyQueue
    if currentName and q[1] and q[1].name == currentName then
        -- advance from front
        local idx = 1 + (direction or 1)
        if idx < 1 then idx = #q end
        if idx > #q then idx = 1 end
        return q[idx].name, q[idx].kind
    end
    -- Default: pick most recent
    return q[1].name, q[1].kind
end

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
    SAY           = "Say:",
    EMOTE         = "Emote",
    YELL          = "Yell:",
    PARTY         = "Party:",
    PARTY_LEADER  = "Party Leader:",
    RAID          = "Raid:",
    RAID_LEADER   = "Raid Leader:",
    RAID_WARNING  = "Raid Warning:",
    INSTANCE_CHAT = "Instance:",
    GUILD         = "Guild:",
    OFFICER       = "Officer:",
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
    BN_WHISPER = "BN_WHISPER",
    INSTANCE_CHAT = "INSTANCE_CHAT",
    RAID = "RAID",
    RAID_LEADER = "RAID",
    RAID_WARNING = "RAID_WARNING",
    CHANNEL = "CHANNEL",
    CLUB = "CLUB",
}

local function IsWhisperSlashPrefill(text)
    if type(text) ~= "string" then return false end
    local trimmed = text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return false end
    local cmd = trimmed:match("^/([%w_]+)%s+")
    if not cmd then return false end
    cmd = strlower(cmd)
    return cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t"
        or cmd == "cw" or cmd == "send" or cmd == "charwhisper"
end

local function ParseWhisperSlash(text)
    if type(text) ~= "string" then return nil end
    local cmd, rest = text:match("^%s*/([%w_]+)%s+(.*)")
    if not cmd then return nil end
    cmd = strlower(cmd)
    if cmd ~= "w" and cmd ~= "whisper" and cmd ~= "tell" and cmd ~= "t"
        and cmd ~= "cw" and cmd ~= "send" and cmd ~= "charwhisper" then
        return nil
    end
    local target, remainder = (rest or ""):match("^(%S+)%s*(.*)")
    if not target or target == "" then return nil end
    return target, remainder or ""
end

local function GetLastTellTargetInfo()
    local lastTell = nil
    if ChatEdit_GetLastTellTarget then
        lastTell = ChatEdit_GetLastTellTarget()
    end
    if not lastTell or lastTell == "" then
        return nil, nil
    end

    local lastType = nil
    if ChatEdit_GetLastTellTargetType then
        lastType = ChatEdit_GetLastTellTargetType()
    end
    if lastType ~= "BN_WHISPER" then
        -- If the last tell is actually a BNet friend, switch to BN_WHISPER.
        if YapperTable and YapperTable.Router and YapperTable.Router.ResolveBnetTarget then
            local presenceID, bnetAccountID = YapperTable.Router:ResolveBnetTarget(lastTell)
            if bnetAccountID or presenceID then
                lastType = "BN_WHISPER"
                lastTell = bnetAccountID or presenceID
            else
                lastType = "WHISPER"
            end
        else
            lastType = "WHISPER"
        end
    end

    return lastType, lastTell
end
------------------------------------------------
--- Bypass Yapper and go straight to Blizzard's editbox.
------------------------------------------------
function EditBox:OpenBlizzardChat()
    UserBypassingYapper = true
    local eb = self.OrigEditBox or _G.ChatFrame1EditBox
    BypassEditBox = eb and eb.GetName and eb:GetName() or nil

    -- Ensure any overlay state is handed off and saved first.
    -- Pass true (silent) so users bypassing intentionally don't see the lockdown message.
    if self.Overlay and self.Overlay:IsShown() then
        self:HandoffToBlizzard(true)
    end

    -- Defer the actual opening to the next frame so our Show-hook
    -- observes `UserBypassingYapper` and lets Blizzard's editbox win.
    C_Timer.After(0, function()
        -- Prefer using Blizzard's ChatFrame_OpenChat so Blizzard/ChatFrameUtil
        -- callbacks (focus gained, etc.) run and other addons (e.g. Chattery)
        -- can observe the editbox properly.
        if ChatFrame_OpenChat then
            pcall(ChatFrame_OpenChat, "", eb)
            if eb and eb.SetFocus then eb:SetFocus() end
        else
            if eb and eb.Show then eb:Show() end
            if eb and eb.SetFocus then eb:SetFocus() end
        end
    end)
end

------------------------------------------------
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

local function SetFrameFillColour(frame, r, g, b, a, rounded)
    if not frame then return end
    if rounded then
        if frame._yapperSolidFill then frame._yapperSolidFill:Hide() end
        if not frame._yapperRoundedFill then
            local rf = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            rf:SetAllPoints(frame)
            rf:SetFrameLevel(frame:GetFrameLevel())
            rf:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            frame._yapperRoundedFill = rf
        end
        frame._yapperRoundedFill:Show()
        frame._yapperRoundedFill:SetBackdropColor(r or 0, g or 0, b or 0, a or 1)
        frame._yapperRoundedFill:SetBackdropBorderColor(r or 0, g or 0, b or 0, a or 1)
    else
        if frame._yapperRoundedFill then frame._yapperRoundedFill:Hide() end
        if not frame._yapperSolidFill then
            local tex = frame:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(frame)
            frame._yapperSolidFill = tex
        end
        frame._yapperSolidFill:Show()
        frame._yapperSolidFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end
end

--- Copy every texture from Blizzard’s editbox onto our overlay so it
--- wears the same skin; afterwards the original box can simply hide.

-- Export shared locals for sub-files to re-localise.
EditBox._UserBypassingYapper = function() return UserBypassingYapper end
EditBox._SetUserBypassingYapper = function(val) UserBypassingYapper = val end
EditBox._BypassEditBox = function() return BypassEditBox end
EditBox._SetBypassEditBox = function(val) BypassEditBox = val end
EditBox._SLASH_MAP              = SLASH_MAP
EditBox._TAB_CYCLE              = TAB_CYCLE
EditBox._LABEL_PREFIXES         = LABEL_PREFIXES
EditBox._GROUP_CHAT_TYPES       = GROUP_CHAT_TYPES
EditBox._CHATTYPE_TO_OVERRIDE_KEY = CHATTYPE_TO_OVERRIDE_KEY
EditBox._REPLY_QUEUE_MAX        = REPLY_QUEUE_MAX
EditBox.IsWhisperSlashPrefill   = IsWhisperSlashPrefill
EditBox.ParseWhisperSlash       = ParseWhisperSlash
EditBox.GetLastTellTargetInfo   = GetLastTellTargetInfo
EditBox.IsWIMFocusActive        = IsWIMFocusActive
EditBox.SetFrameFillColour      = SetFrameFillColour

function EditBox:SetOnSend(fn)
    self.OnSend = fn
end

--- If fn(blizzEditBox) returns true, the overlay is suppressed.
--- Used by Queue to consume hardware events for send continuation.
function EditBox:SetPreShowCheck(fn)
    self.PreShowCheck = fn
end
