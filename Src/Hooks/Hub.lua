--[[
    Hooks/Hub.lua
    Shared locals for all EditBox hook modules.
    Exported via YapperTable.EditBoxHooksCore for submodules to import.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State

-- Export shared references for submodules
YapperTable.EditBoxHooksCore = {
    -- Core references
    YapperTable = YapperTable,
    EditBox = EditBox,
    State = State,

    -- Constants from EditBox
    SLASH_MAP = EditBox._SLASH_MAP,
    TAB_CYCLE = EditBox._TAB_CYCLE,
    LABEL_PREFIXES = EditBox._LABEL_PREFIXES,
    GROUP_CHAT_TYPES = EditBox._GROUP_CHAT_TYPES,
    CHATTYPE_TO_OVERRIDE_KEY = EditBox._CHATTYPE_TO_OVERRIDE_KEY,

    -- Helper functions from EditBox
    IsWhisperSlashPrefill = EditBox.IsWhisperSlashPrefill,
    ParseWhisperSlash = EditBox.ParseWhisperSlash,
    GetLastTellTargetInfo = EditBox.GetLastTellTargetInfo,
    GetLastToldTargetInfo = EditBox.GetLastToldTargetInfo,
    SetFrameFillColour = EditBox.SetFrameFillColour,

    -- Overlay helpers (set by Overlay.lua, loaded before us)
    RefreshOverlayVisuals = EditBox._RefreshOverlayVisuals,
    ResolveChannelName = EditBox._ResolveChannelName,
    BuildLabelText = EditBox._BuildLabelText,
    GetLabelUsableWidth = EditBox._GetLabelUsableWidth,
    ResetLabelToBaseFont = EditBox._ResetLabelToBaseFont,
    TruncateLabelToWidth = EditBox._TruncateLabelToWidth,
    FitLabelFontToWidth = EditBox._FitLabelFontToWidth,
    UpdateLabelBackgroundForText = EditBox._UpdateLabelBackgroundForText,

    -- Closure accessors for mutable hub-scoped locals
    UserBypassingYapper = function() return EditBox._UserBypassingYapper() end,
    SetUserBypassingYapper = function(v) EditBox._SetUserBypassingYapper(v) end,
    BypassEditBox = function() return EditBox._BypassEditBox() end,
    SetBypassEditBox = function(v) EditBox._SetBypassEditBox(v) end,
}
