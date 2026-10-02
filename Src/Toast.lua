--[[
    Toast.lua
    Shared transient notification card for Yapper.

    A small UIParent-parented frame (TOOLTIP strata, same pattern as the
    multiline onboarding hint) with a title, a body line and up to three
    action buttons.  Used by:
      * Spellcheck autocorrect — "Autocorrected 'teh' -> 'the'" with Undo.
      * YAS learned-word notifications — Keep / Unlearn / Ignore.

    Placement avoids the user's interactive surfaces: the solver collects
    the screen rects of the overlay editbox, the multiline editor, the
    suggestion popup, the hint frame and the default chat frame, then tries
    a fixed list of candidate zones until one does not overlap any occupied
    rect.  The result is always clamped to the screen.

    Lifetime: holds for `duration` seconds, then fades.  Hovering pauses
    the hold timer so the user can always reach the buttons.
]]

local _, YapperTable = ...
local Toast = {}
YapperTable.Toast = Toast

local L = YapperTable.Strings
local function S(key, ...)
    if L then return L:Get(key, ...) end
    return tostring(key)
end

local type          = type
local ipairs        = ipairs
local table_insert  = table.insert
local table_remove  = table.remove
local math_min      = math.min
local math_max      = math.max
local math_ceil     = math.ceil
local string_format = string.format
local tostring      = tostring

local TOAST_WIDTH_MAX   = 320
local TOAST_PAD         = 8
local TOAST_GAP         = 6   -- gap between toast and the rect it hugs
local SCREEN_PAD        = 8
local TOAST_FADE_TIME   = 0.35
local MAX_BUTTONS       = 3
local QUEUE_CAP         = 3   -- pending toasts; oldest dropped beyond this

Toast.Frame  = nil
Toast._queue = {}

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function EnsureFrame()
    if Toast.Frame then return Toast.Frame end

    local frame = CreateFrame("Frame", "YapperToast", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", TOAST_PAD + 4, -TOAST_PAD - 2)
    title:SetJustifyH("LEFT")
    frame._title = title

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    body:SetJustifyH("LEFT")
    frame._body = body

    frame._buttons = {}
    for i = 1, MAX_BUTTONS do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(64, 18)
        btn:Hide()
        frame._buttons[i] = btn
    end

    -- Hovering pauses the hold-out so the buttons stay reachable.
    frame:SetScript("OnEnter", function(self)
        if not self._expiresAt then return end
        self._holdRemain = self._expiresAt - GetTime()
        self._expiresAt = nil
        if Toast._holdTimer and Toast._holdTimer.Cancel then
            Toast._holdTimer:Cancel()
        end
        Toast._holdTimer = nil
    end)
    frame:SetScript("OnLeave", function(self)
        if self._holdRemain then
            local remain = self._holdRemain
            self._holdRemain = nil
            self._expiresAt = GetTime() + remain
            Toast:_ArmHoldTimer(remain)
        end
    end)

    Toast.Frame = frame
    if YapperTable.Core and type(YapperTable.Core.RegisterFrame) == "function" then
        YapperTable.Core:RegisterFrame("Toast", "Frame", frame)
    end
    return frame
end

-- ---------------------------------------------------------------------------
-- Placement solver
-- ---------------------------------------------------------------------------

--- Screen-space rect {l, r, b, t} for a shown frame, or nil.
local function FrameRect(f)
    if not f or not f.IsShown or not f:IsShown() then return nil end
    if not f.GetLeft then return nil end
    local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
    if not (l and r and b and t) then return nil end
    return { l = l, r = r, b = b, t = t }
end

local function RectsOverlap(a, b)
    return not (a.r <= b.l or a.l >= b.r or a.t <= b.b or a.b >= b.t)
end

--- Fold a chat-cluster child (tab strip, edit box) into the frame rect.
--- Hidden frames report no screen rect, so fall back to the child's anchor
--- on the chat frame and reserve the strip it will occupy when shown.
local function ExtendClusterRect(rect, chatFrame, child)
    if not child then return end
    local cr = FrameRect(child)
    if cr then
        if cr.b < rect.b then rect.b = cr.b end
        if cr.t > rect.t then rect.t = cr.t end
        return
    end
    if not (child.GetPoint and child.GetHeight) then return end
    local _, relTo, relPoint = child:GetPoint(1)
    if relTo ~= chatFrame or type(relPoint) ~= "string" then return end
    local h = child:GetHeight() or 0
    if h <= 0 then return end
    if relPoint:find("TOP") then
        rect.t = rect.t + h
    elseif relPoint:find("BOTTOM") then
        rect.b = rect.b - h
    end
end

--- The visible chat cluster is taller than DEFAULT_CHAT_FRAME alone: the
--- tab strip sits above its top edge and the edit box hangs below its
--- bottom edge.  Anchoring to the extended rect keeps toasts clear of both.
local function ChatClusterRect()
    local f = DEFAULT_CHAT_FRAME
    local rect = FrameRect(f)
    if not rect then return nil end
    ExtendClusterRect(rect, f, f.Tab or _G["ChatFrame1Tab"])
    ExtendClusterRect(rect, f, f.editBox)
    return rect
end

local function OccupiedRects()
    local rects = {}
    local eb   = YapperTable.EditBox
    local ml   = YapperTable.Multiline
    local sc   = YapperTable.Spellcheck
    if eb and eb.Overlay then rects[#rects + 1] = FrameRect(eb.Overlay) end
    if eb and eb.OverlayEdit then rects[#rects + 1] = FrameRect(eb.OverlayEdit) end
    if ml and ml.Frame then rects[#rects + 1] = FrameRect(ml.Frame) end
    if sc and sc.SuggestionFrame then rects[#rects + 1] = FrameRect(sc.SuggestionFrame) end
    if sc and sc.HintFrame then rects[#rects + 1] = FrameRect(sc.HintFrame) end
    if DEFAULT_CHAT_FRAME then rects[#rects + 1] = ChatClusterRect() end

    -- Filter nils (hidden frames) out in-place.
    local out = {}
    for _, r in ipairs(rects) do if r then out[#out + 1] = r end end
    return out
end

--- Candidate zones are {x, y} BOTTOMLEFT screen coords for the toast.
--- Ordered by preference: beside/above/below the input, above/below/beside
--- the chat frame, then corners.
local function CandidatePositions(w, h, screenW, screenH, occupied)
    local cands = {}

    local inputRect
    local ml = YapperTable.Multiline
    local eb = YapperTable.EditBox
    if ml and ml.Frame and ml.Frame:IsShown() then
        inputRect = FrameRect(ml.Frame)
    elseif eb and eb.Overlay and eb.Overlay:IsShown() then
        inputRect = FrameRect(eb.Overlay)
    end

    if inputRect then
        -- Beside the input, vertically centred.
        cands[#cands + 1] = { x = inputRect.r + TOAST_GAP,
            y = inputRect.b + (inputRect.t - inputRect.b - h) / 2 }
        cands[#cands + 1] = { x = inputRect.l - TOAST_GAP - w,
            y = inputRect.b + (inputRect.t - inputRect.b - h) / 2 }
        -- Directly above / below the input, left-aligned.
        cands[#cands + 1] = { x = inputRect.l, y = inputRect.t + TOAST_GAP }
        cands[#cands + 1] = { x = inputRect.l, y = inputRect.b - TOAST_GAP - h }
    end

    -- Chat-frame candidates: above, below, then beside (top-aligned).  A
    -- chat window hugging the screen top makes "above" clamp back onto the
    -- frame itself, so the below/beside fallbacks keep the toast near the
    -- context instead of dropping to a far corner.
    local chat = ChatClusterRect()
    if chat then
        cands[#cands + 1] = { x = chat.l, y = chat.t + TOAST_GAP }
        cands[#cands + 1] = { x = chat.l, y = chat.b - TOAST_GAP - h }
        cands[#cands + 1] = { x = chat.r + TOAST_GAP, y = chat.t - h }
        cands[#cands + 1] = { x = chat.l - TOAST_GAP - w, y = chat.t - h }
    end

    -- Corners.
    cands[#cands + 1] = { x = screenW - w - SCREEN_PAD, y = SCREEN_PAD }
    cands[#cands + 1] = { x = screenW - w - SCREEN_PAD, y = screenH - h - SCREEN_PAD }
    cands[#cands + 1] = { x = SCREEN_PAD, y = screenH - h - SCREEN_PAD }

    return cands
end

--- Pick a screen position: first candidate whose rect overlaps nothing
--- occupied, else the last candidate clamped into the screen.
function Toast:_PickPosition(w, h)
    local screenW = (UIParent and UIParent:GetWidth()) or 1024
    local screenH = (UIParent and UIParent:GetHeight()) or 768
    local occupied = OccupiedRects()
    local cands = CandidatePositions(w, h, screenW, screenH, occupied)

    local fallback
    for _, c in ipairs(cands) do
        local x = math_max(SCREEN_PAD, math_min(c.x, screenW - w - SCREEN_PAD))
        local y = math_max(SCREEN_PAD, math_min(c.y, screenH - h - SCREEN_PAD))
        local rect = { l = x, r = x + w, b = y, t = y + h }
        fallback = fallback or { x = x, y = y }
        local blocked = false
        for _, o in ipairs(occupied) do
            if RectsOverlap(rect, o) then blocked = true break end
        end
        if not blocked then
            return x, y
        end
    end
    -- Everything overlapped: bottom-right is least bad.
    return screenW - w - SCREEN_PAD, SCREEN_PAD
end

-- ---------------------------------------------------------------------------
-- Lifetime
-- ---------------------------------------------------------------------------

function Toast:_ArmHoldTimer(remain)
    if not (C_Timer and C_Timer.NewTimer) then return end
    if self._holdTimer and self._holdTimer.Cancel then
        self._holdTimer:Cancel()
    end
    local timer
    timer = C_Timer.NewTimer(remain, function()
        if self._holdTimer ~= timer then return end
        self._holdTimer = nil
        self:_Dismiss()
    end)
    self._holdTimer = timer
end

function Toast:_Dismiss()
    local frame = self.Frame
    if not frame then return end
    if self._holdTimer and self._holdTimer.Cancel then
        self._holdTimer:Cancel()
    end
    self._holdTimer = nil
    frame._expiresAt = nil
    frame._holdRemain = nil
    if UIFrameFadeOut then
        UIFrameFadeOut(frame, TOAST_FADE_TIME, frame:GetAlpha() or 1, 0)
    else
        frame:SetAlpha(0)
    end
    -- Hide after the fade completes (alpha 0 frames still eat mouse hits).
    if C_Timer and C_Timer.After then
        C_Timer.After(TOAST_FADE_TIME + 0.05, function()
            if frame:GetAlpha() <= 0.01 then frame:Hide() end
            Toast:_PumpQueue()
        end)
    else
        frame:Hide()
        self:_PumpQueue()
    end
end

function Toast:_PumpQueue()
    if self.Frame and self.Frame:IsShown() then return end
    local nextToast = table_remove(self._queue, 1)
    if nextToast then
        self:Show(nextToast)
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Show a toast card.  opts = { title, body, buttons = { {label, onClick} },
--- duration = seconds }.  A second show while one is visible queues.
function Toast:Show(opts)
    if type(opts) ~= "table" then return end
    if self.Frame and self.Frame:IsShown() then
        if #self._queue >= QUEUE_CAP then
            table_remove(self._queue, 1) -- drop the oldest pending toast
        end
        table_insert(self._queue, opts)
        return
    end

    local frame = EnsureFrame()
    local duration = tonumber(opts.duration) or 10

    frame._title:SetText(tostring(opts.title or ""))
    frame._body:SetText(tostring(opts.body or ""))

    -- Buttons, right-aligned under the body.
    local buttons = opts.buttons or {}
    local shownBtns = 0
    local btnRowW = 0
    for i, btn in ipairs(frame._buttons) do
        local spec = buttons[i]
        if spec then
            btn:SetText(tostring(spec.label or "?"))
            local bw = math_max(52, (btn:GetTextWidth() or 40) + 16)
            btn:SetSize(bw, 18)
            btn._onClick = spec.onClick
            btn:SetScript("OnClick", function(self)
                if self._onClick then self._onClick() end
                Toast:_Dismiss()
            end)
            btn:Show()
            shownBtns = shownBtns + 1
            btnRowW = btnRowW + bw + 6
        else
            btn:Hide()
        end
    end
    if shownBtns > 0 then btnRowW = btnRowW - 6 end

    -- Lay out: buttons sit on a row under the body, right-aligned —
    -- anchor the last button to the frame's bottom-right and chain
    -- right-to-left so the widest label never pushes off-card.
    if shownBtns > 0 then
        local prev
        for i = shownBtns, 1, -1 do
            local btn = frame._buttons[i]
            btn:ClearAllPoints()
            if prev then
                btn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
            else
                btn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -TOAST_PAD, TOAST_PAD)
            end
            prev = btn
        end
    end

    local textW = math_max(frame._title:GetStringWidth() or 0,
        frame._body:GetStringWidth() or 0)
    local w = math_ceil(math_min(TOAST_WIDTH_MAX, math_max(textW + TOAST_PAD * 2 + 8, btnRowW + TOAST_PAD * 2 + 8)))
    local bodyH = (frame._body:GetStringHeight() or 12)
    local titleH = (frame._title:GetStringHeight() or 10)
    local h = TOAST_PAD + titleH + 3 + bodyH + (shownBtns > 0 and (18 + 8) or 0) + TOAST_PAD
    frame:SetSize(w, h)

    local x, y = self:_PickPosition(w, h)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)

    frame:SetAlpha(0)
    frame:Show()
    if UIFrameFadeIn then
        UIFrameFadeIn(frame, 0.12, 0, 1)
    else
        frame:SetAlpha(1)
    end

    -- Hold timer (paused while hovered).
    frame._expiresAt = GetTime() + duration
    self:_ArmHoldTimer(duration)
end

--- Convenience: the autocorrect card with an Undo button.
function Toast:ShowCorrection(corr)
    if not corr then return end
    local ac = YapperTable.Spellcheck and YapperTable.Spellcheck.Autocorrect
    if not ac then return end
    self:Show({
        title    = S("ui.toast.autocorrected"),
        body     = S("ui.toast.autocorrectBody", tostring(corr.original),
            tostring(corr.applied)),
        duration = 4,
        buttons  = {
            { label = S("ui.toast.undo"), onClick = function()
                ac:UndoByToast(corr.undoEntry)
            end },
        },
    })
end

--- Convenience: the learned-word card with Keep / Unlearn / Ignore.
function Toast:ShowLearned(word, locale)
    local sc = YapperTable.Spellcheck
    if not sc then return end
    local loc = locale or (sc.GetLocale and sc:GetLocale()) or "enUS"
    self:Show({
        title    = S("ui.toast.learned"),
        body     = S("ui.toast.learnedBody", tostring(word), tostring(loc)),
        duration = 10,
        buttons  = {
            { label = S("ui.toast.keep"), onClick = function() end },
            { label = S("ui.toast.unlearn"), onClick = function()
                local yas = sc.YAS
                if yas and yas.UnlearnWord then yas:UnlearnWord(word, loc) end
            end },
            { label = S("ui.toast.ignore"), onClick = function()
                if sc.IgnoreWord then
                    sc:IgnoreWord(loc, word)
                    if sc.YAS and sc.YAS.PinIntent then
                        sc.YAS:PinIntent(word, "WAIVER", loc)
                    end
                end
            end },
        },
    })
end

--- Subscribe to the learned-word event.  Called once from Chat:Init.
function Toast:Init()
    if self._subscribed then return end
    self._subscribed = true
    local api = YapperTable.API
    if api and api.RegisterCallback then
        api:RegisterCallback("YAS_WORD_LEARNED", function(word, locale)
            local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
            if cfg and cfg.LearnToastEnabled == false then return end
            Toast:ShowLearned(word, locale)
        end)
    end
end

return Toast
