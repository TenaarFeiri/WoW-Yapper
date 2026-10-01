#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_shadow_tint.lua  —  Channel-coloured drop shadow
-- Run from the repo root: lua tools/2.0testsuites/test_shadow_tint.lua
--
-- Covers the ShadowChannelColor / MultilineShadowChannelColor feature:
--   * ApplyShadowTint recolours a frame's _yapperShadows textures with the
--     shared alpha falloff.
--   * EditBox:RefreshLabel stores _lastChannelRGB and retints the overlay
--     shadow to the resolved channel colour when the flag is on.
--   * RefreshOverlayVisuals uses _lastChannelRGB when the flag is on, and the
--     configured ShadowColor when it is off.
--   * Multiline._RefreshLabel applies the same tint to the storyteller frame.
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

local function approxEq(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.001
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G.hooksecurefunc = function() end
_G.ChatTypeInfo = {
    SAY   = { r = 1.0, g = 1.0, b = 1.0 },
    PARTY = { r = 0.67, g = 0.67, b = 1.0 },
}
_G.GetChannelName = function() return 0, nil end

-- Generic region mock: covers frames, textures and fontstrings.
local function MockRegion(name)
    local f = { _name = name, _shown = false }
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:SetAllPoints() end
    function f:SetWidth() end
    function f:GetWidth() return 100 end
    function f:SetFrameLevel() end
    function f:GetFrameLevel() return 1 end
    function f:SetColorTexture(r, g, b, a)
        self._r, self._g, self._b, self._a = r, g, b, a
    end
    function f:SetText() end
    function f:SetTextColor(r, g, b) self._tr, self._tg, self._tb = r, g, b end
    function f:SetTextInsets() end
    function f:GetStringWidth() return 40 end
    function f:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function f:SetFont() end
    function f:SetFontObject() end
    function f:GetFontObject() return nil end
    function f:SetAttribute() end
    function f:GetAttribute() return nil end
    function f:UpdateHeader() end
    function f:SetBackdropBorderColor() end
    return f
end

local function MakeShadowedFrame(name)
    local f = MockRegion(name)
    f._yapperShadowLayer = MockRegion(name .. "ShadowLayer")
    f._yapperShadows = {
        MockRegion(name .. "S1"),
        MockRegion(name .. "S2"),
        MockRegion(name .. "S3"),
    }
    return f
end

-- ===========================================================================
-- YapperTable + module loading (mirrors Hooks/Hub.lua wiring)
-- ===========================================================================

local YapperTable = {}

YapperTable.Utils = {
    IsSecret = function() return false end,
    IsChatLockdown = function() return false end,
    IsChatOrCombatLockdown = function() return false end,
    IsUnambiguousBnetTarget = function() return false end,
    SanitizeTarget = function(_, value) return value end,
    VerbosePrint = function() end,
    DebugPrint = function() end,
}

YapperTable.Interface = {
    IsColourTable = function(c)
        return type(c) == "table" and type(c.r) == "number"
            and type(c.g) == "number" and type(c.b) == "number"
    end,
}

local PARTY_RGB = { r = 0.2, g = 0.4, b = 0.8 }
YapperTable.Config = {
    System = { DEBUG = false },
    EditBox = {
        ShadowChannelColor = true,
        MultilineShadowChannelColor = true,
        Shadow = true,
        ShadowColor = { r = 0, g = 0, b = 0, a = 0.5 },
        ShadowSize = 4,
        ChannelColorMode = {},
        ChannelTextColors = { PARTY = PARTY_RGB },
    },
}

local EditBox = {
    _LABEL_PREFIXES = { SAY = "Say", PARTY = "Party" },
    SetFrameFillColour = function() end,
}
YapperTable.EditBox = EditBox
YapperTable.State = {}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/EditBox/Overlay.lua")

-- Stub EditBoxHooksCore the way Hub.lua populates it.
YapperTable.EditBoxHooksCore = {
    CHATTYPE_TO_OVERRIDE_KEY = {
        SAY = "SAY", PARTY = "PARTY",
    },
    GROUP_CHAT_TYPES = { PARTY = true },
    BuildLabelText = function() return "Party:", 0.67, 0.67, 1.0 end,
    GetLabelUsableWidth = function() return 100 end,
    ResetLabelToBaseFont = function() end,
    TruncateLabelToWidth = function(_, label) return label end,
    FitLabelFontToWidth = function() return true end,
    UpdateLabelBackgroundForText = function() end,
    ApplyShadowTint = EditBox._ApplyShadowTint,
}

loadModule("Src/Hooks/Label.lua")
loadModule("Src/Multiline.lua")

-- ===========================================================================
-- ApplyShadowTint (EditBox._ApplyShadowTint)
-- ===========================================================================
print("ApplyShadowTint")

do
    local f = MakeShadowedFrame("TintTarget")
    EditBox._ApplyShadowTint(f, 0.5, 0.25, 0.75, 0.4)
    local t = f._yapperShadows
    check("layer 1 gets rgb", approxEq(t[1]._r, 0.5) and approxEq(t[1]._g, 0.25) and approxEq(t[1]._b, 0.75))
    check("layer 1 alpha = base*0.5", approxEq(t[1]._a, 0.4 * 0.5))
    check("layer 2 alpha = base*0.3", approxEq(t[2]._a, 0.4 * 0.3))
    check("layer 3 alpha = base*0.15", approxEq(t[3]._a, 0.4 * 0.15))

    local bare = MockRegion("NoShadows")
    EditBox._ApplyShadowTint(bare, 1, 0, 0, 1)
    check("no-op on frame without _yapperShadows", bare._r == nil)
end

-- ===========================================================================
-- EditBox:RefreshLabel stores + applies the channel tint
-- ===========================================================================
print("EditBox:RefreshLabel")

local function BuildEditBox(shadowCfg)
    EditBox.Overlay = MakeShadowedFrame("Overlay")
    EditBox.LabelBg = MockRegion("LabelBg")
    EditBox.ChannelLabel = MockRegion("ChannelLabel")
    EditBox.OverlayEdit = MockRegion("OverlayEdit")
    EditBox.OrigEditBox = MockRegion("OrigEditBox")
    EditBox.ChatType = "PARTY"
    EditBox.Target = nil
    EditBox.ChannelName = nil
    EditBox._lastChannelRGB = nil
end

-- Flag on: shadow follows resolved (user-override) channel colour.
do
    BuildEditBox()
    YapperTable.Config.EditBox.ShadowChannelColor = true
    EditBox:RefreshLabel()
    check("_lastChannelRGB stored",
        EditBox._lastChannelRGB and approxEq(EditBox._lastChannelRGB.r, PARTY_RGB.r)
        and approxEq(EditBox._lastChannelRGB.b, PARTY_RGB.b))
    local t = EditBox.Overlay._yapperShadows
    check("overlay shadow tinted to channel colour",
        approxEq(t[1]._r, PARTY_RGB.r) and approxEq(t[1]._g, PARTY_RGB.g)
        and approxEq(t[1]._b, PARTY_RGB.b))
    check("overlay shadow keeps configured base alpha",
        approxEq(t[1]._a, 0.5 * 0.5))
end

-- Flag off: RefreshLabel stores the colour but does not retint.
do
    BuildEditBox()
    YapperTable.Config.EditBox.ShadowChannelColor = false
    EditBox:RefreshLabel()
    check("flag off: _lastChannelRGB still stored",
        EditBox._lastChannelRGB and approxEq(EditBox._lastChannelRGB.r, PARTY_RGB.r))
    check("flag off: shadow textures untouched",
        EditBox.Overlay._yapperShadows[1]._r == nil)
    YapperTable.Config.EditBox.ShadowChannelColor = true
end

-- ===========================================================================
-- RefreshOverlayVisuals honours the flag + stored colour
-- ===========================================================================
print("RefreshOverlayVisuals")

local cfgBase = {
    Shadow = true,
    ShadowColor = { r = 0.9, g = 0.1, b = 0.1, a = 0.5 },
    ShadowSize = 4,
    InputBg = {}, LabelBg = {}, BorderColor = {}, TextColor = {},
}

do
    BuildEditBox()
    EditBox._lastChannelRGB = { r = 0.1, g = 0.9, b = 0.2 }
    local cfg = {}
    for k, v in pairs(cfgBase) do cfg[k] = v end
    cfg.ShadowChannelColor = true
    EditBox._RefreshOverlayVisuals(EditBox, cfg, false, 0)
    local t = EditBox.Overlay._yapperShadows
    check("visuals: channel rgb applied when flag on",
        approxEq(t[1]._r, 0.1) and approxEq(t[1]._g, 0.9) and approxEq(t[1]._b, 0.2))
    check("visuals: alpha still uses ShadowColor.a", approxEq(t[1]._a, 0.5 * 0.5))
end

do
    BuildEditBox()
    EditBox._lastChannelRGB = { r = 0.1, g = 0.9, b = 0.2 }
    local cfg = {}
    for k, v in pairs(cfgBase) do cfg[k] = v end
    cfg.ShadowChannelColor = false
    EditBox._RefreshOverlayVisuals(EditBox, cfg, false, 0)
    local t = EditBox.Overlay._yapperShadows
    check("visuals: ShadowColor used when flag off",
        approxEq(t[1]._r, 0.9) and approxEq(t[1]._g, 0.1) and approxEq(t[1]._b, 0.1))
end

-- ===========================================================================
-- Multiline label refresh tints the storyteller frame's shadow
-- ===========================================================================
print("Multiline._RefreshLabel")

-- RefreshMLLabel resolves via _BuildLabelText + ChannelTextColors.
EditBox._BuildLabelText = function() return "[Party]", 0.67, 0.67, 1.0 end

do
    local ml = {
        ChatType = "PARTY",
        Frame = MakeShadowedFrame("MLFrame"),
        LabelFS = MockRegion("MLLabel"),
        EditBox = MockRegion("MLEdit"),
    }
    YapperTable.Config.EditBox.MultilineShadowChannelColor = true
    YapperTable.Multiline._RefreshLabel(ml)
    check("ml: _lastChannelRGB stored",
        ml._lastChannelRGB and approxEq(ml._lastChannelRGB.r, PARTY_RGB.r))
    local t = ml.Frame._yapperShadows
    check("ml: shadow tinted to channel colour",
        approxEq(t[1]._r, PARTY_RGB.r) and approxEq(t[1]._g, PARTY_RGB.g)
        and approxEq(t[1]._b, PARTY_RGB.b))

    local ml2 = {
        ChatType = "PARTY",
        Frame = MakeShadowedFrame("MLFrame2"),
        LabelFS = MockRegion("MLLabel2"),
        EditBox = MockRegion("MLEdit2"),
    }
    YapperTable.Config.EditBox.MultilineShadowChannelColor = false
    YapperTable.Multiline._RefreshLabel(ml2)
    check("ml flag off: textures untouched", ml2.Frame._yapperShadows[1]._r == nil)
    YapperTable.Config.EditBox.MultilineShadowChannelColor = true
end

-- ===========================================================================
print(("Results: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then os.exit(1) end
