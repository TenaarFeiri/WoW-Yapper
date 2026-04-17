#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_icon_gallery_api.lua  —  IconGallery API test suite
-- Run from the repo root:  lua tools/2.0testsuites/test_icon_gallery_api.lua
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
    function self:SetPoint(...) table.insert(self.points, {...}) end
    function self:SetParent(_) end
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
    function self:CreateTexture() 
        local tex = { coords = {} }
        function tex:SetAllPoints() end
        function tex:SetTexture() end
        function tex:SetTexCoord(a,b,c,d) self.coords = {a,b,c,d} end
        function tex:SetColorTexture() end
        return tex
    end
    function self:CreateFontString() 
        local fs = {}
        function fs:SetPoint() end
        function fs:SetText(t) fs.text = t end
        function fs:SetTextColor() end
        return fs
    end
    return self
end

_G.C_Timer = {
    NewTimer = function(duration, callback)
        return { duration = duration, callback = callback, Cancel = function(self) self.cancelled = true end }
    end,
}

_G.UIParent = makeFrame("Frame", "UIParent", nil)
_G.CreateFrame = function(frameType, name, parent)
    return makeFrame(frameType, name, parent)
end

-- Basic debug and utils required by API/IconGallery.
local debugLines = {}
local YapperTable = {}
YapperTable.Utils = {
    DebugPrint = function(_, msg) debugLines[#debugLines + 1] = msg end,
}

-- Load API and IconGallery modules.
local api_loader, err = loadfile("Src/API.lua")
assert(api_loader, "failed to load Src/API.lua: " .. tostring(err))
api_loader("Yapper", YapperTable)

local ig_loader, err2 = loadfile("Src/IconGallery.lua")
assert(ig_loader, "failed to load Src/IconGallery.lua: " .. tostring(err2))
ig_loader("Yapper", YapperTable)

local YapperAPI = _G.YapperAPI
assert(type(YapperAPI) == "table", "YapperAPI not created")
assert(type(YapperTable.IconGallery) == "table", "IconGallery not created")

-- Raw editbox stub.
local function makeRawEditBox(text, cursor)
    local eb = { text = text or "", cursor = cursor or 0 }
    function eb:GetText() return self.text end
    function eb:SetText(t) self.text = t end
    function eb:GetCursorPosition() return self.cursor end
    function eb:SetCursorPosition(pos) self.cursor = pos end
    return eb
end

-- Tests
print("Test 1: Icon gallery API methods")
local raw = makeRawEditBox("Hello {s", 8)

check("IsIconGalleryShown false before show", YapperAPI:IsIconGalleryShown() == false)
check("GetRaidIconData returns 8 entries", (#YapperAPI:GetRaidIconData() == 8))
check("First raid icon code is rt1", YapperAPI:GetRaidIconData()[1].code == "rt1")

YapperAPI:ShowIconGallery(raw, UIParent, "s")
check("ShowIconGallery makes the gallery visible", YapperAPI:IsIconGalleryShown() == true)
check("IconGallery.Active is true after show", YapperTable.IconGallery.Active == true)

YapperAPI:HideIconGallery()
check("HideIconGallery hides the gallery", YapperAPI:IsIconGalleryShown() == false)

print("\nTest 2: Icon selection and callbacks")
local selected = nil
YapperAPI:RegisterCallback("ICON_GALLERY_SELECT", function(index, text, code)
    selected = { index = index, text = text, code = code }
end)

raw = makeRawEditBox("Hello {s", 8)
YapperAPI:ShowIconGallery(raw, UIParent, "s")
local ig = YapperTable.IconGallery
ig:Select(1)
check("Select fires ICON_GALLERY_SELECT callback", selected ~= nil)
check("Select callback index is 1", selected and selected.index == 1)
check("Select callback text is star", selected and selected.text == "star")
check("Select callback code is rt1", selected and selected.code == "rt1")
check("Raw editbox text was replaced", raw:GetText() == "Hello {star} ")
check("Gallery is hidden after select", YapperAPI:IsIconGalleryShown() == false)

print("\nTest 3: HandleKeyDown keyboard shortcut")
raw = makeRawEditBox("Hello {s", 8)
YapperAPI:ShowIconGallery(raw, UIParent, "s")
selected = nil
local consumed = ig:HandleKeyDown("1")
check("HandleKeyDown returns true for digit shortcut", consumed == true)
check("HandleKeyDown selected icon 1", selected ~= nil and selected.index == 1)
check("Raw editbox text replaced by digit shortcut", raw:GetText() == "Hello {star} ")
check("Gallery is hidden after digit shortcut", YapperAPI:IsIconGalleryShown() == false)

print("\nTest 4: OnTextChanged shows and hides gallery")
raw = makeRawEditBox("{mo", 3)
ig:OnTextChanged(raw, UIParent)
check("OnTextChanged opens gallery for '{mo'", ig.Active == true)

ig:OnTextChanged(makeRawEditBox("hello", 5), UIParent)
check("OnTextChanged hides gallery when no '{' trigger", ig.Active == false)

print("\nTest 5: HideIconGallery works when already hidden")
YapperAPI:HideIconGallery()
check("HideIconGallery does not error when already hidden", true)

print("\nTest 6: GetRaidIconData stable when gallery not initialized")
local staticData = YapperAPI:GetRaidIconData()
check("GetRaidIconData returns 8 entries when gallery is present", type(staticData) == "table" and #staticData == 8)
check("GetRaidIconData entries contain text and code", staticData[8].text == "skull" and staticData[8].code == "rt8")

print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
