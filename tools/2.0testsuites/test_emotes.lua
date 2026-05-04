#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_emotes.lua  —  Emotes API test suite
-- Run from the repo root:  lua tools/2.0testsuites/test_emotes.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        io.write("  [" .. PASS .. "] " .. label .. "\n")
    else
        FAILURES = FAILURES + 1
        io.write("  [" .. FAIL .. "] " .. label .. "\n")
    end
end

-- Minimal WoW UI mock for CreateFrame + frame methods.
local function makeFrame(frameType, name, parent)
    local self = {
        frameType = frameType,
        name = name,
        parent = parent,
        scripts = {},
        shown = false,
        enabled = true,
        alpha = 1,
        text = nil,
        cursor = 0,
        points = {},
    }

    function self:SetSize() end
    function self:SetFrameStrata() end
    function self:SetFrameLevel() end
    function self:SetBackdrop() end
    function self:SetBackdropColor() end
    function self:SetBackdropBorderColor() end
    function self:Hide() self.shown = false end
    function self:Show() self.shown = true end
    function self:IsShown() return self.shown end
    function self:ClearAllPoints() self.points = {} end
    function self:SetAllPoints() end
    function self:SetPoint(...) table.insert(self.points, {...}) end
    function self:SetParent(_) end
    function self:EnableMouse(_) end
    function self:Enable() self.enabled = true end
    function self:Disable() self.enabled = false end
    function self:IsEnabled() return self.enabled end
    function self:SetAlpha(a) self.alpha = a end
    function self:GetAlpha() return self.alpha end
    function self:SetText(t) self.text = t end
    function self:GetText() return self.text end
    function self:SetCursorPosition(pos) self.cursor = pos end
    function self:GetCursorPosition() return self.cursor end
    function self:SetScript(event, fn) self.scripts[event] = fn end
    function self:RegisterForClicks() end
    function self:CreateTexture() 
        local tex = { coords = {} }
        function tex:SetAllPoints() end
        function tex:SetTexture() end
        function tex:SetTexCoord(a,b,c,d) self.coords = {a,b,c,d} end
        function tex:SetColorTexture() end
        function tex:Show() tex.shown = true end
        function tex:Hide() tex.shown = false end
        return tex
    end
    function self:CreateFontString() 
        local fs = {}
        function fs:SetPoint() end
        function fs:SetText(t) fs.text = t end
        function fs:SetTextColor() end
        function fs:SetJustifyH() end
        function fs:SetWordWrap() end
        function fs:GetStringWidth() return 100 end
        return fs
    end
    return self
end

_G.UIParent = makeFrame("Frame", "UIParent", nil)
_G.CreateFrame = function(frameType, name, parent)
    return makeFrame(frameType, name, parent)
end

-- Mock WoW API for Emotes
_G.MAXEMOTEINDEX = 3
_G.EMOTE1_TOKEN = "WAVE"
_G.EMOTE1_CMD1 = "/wave"
_G.EMOTE2_TOKEN = "DANCE"
_G.EMOTE2_CMD1 = "/dance"
_G.EMOTE3_TOKEN = "AGREE"
_G.EMOTE3_CMD1 = "/agree"

local YapperTable = {}
local loader, err = loadfile("Src/Emotes.lua")
assert(loader, "failed to load Src/Emotes.lua: " .. tostring(err))
loader("Yapper", YapperTable)

local Emotes = YapperTable.Emotes
assert(type(Emotes) == "table", "Emotes not created")

-- Raw editbox stub.
local function makeRawEditBox(text, cursor)
    local eb = { text = text or "", cursor = cursor or 0 }
    function eb:GetText() return self.text end
    function eb:SetText(t) self.text = t end
    function eb:GetCursorPosition() return self.cursor end
    function eb:SetCursorPosition(pos) self.cursor = pos end
    return eb
end

print("Test 1: Initialization")
Emotes:Init()
check("EmoteList is built", #Emotes.EmoteList == 3)
check("EmoteList is sorted alphabetically", Emotes.EmoteList[1].cmd == "/agree" and Emotes.EmoteList[3].cmd == "/wave")

print("\nTest 2: Hint Frame")
local eb = makeRawEditBox("/", 1)
Emotes:ShowHint(eb)
check("HintFrame is shown", Emotes.HintFrame:IsShown() == true)
Emotes:HideHint()
check("HintFrame is hidden", Emotes.HintFrame:IsShown() == false)

print("\nTest 3: Menu Open and Filter")
Emotes:OpenMenu(eb)
check("MenuFrame is shown", Emotes.MenuFrame:IsShown() == true)
check("ActiveIndex is 1 on open", Emotes.ActiveIndex == 1)
check("FilteredList has 3 items initially", #Emotes.FilteredList == 3)

Emotes:FilterMenu("/w")
check("FilteredList has 1 item after filtering '/w'", #Emotes.FilteredList == 1)
check("FilteredList item is '/wave'", Emotes.FilteredList[1].cmd == "/wave")

print("\nTest 4: Selection and Application")
Emotes:OpenMenu(eb)
Emotes:MoveSelection(1)
check("ActiveIndex moves to 2 after MoveSelection(1)", Emotes.ActiveIndex == 2)
Emotes:MoveSelection(-1)
check("ActiveIndex moves to 1 after MoveSelection(-1)", Emotes.ActiveIndex == 1)

Emotes:ApplySelection()
check("EditBox text is replaced with '/agree'", eb:GetText() == "/agree")
check("EditBox cursor is at the end of the text", eb:GetCursorPosition() == 6)
check("MenuFrame is hidden after application", Emotes.MenuFrame:IsShown() == false)

print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
