#!/usr/bin/env python3
"""
Split EditBox.lua into sub-files.
Run from repo root: python3 tools/split_editbox.py
"""
import os

SRC = "Src/EditBox.lua.bak"
OUT_DIR = "Src/EditBox"
OUT_HUB = "Src/EditBox.lua"

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
    # Hub (EditBox.lua): module + state + constants + parsing helpers +
    #   utility functions + public API
    # Lines: 1-310 (header through SetFrameFillColour)
    #        + 2903-2911 (SetOnSend, SetPreShowCheck)
    # -----------------------------------------------------------------------
    hub_content = extract(lines, 1, 310)

    # Export shared locals for sub-files.
    hub_content += '''
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
'''
    # Public API at end of file
    hub_content += "\n"
    hub_content += extract(lines, 2903, 2911)
    write_file(OUT_HUB, hub_content)

    # -----------------------------------------------------------------------
    # SkinProxy.lua: Blizzard skin cloning
    # Lines: 313-525
    # -----------------------------------------------------------------------
    skinproxy_header = '''\
--[[
    EditBox/SkinProxy.lua
    Clone Blizzard's editbox textures onto the overlay so the user sees
    their theme skin. Supports live tinting and detachment.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local math_max   = math.max
local math_min   = math.min
local math_abs   = math.abs

'''
    skinproxy_body = extract(lines, 313, 525)
    write_file(os.path.join(OUT_DIR, "SkinProxy.lua"), skinproxy_header + skinproxy_body)

    # -----------------------------------------------------------------------
    # Overlay.lua: visual refresh, channel name resolution, label helpers,
    #   CreateOverlay
    # Lines: 526-974
    # -----------------------------------------------------------------------
    overlay_header = '''\
--[[
    EditBox/Overlay.lua
    Overlay visual refresh (fills, text colors, borders, shadows),
    channel name resolution, label sizing/font fitting, and the main
    CreateOverlay function that builds the overlay frame hierarchy.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SetFrameFillColour = EditBox.SetFrameFillColour
local LABEL_PREFIXES     = EditBox._LABEL_PREFIXES

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local tostring   = tostring
local tonumber   = tonumber
local math_max   = math.max
local math_min   = math.min
local math_floor = math.floor
local strmatch   = string.match
local strlower   = string.lower
local table_insert = table.insert

'''
    overlay_body = extract(lines, 526, 974)
    # Export locals that Hooks.lua needs at runtime.
    overlay_body += '''
-- Export visual/label locals for Hooks.lua & Handlers.lua.
EditBox._RefreshOverlayVisuals     = RefreshOverlayVisuals
EditBox._ResolveChannelName        = ResolveChannelName
EditBox._BuildLabelText            = BuildLabelText
EditBox._GetLabelUsableWidth       = GetLabelUsableWidth
EditBox._ResetLabelToBaseFont      = ResetLabelToBaseFont
EditBox._TruncateLabelToWidth      = TruncateLabelToWidth
EditBox._FitLabelFontToWidth       = FitLabelFontToWidth
EditBox._UpdateLabelBackgroundForText = UpdateLabelBackgroundForText
'''
    write_file(os.path.join(OUT_DIR, "Overlay.lua"), overlay_header + overlay_body)

    # -----------------------------------------------------------------------
    # Handlers.lua: SetupOverlayScripts + ResetLockdownIdleTimer
    # Lines: 975-1641
    # -----------------------------------------------------------------------
    handlers_header = '''\
--[[
    EditBox/Handlers.lua
    All overlay script handlers (OnTextChanged, OnEnterPressed,
    OnEscapePressed, OnKeyDown, OnHide, OnEditFocusLost/Gained),
    event registration, lockdown detection, and idle timer management.
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SLASH_MAP            = EditBox._SLASH_MAP
local TAB_CYCLE            = EditBox._TAB_CYCLE
local GROUP_CHAT_TYPES     = EditBox._GROUP_CHAT_TYPES
local IsWhisperSlashPrefill = EditBox.IsWhisperSlashPrefill
local ParseWhisperSlash    = EditBox.ParseWhisperSlash
local GetLastTellTargetInfo = EditBox.GetLastTellTargetInfo

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local tostring   = tostring
local tonumber   = tonumber
local strmatch   = string.match
local strlower   = string.lower
local strbyte    = string.byte

'''
    handlers_body = extract(lines, 975, 1641)
    write_file(os.path.join(OUT_DIR, "Handlers.lua"), handlers_header + handlers_body)

    # -----------------------------------------------------------------------
    # Hooks.lua: Show, Hide, HandoffToBlizzard, ApplyConfigToLiveOverlay,
    #   RefreshLabel, PersistLastUsed, CycleChat, IsChatTypeAvailable,
    #   GetResolvedChatType, NavigateHistory, ForwardSlashCommand,
    #   HookBlizzardEditBox, HookAllChatFrames
    # Lines: 1642-2902
    # -----------------------------------------------------------------------
    hooks_header = '''\
--[[
    EditBox/Hooks.lua
    Show/Hide lifecycle, Blizzard handoff, live config application,
    label refresh, channel cycling, history navigation, slash forwarding,
    and the Blizzard editbox hook integration (HookBlizzardEditBox,
    HookAllChatFrames).
]]

local _, YapperTable = ...
local EditBox        = YapperTable.EditBox

-- Re-localise shared helpers from hub.
local SLASH_MAP                = EditBox._SLASH_MAP
local TAB_CYCLE                = EditBox._TAB_CYCLE
local LABEL_PREFIXES           = EditBox._LABEL_PREFIXES
local GROUP_CHAT_TYPES         = EditBox._GROUP_CHAT_TYPES
local CHATTYPE_TO_OVERRIDE_KEY = EditBox._CHATTYPE_TO_OVERRIDE_KEY
local IsWhisperSlashPrefill    = EditBox.IsWhisperSlashPrefill
local ParseWhisperSlash        = EditBox.ParseWhisperSlash
local GetLastTellTargetInfo    = EditBox.GetLastTellTargetInfo
local IsWIMFocusActive         = EditBox.IsWIMFocusActive
local SetFrameFillColour       = EditBox.SetFrameFillColour

-- Lazy-resolved locals from Overlay.lua (loaded before us).
local RefreshOverlayVisuals
local ResolveChannelName
local BuildLabelText
local GetLabelUsableWidth
local ResetLabelToBaseFont
local TruncateLabelToWidth
local FitLabelFontToWidth
local UpdateLabelBackgroundForText

local function ResolveOverlayLocals()
    if not RefreshOverlayVisuals then
        RefreshOverlayVisuals     = EditBox._RefreshOverlayVisuals
        ResolveChannelName        = EditBox._ResolveChannelName
        BuildLabelText            = EditBox._BuildLabelText
        GetLabelUsableWidth       = EditBox._GetLabelUsableWidth
        ResetLabelToBaseFont      = EditBox._ResetLabelToBaseFont
        TruncateLabelToWidth      = EditBox._TruncateLabelToWidth
        FitLabelFontToWidth       = EditBox._FitLabelFontToWidth
        UpdateLabelBackgroundForText = EditBox._UpdateLabelBackgroundForText
    end
end

-- Closure accessors for mutable hub-scoped locals.
local function UserBypassingYapper() return EditBox._UserBypassingYapper() end
local function SetUserBypassingYapper(v) EditBox._SetUserBypassingYapper(v) end
local function BypassEditBox() return EditBox._BypassEditBox() end
local function SetBypassEditBox(v) EditBox._SetBypassEditBox(v) end

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_max   = math.max
local math_min   = math.min
local math_abs   = math.abs
local math_floor = math.floor
local strmatch   = string.match
local strlower   = string.lower

'''
    hooks_body = extract(lines, 1642, 2902)
    write_file(os.path.join(OUT_DIR, "Hooks.lua"), hooks_header + hooks_body)

    print("\nDone! Verify with: wc -l Src/EditBox.lua Src/EditBox/*.lua")

if __name__ == "__main__":
    main()
