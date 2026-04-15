#!/usr/bin/env python3
"""
Split Interface.lua into sub-files.
Run from repo root: python3 tools/split_interface.py
"""
import os

SRC = "Src/Interface.lua.bak"
OUT_DIR = "Src/Interface"
OUT_HUB = "Src/Interface.lua"

def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.readlines()

def write_file(path, content):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  wrote {path} ({content.count(chr(10))} lines)")

def extract(lines, start, end_):
    """Extract lines[start-1:end_] (1-indexed inclusive)."""
    return "".join(lines[start - 1 : end_])

def main():
    lines = read_lines(SRC)
    print(f"Read {len(lines)} lines from {SRC}")

    # -----------------------------------------------------------------------
    # Schema.lua: metadata tables (141-441) + schema builder (999-1163)
    # -----------------------------------------------------------------------
    schema_header = '''\
--[[
    Interface/Schema.lua
    Configuration metadata tables (categories, tooltips, labels) and the
    schema builder that drives the dynamic settings renderer.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath       = Interface.JoinPath
local ClonePath      = Interface.ClonePath
local IsColourTable  = Interface.IsColourTable

'''
    schema_body = extract(lines, 141, 441)
    schema_body += "\n"
    schema_body += extract(lines, 999, 1163)

    # Export tables so other sub-files can access them.
    schema_exports = '''
-- Export metadata for other sub-files.
Interface._COLOUR_KEYS                = COLOUR_KEYS
Interface._CHANNEL_OVERRIDE_OPTIONS   = CHANNEL_OVERRIDE_OPTIONS
Interface._CREDITS_BUNDLED            = CREDITS_DICTIONARIES_BUNDLED
Interface._CREDITS_OPTIONAL           = CREDITS_DICTIONARIES_OPTIONAL
Interface._FONT_OUTLINE_OPTIONS       = FONT_OUTLINE_OPTIONS
Interface._SETTING_TOOLTIPS           = SETTING_TOOLTIPS
Interface._FRIENDLY_LABELS            = FRIENDLY_LABELS
Interface._CATEGORIES                 = CATEGORIES
Interface._PATH_TO_CATEGORY           = PATH_TO_CATEGORY
'''
    write_file(os.path.join(OUT_DIR, "Schema.lua"),
               schema_header + schema_body + schema_exports)

    # -----------------------------------------------------------------------
    # Config.lua: config access (676-997)
    # -----------------------------------------------------------------------
    config_header = '''\
--[[
    Interface/Config.lua
    Configuration getters/setters, minimap button helpers, theme override
    checks, and config sanitisation.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath              = Interface.JoinPath
local GetPathValue          = Interface.GetPathValue
local SetPathValue          = Interface.SetPathValue
local NormalizeChatMarkers  = Interface.NormalizeChatMarkers
local Clamp01               = Interface.Clamp01
local TrimString            = Interface.TrimString
local PruneUnknown          = Interface.PruneUnknown
local IsAnchorPoint         = Interface.IsAnchorPoint
local IsColourTable         = Interface.IsColourTable
local CopyColour            = Interface.CopyColour
local COLOUR_KEYS           = Interface._COLOUR_KEYS
local FRIENDLY_LABELS       = Interface._FRIENDLY_LABELS
local SETTING_TOOLTIPS      = Interface._SETTING_TOOLTIPS

-- Re-localise Lua globals.
local type     = type
local tonumber = tonumber
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_deg = math.deg
local math_atan2 = math.atan2 or math.atan

'''
    config_body = extract(lines, 676, 997)
    write_file(os.path.join(OUT_DIR, "Config.lua"), config_header + config_body)

    # -----------------------------------------------------------------------
    # Window.lua: position + scrolling + welcome + main window + sidebar + font scaling
    # -----------------------------------------------------------------------
    window_header = '''\
--[[
    Interface/Window.lua
    Main settings window creation, scrollable content area, scrollbar,
    welcome choice frame, sidebar, font scaling, and position persistence.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local IsAnchorPoint  = Interface.IsAnchorPoint
local LAYOUT         = Interface._LAYOUT
local CATEGORIES     = Interface._CATEGORIES
local LayoutCursor   = Interface._LayoutCursor

-- Re-localise Lua globals.
local type       = type
local ipairs     = ipairs
local math_abs   = math.abs
local math_floor = math.floor
local math_max   = math.max
local tinsert    = table.insert
local tostring   = tostring

-- Even-increment offsets (re-exported from hub for local use).
local UI_FONT_STEP       = Interface._UI_FONT_STEP
local UI_FONT_MIN_OFFSET = Interface._UI_FONT_MIN_OFFSET
local UI_FONT_MAX_OFFSET = Interface._UI_FONT_MAX_OFFSET

'''
    window_body = extract(lines, 1165, 1731)
    write_file(os.path.join(OUT_DIR, "Window.lua"), window_header + window_body)

    # -----------------------------------------------------------------------
    # Widgets.lua: pool + tooltips + basic creators + OpenColorPicker
    # Lines: 1737-2225 (pool+tooltips+reset+label+OpenColorPicker+checkbox)
    # + 2963-3284 (CreateTextInput, CreateColorPickerControl, CreateFontSizeDropdown, CreateFontOutlineDropdown)
    # -----------------------------------------------------------------------
    widgets_header = '''\
--[[
    Interface/Widgets.lua
    Widget pool management, tooltip helpers, and reusable widget creators
    (checkbox, text input, color picker, font size, font outline, reset
    button, label).
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath          = Interface.JoinPath
local IsColourTable     = Interface.IsColourTable
local CopyColour        = Interface.CopyColour
local Clamp01           = Interface.Clamp01
local TrimString        = Interface.TrimString
local RoundToEven       = Interface.RoundToEven
local NormalizeFontFlags = Interface.NormalizeFontFlags
local GetFontFlagsLabel = Interface.GetFontFlagsLabel
local LAYOUT            = Interface._LAYOUT
local COLOUR_KEYS       = Interface._COLOUR_KEYS
local SETTING_TOOLTIPS  = Interface._SETTING_TOOLTIPS
local FONT_OUTLINE_OPTIONS = Interface._FONT_OUTLINE_OPTIONS

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_floor = math.floor
local math_min   = math.min

'''
    widgets_body = extract(lines, 1737, 2225)
    widgets_body += "\n"
    widgets_body += extract(lines, 2963, 3284)

    # Export OpenColorPicker so Pages.lua can use it.
    widgets_export = '''
-- Export OpenColorPicker for Pages.lua.
Interface._OpenColorPicker = OpenColorPicker
'''
    write_file(os.path.join(OUT_DIR, "Widgets.lua"),
               widgets_header + widgets_body + widgets_export)

    # -----------------------------------------------------------------------
    # Pages.lua: complex custom pages
    # Lines: 2227-2961 (ChannelOverrides, FormatRelativeTime, YALLM, QueueDiag, Credits)
    # + 3286-3687 (spellcheck dropdowns, user dict, theme dropdown)
    # -----------------------------------------------------------------------
    pages_header = '''\
--[[
    Interface/Pages.lua
    Complex custom control pages: channel colour overrides, YALLM learning
    summary, queue diagnostics, credits, spellcheck dropdowns, user
    dictionary editor, and theme selector.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath                    = Interface.JoinPath
local IsColourTable               = Interface.IsColourTable
local CopyColour                  = Interface.CopyColour
local Clamp01                     = Interface.Clamp01
local LAYOUT                      = Interface._LAYOUT
local COLOUR_KEYS                 = Interface._COLOUR_KEYS
local CHANNEL_OVERRIDE_OPTIONS    = Interface._CHANNEL_OVERRIDE_OPTIONS
local CREDITS_DICTIONARIES_BUNDLED  = Interface._CREDITS_BUNDLED
local CREDITS_DICTIONARIES_OPTIONAL = Interface._CREDITS_OPTIONAL
local FRIENDLY_LABELS             = Interface._FRIENDLY_LABELS
local SETTING_TOOLTIPS            = Interface._SETTING_TOOLTIPS

-- Grab OpenColorPicker from Widgets (loaded before us).
local function GetOpenColorPicker()
    return Interface._OpenColorPicker
end

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_abs   = math.abs
local math_floor = math.floor
local table_sort = table.sort
local string_format = string.format

'''
    pages_body = extract(lines, 2227, 2961)
    pages_body += "\n"
    pages_body += extract(lines, 3286, 3687)
    write_file(os.path.join(OUT_DIR, "Pages.lua"), pages_header + pages_body)

    # -----------------------------------------------------------------------
    # Hub (Interface.lua): header + popups + constants + utils + BuildConfigUI + lifecycle
    # Lines: 1-35, 37-138 (InitPopups), 443-670 (LAYOUT+LayoutCursor+utils),
    #        3689-4176 (BuildConfigUI+lifecycle)
    # -----------------------------------------------------------------------
    hub_content = extract(lines, 1, 35)

    # Export utility functions on Interface table BEFORE InitPopups
    # so sub-files loaded after the hub can grab them.
    hub_content += '''
'''
    hub_content += extract(lines, 434, 511)
    hub_content += '''
-- Export layout and cursor for sub-files.
Interface._LAYOUT           = LAYOUT
Interface._LayoutCursor     = LayoutCursor
Interface._UI_FONT_STEP     = UI_FONT_STEP
Interface._UI_FONT_MIN_OFFSET = UI_FONT_MIN_OFFSET
Interface._UI_FONT_MAX_OFFSET = UI_FONT_MAX_OFFSET

-- ---------------------------------------------------------------------------
-- Utility helpers (exported on Interface for sub-files to re-localise)
-- ---------------------------------------------------------------------------
'''
    hub_content += extract(lines, 514, 670)

    # Now export each utility function on the Interface table.
    hub_content += '''
-- Export utilities for sub-files.
Interface.IsColourTable       = IsColourTable
Interface.CopyColour          = CopyColour
Interface.JoinPath            = JoinPath
Interface.ClonePath           = ClonePath
Interface.TrimString          = TrimString
Interface.Clamp01             = Clamp01
Interface.RoundToEven         = RoundToEven
Interface.NormalizeFontFlags  = NormalizeFontFlags
Interface.GetFontFlagsLabel   = GetFontFlagsLabel
Interface.GetPathValue        = GetPathValue
Interface.SetPathValue        = SetPathValue
Interface.NormalizeChatMarkers = NormalizeChatMarkers
Interface.PruneUnknown        = PruneUnknown
Interface.IsAnchorPoint       = IsAnchorPoint

'''

    # InitPopups
    hub_content += "-- ---------------------------------------------------------------------------\n"
    hub_content += "-- StaticPopups\n"
    hub_content += "-- ---------------------------------------------------------------------------\n"
    hub_content += extract(lines, 37, 138)
    hub_content += "\n"

    # BuildConfigUI + lifecycle + launcher
    hub_content += "-- ---------------------------------------------------------------------------\n"
    hub_content += "-- BuildConfigUI — master renderer\n"
    hub_content += "-- ---------------------------------------------------------------------------\n"
    hub_content += extract(lines, 3689, 4176)

    write_file(OUT_HUB, hub_content)

    print("\nDone! Verify with: wc -l Src/Interface.lua Src/Interface/*.lua")

if __name__ == "__main__":
    main()
