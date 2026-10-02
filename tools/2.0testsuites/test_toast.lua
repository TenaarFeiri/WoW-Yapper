#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_toast.lua  --  Toast widget unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_toast.lua
--
-- Covers: lazy frame creation, show/queue semantics, queue cap, hover-pause,
-- placement solver (occupied-rect avoidance + screen clamping).
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================
local fakeNow = 1000
_G.GetTime = function() return fakeNow end
_G.DEFAULT_CHAT_FRAME = nil

local timers = {}
_G.C_Timer = {
    NewTimer = function(sec, fn)
        local t = { _fn = fn, _sec = sec, cancelled = false }
        function t:Cancel() self.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
    After = function(_, fn) fn() end,
}
local function fireTimer(t)
    if t and not t.cancelled then t._fn() end
end

local function MockRegion()
    return {
        SetPoint        = function() end,
        ClearAllPoints  = function() end,
        SetJustifyH     = function() end,
        SetText         = function(self, t) self._text = t end,
        GetText         = function(self) return self._text end,
        GetStringWidth  = function() return 120 end,
        GetStringHeight = function() return 12 end,
        GetTextWidth    = function() return 40 end,
        SetSize         = function() end,
        Show            = function(self) self._shown = true end,
        Hide            = function(self) self._shown = false end,
        IsShown         = function(self) return self._shown == true end,
        SetScript       = function(self, k, fn) self["_" .. k] = fn end,
    }
end

local function MockFrame()
    local f = MockRegion()
    f.SetFrameStrata = function() end
    f.SetFrameLevel  = function() end
    f.SetClampedToScreen = function() end
    f.EnableMouse    = function() end
    f.SetBackdrop    = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.SetAlpha       = function(self, a) self._alpha = a end
    f.GetAlpha       = function(self) return self._alpha or 1 end
    f.CreateFontString = function() return MockRegion() end
    f.GetLeft        = function(self) return self._l end
    f.GetRight       = function(self) return self._r end
    f.GetBottom      = function(self) return self._b end
    f.GetTop         = function(self) return self._t end
    f._alpha = 1
    return f
end

local createdButtons = {}
_G.CreateFrame = function(kind, name, parent, template)
    local f = MockFrame()
    f._kind = kind
    f._parent = parent
    if kind == "Button" then createdButtons[#createdButtons + 1] = f end
    return f
end

local UIW, UIH = 1920, 1080
_G.UIParent = { GetWidth = function() return UIW end, GetHeight = function() return UIH end }
_G.UIFrameFadeIn  = nil
_G.UIFrameFadeOut = nil

local YapperName = "Yapper"
local YapperTable = { Config = { Spellcheck = { LearnToastEnabled = true } } }

local loader, err = loadfile("Src/Toast.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)
local Toast = YapperTable.Toast

local function reset()
    Toast.Frame = nil
    Toast._queue = {}
    Toast._holdTimer = nil
    timers = {}
end

-- ===========================================================================
-- Test 1: lazy creation + show
-- ===========================================================================
print("\nTest 1: lazy creation + show")

reset()
check("frame not built before first show", Toast.Frame == nil)
Toast:Show({ title = "T", body = "B", duration = 5 })
check("frame created on first show", Toast.Frame ~= nil)
check("frame shown", Toast.Frame:IsShown())
check("title set", Toast.Frame._title:GetText() == "T")
check("body set", Toast.Frame._body:GetText() == "B")
check("hold timer armed", #timers == 1)

-- ===========================================================================
-- Test 2: queueing
-- ===========================================================================
print("\nTest 2: queueing")

reset()
Toast:Show({ title = "one", body = "b1", duration = 5 })
Toast:Show({ title = "two", body = "b2", duration = 5 })
check("second show queues", #Toast._queue == 1)
check("frame still shows first", Toast.Frame._title:GetText() == "one")

-- Dismiss pumps the queue.
Toast:_Dismiss()
check("queued toast shown after dismiss", Toast.Frame._title:GetText() == "two")
check("queue drained", #Toast._queue == 0)

-- Cap: QUEUE_CAP = 3 pending; a fifth drop-in evicts the oldest.
reset()
Toast:Show({ title = "live", body = "", duration = 5 })
for i = 1, 5 do
    Toast:Show({ title = "q" .. i, body = "", duration = 5 })
end
check("queue capped at 3", #Toast._queue == 3)
check("oldest dropped (q2 now first)", Toast._queue[1].title == "q3")

-- ===========================================================================
-- Test 3: hold timer + hover pause
-- ===========================================================================
print("\nTest 3: hold timer + hover pause")

reset()
Toast:Show({ title = "t", body = "b", duration = 5 })
fakeNow = fakeNow + 2 -- 2s into the 5s hold
Toast.Frame:_OnEnter()
check("hover pauses (expiry cleared)", Toast.Frame._expiresAt == nil)
check("remaining time recorded", Toast.Frame._holdRemain ~= nil
    and math.abs(Toast.Frame._holdRemain - 3) < 0.01)
check("hold timer cancelled while hovered", timers[1].cancelled == true)

Toast.Frame:_OnLeave()
check("resume re-arms timer", Toast.Frame._expiresAt ~= nil)
check("new timer armed for remainder",
    #timers == 2 and math.abs(timers[2]._sec - 3) < 0.01)

-- Expiry hides the frame (C_Timer.After fires immediately in this env).
fireTimer(timers[2])
check("expiry hides the toast", Toast.Frame:IsShown() == false)

-- ===========================================================================
-- Test 4: placement solver avoids occupied rects
-- ===========================================================================
print("\nTest 4: placement solver")

reset()
-- No occupied rects: first candidate region... without an input rect the
-- solver falls to corners; verify it returns in-bounds coordinates.
local x, y = Toast:_PickPosition(200, 60)
check("position in screen bounds",
    x >= 0 and y >= 0 and x + 200 <= UIW and y + 60 <= UIH)

-- Occupy the bottom-right corner via a fake chat frame; the solver must not
-- place the toast inside it.
_G.DEFAULT_CHAT_FRAME = MockFrame()
DEFAULT_CHAT_FRAME._shown = true
DEFAULT_CHAT_FRAME._l, DEFAULT_CHAT_FRAME._r = UIW - 400, UIW
DEFAULT_CHAT_FRAME._b, DEFAULT_CHAT_FRAME._t = 0, 300
Toast.Frame = MockFrame() -- pretend no overlay/multiline/hints are up
YapperTable.EditBox = nil
YapperTable.Multiline = nil
x, y = Toast:_PickPosition(200, 60)
local overlaps = not (x + 200 <= UIW - 400 or x >= UIW or y + 60 <= 0 or y >= 300)
check("avoids chat-frame rect", overlaps == false)
check("still in bounds", x >= 0 and y >= 0 and x + 200 <= UIW and y + 60 <= UIH)

-- An input rect to the left gets a toast placed beside/above it, not inside.
YapperTable.EditBox = { Overlay = MockFrame() }
YapperTable.EditBox.Overlay._shown = true
YapperTable.EditBox.Overlay._l, YapperTable.EditBox.Overlay._r = 10, 400
YapperTable.EditBox.Overlay._b, YapperTable.EditBox.Overlay._t = 10, 40
x, y = Toast:_PickPosition(200, 60)
local inOverlay = not (x + 200 <= 10 or x >= 400 or y + 60 <= 10 or y >= 40)
check("avoids input overlay rect", inOverlay == false)

YapperTable.EditBox = nil
_G.DEFAULT_CHAT_FRAME = nil

-- ===========================================================================
-- Test 5: learned-word card wiring
-- ===========================================================================
print("\nTest 5: learned-word card")

reset()
local unlearned, ignored = nil, nil
YapperTable.Spellcheck = {
    GetLocale   = function() return "tloc" end,
    IgnoreWord  = function(_, loc, w) ignored = w end,
    YAS         = { UnlearnWord = function(_, w) unlearned = w end,
                    PinIntent = function() end },
}
Toast:ShowLearned("someword", "tloc")
check("learned toast shown", Toast.Frame:IsShown())
local btns = Toast.Frame._buttons
check("three buttons wired", btns[1]._shown == true
    and btns[2]._shown == true and btns[3]._shown == true)

-- Buttons: [1]=Keep [2]=Unlearn [3]=Ignore (creation order = buttons[i]).
btns[2]._OnClick(btns[2])
check("unlearn button calls UnlearnWord", unlearned == "someword")

reset()
Toast:ShowLearned("otherword", "tloc")
Toast.Frame._buttons[3]._OnClick(Toast.Frame._buttons[3])
check("ignore button calls IgnoreWord", ignored == "otherword")

-- ===========================================================================
-- Summary
-- ===========================================================================
print(string.format("\n%d tests, %d failures", TESTS, FAILURES))
os.exit(FAILURES == 0 and 0 or 1)
