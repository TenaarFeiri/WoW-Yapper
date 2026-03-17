--[[
    User interface for configuration options.
]]

local YapperName, YapperTable = ...
local Interface = {}
YapperTable.Interface = Interface
Interface.MouseWheelStepRate = YapperTable.Config.FrameSettings.MouseWheelStepRate or 30
Interface.IsVisible = false

-- Treat these paths as RGBA color pickers in the dynamic settings renderer.
local COLOR_KEYS = {
    InputBg = true,
    LabelBg = true,
    TextColor = true,
    BorderColor = true,
}

local CHANNEL_OVERRIDE_OPTIONS = {
    { key = "SAY",           label = "Say" },
    { key = "YELL",          label = "Yell" },
    { key = "PARTY",         label = "Party" },
    { key = "WHISPER",       label = "Whisper" },
    { key = "BN_WHISPER",    label = "BNet Whisper" },
    { key = "CHANNEL",       label = "Channel" },
    { key = "CLUB",          label = "Community" },
    { key = "INSTANCE_CHAT", label = "Instance" },
    { key = "RAID",          label = "Raid" },
    { key = "RAID_WARNING",  label = "Raid Warning" },
}

local CREDITS_DICTIONARIES_BUNDLED = {
    { locale = "enUS", label = "English (US)", package = "dictionary-en", license = "MIT AND BSD" },
    { locale = "enGB", label = "English (UK)", package = "dictionary-en-GB", license = "MIT AND BSD" },
}

local CREDITS_DICTIONARIES_OPTIONAL = {
    { locale = "frFR", label = "French", package = "dictionary-fr", license = "MPL-2.0" },
    { locale = "deDE", label = "German", package = "dictionary-de", license = "GPL-2.0 OR GPL-3.0" },
    { locale = "esES", label = "Spanish", package = "dictionary-es", license = "GPL-3.0 OR LGPL-3.0 OR MPL-1.1" },
    { locale = "esMX", label = "Spanish (Mexico)", package = "dictionary-es-MX", license = "GPL-3.0 OR LGPL-3.0 OR MPL-1.1" },
    { locale = "itIT", label = "Italian", package = "dictionary-it", license = "GPL-3.0" },
    { locale = "ptBR", label = "Portuguese (Brazil)", package = "dictionary-pt", license = "LGPL-3.0 OR MPL-2.0" },
    { locale = "ruRU", label = "Russian", package = "dictionary-ru", license = "BSD-3-Clause" },
}

-- Friendly dropdown values for font outline modes.
local FONT_OUTLINE_OPTIONS = {
    { value = "",             label = "Default (None)" },
    { value = "OUTLINE",      label = "Outline" },
    { value = "THICKOUTLINE", label = "Thick Outline" },
}

-- Tooltip copy keyed by setting path / synthetic header keys.
local SETTING_TOOLTIPS = {
    ["HEADER.AUTOSAVE"] = "Settings are automatically saved; go ahead and change them!",
    ["HEADER.VIEWMODE"] =
    "Basic should be all you need but if you want a little more technical customisation, you can change some chat mechanics in advanced.",
    ["SECTION.Chat"] = "Controls chat splitting and send behaviour.",
    ["SECTION.EditBox"] = "Customises your editbox appearance and behaviour.",
    ["SECTION.FrameSettings"] = "Controls window and scrolling behaviour.",
    ["FrameSettings.EnableMinimapButton"] = "Show or hide the minimap launcher button.",
    ["FrameSettings.MinimapButtonOffset"] =
    "Extra pixels away from the minimap center for the fallback minimap button.",
    ["Spellcheck.Enabled"] = "Underline and suggest replacements for misspelled words.",
    ["Spellcheck.Locale"] = "Select the dictionary locale to use for spellchecking.",
    ["Spellcheck.UnderlineStyle"] = "Choose between straight underline or highlight style.",
    ["Spellcheck.MinWordLength"] = "Ignore words shorter than this length.",
    ["Spellcheck.MaxSuggestions"] = "Maximum number of suggestions shown (1-4).",
    ["Chat.USE_DELINEATORS"] = "Add marker text between split chunks.",
    ["Chat.DELINEATOR"] = "Single marker token used for both suffix and prefix; spacing is auto-managed.",
    ["Chat.MAX_HISTORY_LINES"] = "How many previous messages are kept in local history.",
    ["EditBox.InputBg"] = "Background colour of the input area.",
    ["EditBox.LabelBg"] = "Background colour of the channel label area.",
    ["EditBox.FontFace"] = "Custom font file path. Leave empty to use default font.",
    ["EditBox.FontFlags"] = "Choose whether text has an outline effect.",
    ["EditBox.FontSize"] = "The editbox will automatically expand to fit your selected font size.",
    ["EditBox.AutoFitLabel"] =
    "If enabled, label text shrinks to fit. If disabled, long labels are truncated with ellipsis.",
    ["EditBox.StickyChannel"] =
    "When enabled, the overlay remembers the last channel you used and reopens with it selected.",
    ["EditBox.StickyGroupChannel"] =
    "When 'Remember last channel' is off, group channels (Party, Instance, Raid, Raid Warning) still remain sticky. Uncheck to disable that too.",
    ["EditBox.RecoverOnEscape"] =
    "When enabled, ESC keeps your text as a draft. When disabled, ESC saves to history but discards drafts.",
    ["EditBox.MinHeight"] =
    "Sets a minimum height for the chat input box. Only takes effect if larger than the game's native editbox height.",
    ["EditBox.UseBlizzardSkinProxy"] =
    "When enabled, Yapper temporarily snaps Blizzard's editbox backdrop/skin frame around the overlay so external chat-skin addons can style it.",
    ["EditBox.BlizzardSkinProxyPad"] =
    "Extra padding (in pixels) around the borrowed Blizzard skin frame when wrapped around Yapper's overlay.",
    ["CHANNEL.HEADER"] =
    "Change the colours for your chat channels here, and optionally set a master override to adhere to!",
    ["CHANNEL.MASTER"] = "One selected channel can act as a colour source.",
    ["CHANNEL.OVERRIDE"] = "When checked, this channel uses the selected master channel's colour.",
    ["CHANNEL.RESET_ALL"] = "Restore all channel colours to defaults.",
    ["System.DEBUG"] = "Enables debug output. Warning: this is very spammy!",
    ["System.VERBOSE"] = "Yapper will announce when it does something unusual — a less spammy alternative to Debug.",
    ["System.RUN_ALL_PATCHES"] =
    "Placeholder for a future patching framework that will let other addons integrate more easily with Yapper. Currently does nothing.",
    ["System.EnableGopherBridge"] =
    "Toggle integration with Gopher (CrossRP compatibility). |cFFFF4444Disabling this WHILE using a Gopher-powered addon like CrossRP is a BAD idea and will cause stalls and chat problems.|r",
    ["System.EnableTypingTrackerBridge"] =
    "Toggle integration with Simply_RP_Typing_Tracker. Disabling this stops typing indicators from being sent.",
}

-- UI-only aliases to not scare the normies.
local FRIENDLY_LABELS = {
    ["SECTION.Chat"] = "Message Sending",
    ["SECTION.EditBox"] = "Chat Input Appearance",
    ["SECTION.FrameSettings"] = "Window & Scrolling",
    ["FrameSettings.EnableMinimapButton"] = "Show minimap button",
    ["FrameSettings.MinimapButtonOffset"] = "Minimap button offset",
    ["Spellcheck.Enabled"] = "Enable spellcheck",
    ["Spellcheck.Locale"] = "Spellcheck locale",
    ["Spellcheck.UnderlineStyle"] = "Underline style",
    ["Spellcheck.MinWordLength"] = "Minimum word length",
    ["Spellcheck.MaxSuggestions"] = "Max suggestions",
    ["System.EnableGopherBridge"] = "Enable Gopher Bridge",
    ["System.EnableTypingTrackerBridge"] = "Enable Typing Tracker Bridge",

    ["Chat.USE_DELINEATORS"] = "Add split marker",
    ["Chat.DELINEATOR"] = "Split marker text",
    ["Chat.MAX_HISTORY_LINES"] = "Saved message history",

    ["EditBox.InputBg"] = "Input background colour",
    ["EditBox.LabelBg"] = "Label background colour",
    ["EditBox.FontFace"] = "Font file path",
    ["EditBox.FontFlags"] = "Font outline mode",
    ["EditBox.FontSize"] = "Font size",
    ["EditBox.AutoFitLabel"] = "Auto-fit long labels",
    ["EditBox.StickyChannel"] = "Remember last channel",
    ["EditBox.StickyGroupChannel"] = "Keep group channels sticky",
    ["EditBox.RecoverOnEscape"] = "Recover text after ESC",
    ["EditBox.MinHeight"] = "Minimum input height",
    ["EditBox.UseBlizzardSkinProxy"] = "Use Blizzard skin proxy",
    ["EditBox.BlizzardSkinProxyPad"] = "Skin proxy padding",
}

-- ---------------------------------------------------------------------------
-- Category system -- each entry defines a sidebar tab and the settings it owns.
-- Settings are referenced by their JoinPath() key (e.g. "EditBox.FontSize").
-- A nil/empty `paths` list means "render nothing from the schema" (the page
-- builder can still emit custom controls).
-- ---------------------------------------------------------------------------
local CATEGORIES = {
    {
        id    = "general",
        label = "General",
        icon  = nil,  -- reserved for future icon support
        paths = {
            -- Minimap button
            "FrameSettings.EnableMinimapButton",
            "FrameSettings.MinimapButtonOffset",
            -- Spellcheck
            "Spellcheck.Enabled",
            "Spellcheck.Locale",
            "Spellcheck.UnderlineStyle",
            -- Sticky channel behaviour
            "EditBox.StickyChannel",
            "EditBox.StickyGroupChannel",
            "EditBox.RecoverOnEscape",
            -- Label fitting
            "EditBox.AutoFitLabel",
            -- Blizzard skin proxy
            "EditBox.UseBlizzardSkinProxy",
            -- Chat split marker
            "Chat.USE_DELINEATORS",
            "Chat.DELINEATOR",
        },
    },
    {
        id    = "appearance",
        label = "Appearance",
        icon  = nil,
        paths = {
            -- Theme
            "System.ActiveTheme",
            -- Colours
            "EditBox.InputBg",
            "EditBox.LabelBg",
            -- Font
            "EditBox.FontSize",
            "EditBox.FontFlags",
        },
        -- Channel override controls and border colour (conditional) are
        -- appended by custom logic inside the page builder.
        custom = { "channelOverrides", "borderColor" },
    },
    {
        id    = "advanced",
        label = "Advanced",
        icon  = nil,
        paths = {
            -- System
            "System.DEBUG",
            "System.VERBOSE",
            "System.RUN_ALL_PATCHES",
            -- Chat mechanics
            "Chat.MAX_HISTORY_LINES",
            -- EditBox advanced
            "EditBox.FontFace",
            "EditBox.MinHeight",
            "EditBox.BlizzardSkinProxyPad",
            -- Spellcheck advanced
            "Spellcheck.MinWordLength",
            "Spellcheck.MaxSuggestions",
        },
        -- Bridges are appended by custom logic.
        custom = { "bridges" },
    },
    {
        id    = "diagnostics",
        label = "Diagnostics",
        icon  = nil,
        paths = {},
        custom = { "queueDiagnostics" },
    },
    {
        id    = "credits",
        label = "Credits",
        icon  = nil,
        paths = {},
        custom = { "credits" },
    },
}

-- Quick lookup: path -> category id.
local PATH_TO_CATEGORY = {}
for _, cat in ipairs(CATEGORIES) do
    if cat.paths then
        for _, p in ipairs(cat.paths) do
            PATH_TO_CATEGORY[p] = cat.id
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------
local LAYOUT = {
    -- Main window
    WINDOW_WIDTH           = 740,
    WINDOW_HEIGHT          = 640,
    WINDOW_PADDING         = 8,
    SCROLLBAR_WIDTH        = 14,
    SCROLLBAR_GAP          = 2,
    TITLE_INSET            = 28,
    BOTTOM_BAR             = 36,

    -- Sidebar
    SIDEBAR_WIDTH          = 150,
    SIDEBAR_BTN_HEIGHT     = 28,
    SIDEBAR_BTN_PAD        = 2,
    SIDEBAR_TOP_INSET      = 32,

    -- Widget row heights (generous spacing for readability)
    ROW_CHECKBOX           = 36,
    ROW_TEXT_INPUT         = 36,
    ROW_COLOR_PICKER       = 36,
    ROW_FONT_OUTLINE       = 36,
    ROW_FONT_SIZE          = 90,
    ROW_SECTION            = 28,
    ROW_CHANNEL_ROW        = 28,
    ROW_CHANNEL_HEADER     = 24,
    ROW_CHANNEL_LABELS     = 18,

    -- Starting Y for dynamic content (pushed below the autosave notice)
    CONTENT_START_Y        = -28,

    -- Horizontal positions (wider labels to avoid word-wrap in 740px window)
    LABEL_X                = 10,
    LABEL_WIDTH            = 300,
    CONTROL_X              = 320,
    RESET_X                = 500,

    -- Close button
    CLOSE_BTN_WIDTH        = 120,
    CLOSE_BTN_HEIGHT       = 24,
    CLOSE_BTN_OFFSET_Y     = 10,

    -- Scrollbar fixed offsets
    SCROLLBAR_TOP_INSET    = 48,
    SCROLLBAR_BOTTOM_INSET = 44,
}

-- Even-increment offsets from the Blizzard base size (used by sidebar +/–).
local UI_FONT_STEP       = 2
local UI_FONT_MIN_OFFSET = -4   -- smallest allowed offset (8 pt at base 12)
local UI_FONT_MAX_OFFSET = 8    -- largest  allowed offset (20 pt at base 12)

-- ---------------------------------------------------------------------------
-- LayoutCursor... replaces manual `y = y - N` tracking.
-- ---------------------------------------------------------------------------
local LayoutCursor = {}
LayoutCursor.__index = LayoutCursor

---@param startY number?
---@return table
function LayoutCursor.New(startY)
    return setmetatable({ _y = startY or 0 }, LayoutCursor)
end

function LayoutCursor:Y()
    return self._y
end

function LayoutCursor:Advance(amount)
    self._y = self._y - (amount or 0)
    return self._y
end

function LayoutCursor:Pad(px)
    return self:Advance(px or 4)
end

-- Basic RGB(A) shape check for config colour tables.
local function IsColorTable(tbl)
    return type(tbl) == "table"
        and type(tbl.r) == "number"
        and type(tbl.g) == "number"
        and type(tbl.b) == "number"
end

-- Copy a colour table safely, supplying sane defaults.
local function CopyColor(tbl)
    return {
        r = tbl.r or 1,
        g = tbl.g or 1,
        b = tbl.b or 1,
        a = tbl.a ~= nil and tbl.a or 1,
    }
end

-- Convert a path array into "A.B.C" form for lookup keys.
local function JoinPath(path)
    return table.concat(path, ".")
end

-- Copy a path array so render walkers can mutate independently.
local function ClonePath(path)
    local out = {}
    for i = 1, #path do out[i] = path[i] end
    return out
end

-- Trim user text input for normalization workflows.
local function TrimString(s)
    s = tostring(s or "")
    return (s:match("^%s*(.-)%s*$") or "")
end

-- Clamp numbers into [0,1], with a fallback when value is invalid.
local function Clamp01(value, fallback)
    if type(value) ~= "number" then
        return fallback
    end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- Force font size to valid even values in our supported range.
local function RoundToEven(value)
    value = tonumber(value) or 14
    value = math.floor(value + 0.5)
    if value % 2 ~= 0 then
        value = value + 1
    end
    if value < 8 then value = 8 end
    if value > 64 then value = 64 end
    return value
end

-- Normalise legacy/variant font flag values into known dropdown options.
local function NormalizeFontFlags(value)
    if type(value) ~= "string" then return "" end
    local flags = string.upper(TrimString(value))
    if flags == "" or flags == "NONE" then
        return ""
    end

    for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
        if option.value == flags then
            return option.value
        end
    end

    return ""
end

-- Resolve a font flag value to display text.
local function GetFontFlagsLabel(flags)
    for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
        if option.value == flags then
            return option.label
        end
    end
    return FONT_OUTLINE_OPTIONS[1].label
end

-- Traverse nested tables using a key path.
local function GetPathValue(root, path)
    local cursor = root
    for i = 1, #path do
        if type(cursor) ~= "table" then return nil end
        cursor = cursor[path[i]]
    end
    return cursor
end

-- Write into nested tables, creating missing parents as needed.
local function SetPathValue(root, path, value)
    if type(root) ~= "table" then return end
    local cursor = root
    for i = 1, #path - 1 do
        local key = path[i]
        if type(cursor[key]) ~= "table" then
            cursor[key] = {}
        end
        cursor = cursor[key]
    end
    cursor[path[#path]] = value
end

-- Keep split marker settings visually consistent while user edits either side.
local function NormalizeChatMarkers(path, value)
    if #path ~= 2 or path[1] ~= "Chat" or type(value) ~= "string" then
        return value
    end

    local trimmed = TrimString(value)
    if trimmed == "" then
        -- Empty marker means: no delineator / no prefix.
        return ""
    end

    if path[2] == "DELINEATOR" then
        return " " .. trimmed
    elseif path[2] == "PREFIX" then
        return trimmed .. " "
    end

    return value
end

-- Remove local keys that no longer exist in defaults.
local function PruneUnknown(localTbl, defaultTbl)
    if type(localTbl) ~= "table" or type(defaultTbl) ~= "table" then return end

    for key, value in pairs(localTbl) do
        local defValue = defaultTbl[key]
        if defValue == nil then
            localTbl[key] = nil
        elseif type(value) == "table" and type(defValue) == "table" then
            PruneUnknown(value, defValue)
        elseif type(value) == "table" and type(defValue) ~= "table" then
            localTbl[key] = nil
        end
    end
end

-- Restrict restored frame anchors to known safe point names.
local function IsAnchorPoint(value)
    return value == "TOP"
        or value == "BOTTOM"
        or value == "LEFT"
        or value == "RIGHT"
        or value == "CENTER"
        or value == "TOPLEFT"
        or value == "TOPRIGHT"
        or value == "BOTTOMLEFT"
        or value == "BOTTOMRIGHT"
end

-- ---------------------------------------------------------------------------
-- Config access / cache
-- ---------------------------------------------------------------------------

function Interface:GetLocalConfigRoot()
    if type(_G.YapperLocalConf) ~= "table" then
        _G.YapperLocalConf = {}
    end
    return _G.YapperLocalConf
end

function Interface:GetDefaultsRoot()
    if YapperTable.Core and YapperTable.Core.GetDefaults then
        return YapperTable.Core:GetDefaults()
    end
    return nil
end

function Interface:GetRenderCacheContainer()
    if type(_G.YapperDB) ~= "table" then
        _G.YapperDB = {}
    end
    if type(_G.YapperDB.InterfaceUI) ~= "table" then
        _G.YapperDB.InterfaceUI = {}
    end
    return _G.YapperDB.InterfaceUI
end

-- Drop cached schema so it rebuilds from current defaults/local values.
function Interface:PurgeRenderCache()
    local cache = self:GetRenderCacheContainer()
    cache.schema = nil
    cache.dirty = false
end

function Interface:SetDirty(flag)
    local cache = self:GetRenderCacheContainer()
    cache.dirty = (flag == true)
end

function Interface:IsDirty()
    local cache = self:GetRenderCacheContainer()
    return cache.dirty == true
end

function Interface:SetSettingsChanged(flag)
    local root = self:GetLocalConfigRoot()
    if type(root.System) ~= "table" then
        root.System = {}
    end
    root.System.SettingsHaveChanged = (flag == true)
end

function Interface:GetConfigPath(path)
    local localVal = GetPathValue(self:GetLocalConfigRoot(), path)
    if localVal ~= nil then
        return localVal
    end
    return GetPathValue(YapperTable.Config, path)
end

function Interface:GetDefaultPath(path)
    return GetPathValue(self:GetDefaultsRoot(), path)
end

function Interface:UpdateOverrideTextColorCheckboxState()
    return
end

function Interface:SetLocalPath(path, value)
    local normalizedValue = NormalizeChatMarkers(path, value)

    if type(normalizedValue) == "table"
        and #path >= 2
        and path[1] == "EditBox"
        and COLOR_KEYS[path[2]] then
        normalizedValue = {
            r = Clamp01(normalizedValue.r, 1),
            g = Clamp01(normalizedValue.g, 1),
            b = Clamp01(normalizedValue.b, 1),
            a = Clamp01(normalizedValue.a, 1),
        }
    end

    local root = self:GetLocalConfigRoot()
    local syncedChatDelineator = nil
    local syncedChatPrefix = nil

    if #path == 2 and path[1] == "Chat"
        and (path[2] == "DELINEATOR" or path[2] == "PREFIX")
        and type(normalizedValue) == "string" then
        local marker = TrimString(normalizedValue)
        if marker == "" then
            syncedChatDelineator = ""
            syncedChatPrefix = ""
        else
            syncedChatDelineator = " " .. marker
            syncedChatPrefix = marker .. " "
        end

        if path[2] == "DELINEATOR" then
            normalizedValue = syncedChatDelineator
        else
            normalizedValue = syncedChatPrefix
        end

        SetPathValue(root, { "Chat", "DELINEATOR" }, syncedChatDelineator)
        SetPathValue(root, { "Chat", "PREFIX" }, syncedChatPrefix)
    else
        SetPathValue(root, path, normalizedValue)
    end

    -- If the user is explicitly editing a top-level EditBox colour, mark it
    -- as an explicit override so theme changes won't stomp the user's choice.
    if type(normalizedValue) == "table"
        and #path >= 2
        and path[1] == "EditBox"
        and COLOR_KEYS[path[2]] then
        if type(root._themeOverrides) ~= "table" then root._themeOverrides = {} end
        root._themeOverrides[path[2]] = true
        _G.YapperLocalConf = root
    end

    if type(YapperTable.Config) == "table" and YapperTable.Config ~= root then
        if syncedChatDelineator and syncedChatPrefix then
            SetPathValue(YapperTable.Config, { "Chat", "DELINEATOR" }, syncedChatDelineator)
            SetPathValue(YapperTable.Config, { "Chat", "PREFIX" }, syncedChatPrefix)
        else
            SetPathValue(YapperTable.Config, path, normalizedValue)
        end
    end

    self:SetSettingsChanged(true)

    if JoinPath(path) == "FrameSettings.MouseWheelStepRate" and type(normalizedValue) == "number" then
        Interface.MouseWheelStepRate = normalizedValue
    elseif JoinPath(path) == "FrameSettings.EnableMinimapButton" then
        Interface:ApplyMinimapButtonVisibility()
    elseif JoinPath(path) == "FrameSettings.MinimapButtonOffset" then
        Interface:PositionMinimapButton()
    elseif JoinPath(path):match("^Spellcheck%.") then
        if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnConfigChanged) == "function" then
            YapperTable.Spellcheck:OnConfigChanged()
        end
    elseif JoinPath(path) == "System.EnableGopherBridge" then
        if YapperTable.GopherBridge and YapperTable.GopherBridge.UpdateState then
            YapperTable.GopherBridge:UpdateState(normalizedValue)
        end
    elseif JoinPath(path) == "System.EnableTypingTrackerBridge" then
        if YapperTable.TypingTrackerBridge and YapperTable.TypingTrackerBridge.UpdateState then
            YapperTable.TypingTrackerBridge:UpdateState(normalizedValue)
        end
    elseif (JoinPath(path) == "EditBox.StickyChannel" or JoinPath(path) == "EditBox.StickyGroupChannel")
        and YapperTable.EditBox
        and YapperTable.EditBox.PersistLastUsed then
        -- Apply the new stickiness rules to LastUsed immediately so the next
        -- open reflects the change without needing an open/close cycle first.
        YapperTable.EditBox:PersistLastUsed()
    end

    if path[1] == "EditBox"
        and YapperTable.EditBox
        and YapperTable.EditBox.ApplyConfigToLiveOverlay then
        YapperTable.EditBox:ApplyConfigToLiveOverlay()
    end

    -- Apply active theme immediately when changed.
    if JoinPath(path) == "System.ActiveTheme" then
        if YapperTable.Theme and type(YapperTable.Theme.SetTheme) == "function" then
            pcall(function()
                YapperTable.Theme:SetTheme(value)
            end)
        end
        if YapperTable.EditBox and YapperTable.EditBox.ApplyConfigToLiveOverlay then
            pcall(function()
                YapperTable.EditBox:ApplyConfigToLiveOverlay()
            end)
        end
    end

    self:SetDirty(true)
    return normalizedValue
end

function Interface:GetLauncherTooltipLines()
    return {
        "Left-Click: Toggle Settings",
        "Right-Click: Toggle Settings",
    }
end

function Interface:GetMinimapButtonSettings()
    if type(_G.YapperDB) ~= "table" then
        _G.YapperDB = {}
    end
    if type(_G.YapperDB.minimapbutton) ~= "table" then
        _G.YapperDB.minimapbutton = { hide = false, angle = 220 }
    end
    if _G.YapperDB.minimapbutton.angle == nil then
        _G.YapperDB.minimapbutton.angle = 220
    end
    return _G.YapperDB.minimapbutton
end

function Interface:GetMinimapButtonOffset()
    return tonumber(self:GetConfigPath({ "FrameSettings", "MinimapButtonOffset" })) or 0
end

function Interface:PositionMinimapButton()
    if not self.MinimapButton or not _G.Minimap then return end
    local minimapCfg = self:GetMinimapButtonSettings()
    local angle = tonumber(minimapCfg.angle) or 220
    local radius = ((_G.Minimap:GetWidth() or 140) / 2) + 10 + self:GetMinimapButtonOffset()
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    self.MinimapButton:ClearAllPoints()
    self.MinimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

function Interface:UpdateMinimapButtonAngleFromCursor()
    if not _G.Minimap then return end
    local mx, my = _G.Minimap:GetCenter()
    if not mx or not my then return end
    local cx, cy = GetCursorPosition()
    local scale = _G.Minimap:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    local dx = cx - mx
    local dy = cy - my
    local angleRad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
    local angle = math.deg(angleRad)
    local minimapCfg = self:GetMinimapButtonSettings()
    minimapCfg.angle = angle
    self:PositionMinimapButton()
end

function Interface:ApplyMinimapButtonVisibility()
    local enabled = self:GetConfigPath({ "FrameSettings", "EnableMinimapButton" }) ~= false
    local minimapCfg = self:GetMinimapButtonSettings()
    minimapCfg.hide = not enabled

    if self.DBIcon and self.MinimapLDBObject then
        if enabled then
            self.DBIcon:Show(YapperName)
        else
            self.DBIcon:Hide(YapperName)
        end
    end

    if self.MinimapButton then
        self.MinimapButton:SetShown(enabled)
        if enabled then
            self:PositionMinimapButton()
        end
    end
end

function Interface:GetFriendlyLabel(item)
    if not item then return "" end
    if item.kind == "section" then
        return FRIENDLY_LABELS["SECTION." .. item.full] or item.key
    end
    return FRIENDLY_LABELS[item.full] or item.key
end

function Interface:SanitizeLocalConfig()
    local defaults = self:GetDefaultsRoot()
    local localConf = self:GetLocalConfigRoot()
    if type(defaults) ~= "table" then return end

    PruneUnknown(localConf, defaults)
end

function Interface:BuildRenderSchema()
    local defaults = self:GetDefaultsRoot()
    if type(defaults) ~= "table" then return {} end

    local schema = {}

    -- Hide internal / engine-facing settings from normal rendering.
    local function shouldSkipPath(path)
        local full = JoinPath(path)
        if full == "System.ActiveTheme" then
            return true
        end
        if full == "System.SettingsHaveChanged"
            or full == "System.VERSION"
            or full == "System.FRAME_ID_PARENT"
            or full == "System._welcomeShown"
            or full == "FrameSettings.MouseWheelStepRate"
            or full == "FrameSettings.MainWindowPosition"
            or full == "FrameSettings.SettingsViewMode"
            or full == "FrameSettings.UIFontOffset"
            or full == "EditBox.FontPad"
            or full == "Chat.STALL_TIMEOUT"
            or full == "Chat.CHARACTER_LIMIT"
            or full == "Chat.CHARACTER_LIMIT"
            or full == "Chat.PREFIX"
            or full == "System.EnableGopherBridge"
            or full == "System.EnableTypingTrackerBridge" then
            return true
        end

        if #path == 2 and path[1] == "EditBox"
            and (path[2] == "ChannelColorMaster"
                or path[2] == "ChannelColorOverrides"
                or path[2] == "ChannelTextColors"
                or path[2] == "TextColor"
                or path[2] == "BorderColor") then
            -- BorderColor is rendered conditionally near the theme picker instead.
            return true
        end

        return false
    end

    -- Avoid rendering empty section headers.
    local function hasRenderableEntries(tbl, path)
        if type(tbl) ~= "table" then return false end
        for key, value in pairs(tbl) do
            local nextPath = ClonePath(path)
            nextPath[#nextPath + 1] = key

            if not shouldSkipPath(nextPath) then
                if type(value) == "table" then
                    if IsColorTable(value) and COLOR_KEYS[key] then
                        return true
                    end
                    if hasRenderableEntries(value, nextPath) then
                        return true
                    end
                elseif type(value) == "boolean" or type(value) == "string" or type(value) == "number" then
                    return true
                end
            end
        end
        return false
    end

    -- Walk defaults tree and emit typed UI items.
    local function walk(tbl, path)
        local keys = {}
        for key in pairs(tbl) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, key in ipairs(keys) do
            local value = tbl[key]
            local nextPath = ClonePath(path)
            nextPath[#nextPath + 1] = key

            if not shouldSkipPath(nextPath) then
                if type(value) == "table" then
                    if IsColorTable(value) and COLOR_KEYS[key] then
                        schema[#schema + 1] = {
                            kind = "color",
                            key = key,
                            path = nextPath,
                            full = JoinPath(nextPath),
                        }
                    else
                        if hasRenderableEntries(value, nextPath) then
                            schema[#schema + 1] = {
                                kind = "section",
                                key = key,
                                path = nextPath,
                                full = JoinPath(nextPath),
                            }
                            walk(value, nextPath)
                        end
                    end
                elseif type(value) == "boolean" then
                    schema[#schema + 1] = {
                        kind = "boolean",
                        key = key,
                        path = nextPath,
                        full = JoinPath(nextPath),
                    }
                elseif type(value) == "string" or type(value) == "number" then
                    local kind = "text"
                    if JoinPath(nextPath) == "EditBox.FontSize" then
                        kind = "fontsize"
                    elseif JoinPath(nextPath) == "EditBox.FontFlags" then
                        kind = "fontflags"
                    elseif JoinPath(nextPath) == "Spellcheck.Locale" then
                        kind = "spellcheck_locale"
                    elseif JoinPath(nextPath) == "Spellcheck.UnderlineStyle" then
                        kind = "spellcheck_underline"
                    end
                    schema[#schema + 1] = {
                        kind = kind,
                        key = key,
                        path = nextPath,
                        full = JoinPath(nextPath),
                        valueType = type(value),
                    }
                end
            end
        end
    end

    walk(defaults, {})

    -- Add theme selector (custom, not derived from defaults).
    schema[#schema + 1] = {
        kind = "theme",
        key = "ActiveTheme",
        path = { "System", "ActiveTheme" },
        full = "System.ActiveTheme",
    }
    return schema
end

function Interface:GetRenderSchema()
    local cache = self:GetRenderCacheContainer()
    if type(cache.schema) ~= "table" then
        cache.schema = self:BuildRenderSchema()
    end
    return cache.schema
end

function Interface:RefreshRenderSchema()
    local cache = self:GetRenderCacheContainer()
    cache.schema = self:BuildRenderSchema()
    cache.dirty = false
end

function Interface:OnWindowClosed()
    if self:IsDirty() then
        self:RefreshRenderSchema()
    end
end

function Interface:GetMainWindowPositionStore()
    -- Stored per-character under local config root.
    local root = self:GetLocalConfigRoot()
    if type(root.FrameSettings) ~= "table" then
        root.FrameSettings = {}
    end
    if type(root.FrameSettings.MainWindowPosition) ~= "table" then
        root.FrameSettings.MainWindowPosition = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        }
    end
    return root.FrameSettings.MainWindowPosition
end

function Interface:SaveMainWindowPosition(frame)
    -- Persist only anchor + offsets; size is static elsewhere.
    if not frame or not frame.GetPoint then return end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not IsAnchorPoint(point) then point = "CENTER" end
    if not IsAnchorPoint(relativePoint) then relativePoint = point end
    xOfs = tonumber(xOfs) or 0
    yOfs = tonumber(yOfs) or 0

    local store = self:GetMainWindowPositionStore()
    store.point = point
    store.relativePoint = relativePoint
    store.x = xOfs
    store.y = yOfs
end

function Interface:ApplyMainWindowPosition(frame)
    -- Apply saved anchor safely with validation fallbacks.
    if not frame or not frame.SetPoint then return end

    local store = self:GetMainWindowPositionStore()
    local point = IsAnchorPoint(store.point) and store.point or "CENTER"
    local relativePoint = IsAnchorPoint(store.relativePoint) and store.relativePoint or point
    local xOfs = tonumber(store.x) or 0
    local yOfs = tonumber(store.y) or 0

    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)
end

-- ---------------------------------------------------------------------------
-- Frame functions
-- ---------------------------------------------------------------------------

-- Create the scrollable content area inside a parent window frame.
-- The content sits to the right of the sidebar.
local function CreateScrollableContent(parent)
    local P = LAYOUT
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    parent.ScrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", P.SIDEBAR_WIDTH + P.WINDOW_PADDING, -P.TITLE_INSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
        -(P.WINDOW_PADDING + P.SCROLLBAR_WIDTH + P.SCROLLBAR_GAP), P.BOTTOM_BAR)
    scrollFrame:SetClipsChildren(true)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
    content:SetHeight(1000)
    parent.ContentFrame = content

    -- Keep content width in sync with the scroll viewport.
    local function UpdateContentWidth()
        content:SetWidth(scrollFrame:GetWidth())
    end
    scrollFrame:SetScript("OnSizeChanged", UpdateContentWidth)
    UpdateContentWidth()
    scrollFrame:SetScrollChild(content)

    -- Mouse wheel support.
    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = tonumber(Interface:GetConfigPath({ "FrameSettings", "MouseWheelStepRate" }))
            or Interface.MouseWheelStepRate
        local cur = self:GetVerticalScroll()
        local maxv = self:GetVerticalScrollRange()
        local nxt = math.min(maxv, math.max(0, cur - delta * step))
        self:SetVerticalScroll(nxt)
        if self.ScrollBar and self.ScrollBar:IsShown() then
            self.ScrollBar:SetValue(nxt)
        end
    end)
    scrollFrame:SetScript("OnHorizontalScroll", function(self) self:SetHorizontalScroll(0) end)

    return scrollFrame, content
end

-- Attach a scrollbar to a parent frame that drives an existing ScrollFrame.
local function CreateScrollBarForFrame(parent, scrollFrame)
    local P = LAYOUT
    local scrollBar = CreateFrame("Slider", nil, parent, "UIPanelScrollBarTemplate")
    parent.ScrollBar = scrollBar
    scrollFrame.ScrollBar = scrollBar

    scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P.WINDOW_PADDING, -P.SCROLLBAR_TOP_INSET)
    scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -P.WINDOW_PADDING, P.SCROLLBAR_BOTTOM_INSET)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetWidth(P.SCROLLBAR_WIDTH)

    local function UpdateVisibility(yRange)
        yRange = math.max(0, yRange or 0)
        local needsScroll = yRange > 0
        scrollBar:SetMinMaxValues(0, yRange)
        scrollBar:SetShown(needsScroll)
        if not needsScroll then
            scrollFrame:SetVerticalScroll(0)
            scrollBar:SetValue(0)
        else
            local cur = scrollFrame:GetVerticalScroll()
            if cur > yRange then
                scrollFrame:SetVerticalScroll(yRange)
                scrollBar:SetValue(yRange)
            end
        end
    end

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(_, _, yRange)
        UpdateVisibility(yRange)
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        if scrollBar:IsShown() then scrollBar:SetValue(offset) end
    end)

    scrollFrame:UpdateScrollChildRect()
    UpdateVisibility(scrollFrame:GetVerticalScrollRange())
    return scrollBar
end

-- Active sidebar category — persists for the session.
Interface._activeCategory = "general"

-- ---------------------------------------------------------------------------
-- First-run appearance choice popup
-- ---------------------------------------------------------------------------
-- Shows once when VERSION < 1.1 (or on every reload if DEBUG is on).
-- Two columns: "Blizzard Skin" vs "Yapper's Own", each with a preview slot.

function Interface:ShouldShowWelcomeChoice()
    local debug = YapperTable.Config and YapperTable.Config.System
        and YapperTable.Config.System.DEBUG == true
    if debug then return true end

    -- Check raw saved variable — the value before defaults got merged in.
    local sv = _G.YapperLocalConf
    if type(sv) ~= "table" then return true end
    local sys = sv.System
    if type(sys) ~= "table" then return true end
    local ver = tonumber(sys._welcomeShown)
    if not ver or ver < 1.1 then return true end
    return false
end

function Interface:MarkWelcomeShown()
    if type(_G.YapperLocalConf) ~= "table" then return end
    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end
    _G.YapperLocalConf.System._welcomeShown = 1.1
end

function Interface:CreateWelcomeChoiceFrame()
    if self.WelcomeFrame then return end

    local FRAME_W      = 960
    local FRAME_H      = 540
    local COL_W        = 440
    local PREVIEW_H    = 320
    local BTN_W        = 200
    local BTN_H        = 36
    local PAD           = 20

    -- Fullscreen darkener.
    local dimmer = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    dimmer:SetBackdropColor(0, 0, 0, 0.55)
    dimmer:EnableMouse(true) -- block clicks through

    -- Main container.
    local frame = CreateFrame("Frame", "YapperWelcomeChoice", dimmer, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(dimmer:GetFrameLevel() + 5)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    -- Title.
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -PAD)
    title:SetText("Choose Your Editbox Appearance")
    title:SetTextColor(1, 0.82, 0, 1)

    -- Subtitle.
    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetWidth(FRAME_W - 60)
    sub:SetText("You can change this at any time in settings. Pick whichever you prefer!")
    sub:SetTextColor(0.75, 0.75, 0.75, 1)

    local contentTop = -72  -- below title+subtitle

    -- Helper: build one column (button + preview area).
    local function BuildColumn(anchorX, labelText, descText, onClick)
        -- Button first (at top of column).
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", frame, "TOP", anchorX, contentTop)
        btn:SetText(labelText)
        btn:SetScript("OnClick", onClick)

        -- Short description under button.
        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOP", btn, "BOTTOM", 0, -6)
        desc:SetWidth(COL_W - 20)
        desc:SetJustifyH("CENTER")
        desc:SetText(descText)
        desc:SetTextColor(0.65, 0.65, 0.65, 1)

        -- Preview placeholder underneath.
        local preview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        preview:SetSize(COL_W, PREVIEW_H)
        preview:SetPoint("TOP", btn, "BOTTOM", 0, -36)
        preview:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        preview:SetBackdropColor(0.04, 0.04, 0.04, 1)
        preview:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

        -- Preview image texture (filled in per-column after BuildColumn).
        local tex = preview:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", preview, "TOPLEFT", 3, -3)
        tex:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -3, 3)
        preview.Texture = tex

        return btn, preview
    end

    local function closeWelcome()
        Interface:MarkWelcomeShown()
        dimmer:Hide()
        dimmer:SetParent(nil)
        Interface.WelcomeFrame = nil
    end

    -- Left column: Blizzard Skin Proxy.
    local blizzBtn, blizzPreview = BuildColumn(
        -(COL_W / 2 + PAD / 2),  -- left of centre
        "Blizzard",
        "Imitates Blizzard's default appearance, but offers less customisation. May not be compatible with other re-skinning addons, in which case Yapper's own theme may serve your needs.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, true)
            closeWelcome()
        end
    )

    -- Right column: Yapper's Own.
    local yapperBtn, yapperPreview = BuildColumn(
        (COL_W / 2 + PAD / 2),   -- right of centre
        "Yapper",
        "Fully customiseable with background colours, but utilitarian and unstylised.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, false)
            closeWelcome()
        end
    )

    -- Store references for preview images if added later.
    frame.BlizzPreview  = blizzPreview
    frame.YapperPreview = yapperPreview
    frame.Dimmer        = dimmer

    -- Set preview screenshots.
    local addonPath = "Interface\\AddOns\\Yapper\\Src\\Img\\"
    blizzPreview.Texture:SetTexture(addonPath .. "BlizzTheme")
    blizzPreview.Texture:SetTexCoord(0, 1, 0, 1)
    yapperPreview.Texture:SetTexture(addonPath .. "YapperTheme")
    yapperPreview.Texture:SetTexCoord(0, 1, 0, 1)

    self.WelcomeFrame = frame
    dimmer:Show()
end

-- ---------------------------------------------------------------------------

-- Create the main settings window.
function Interface:CreateMainWindow()
    -- Prevent duplicate creation.
    if Interface.MainWindowFrame
        and Interface.MainWindowFrame.IsObjectType
        and Interface.MainWindowFrame:IsObjectType("Frame") then
        return
    end
    Interface.MainWindowFrame = nil

    local frame = CreateFrame(
        "Frame",
        YapperName .. "MainWindow",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    Interface.MainWindowFrame = frame
    frame:Hide()

    frame:SetSize(LAYOUT.WINDOW_WIDTH, LAYOUT.WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(true)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Interface:SaveMainWindowPosition(self)
    end)
    frame:SetClampedToScreen(true)
    Interface:ApplyMainWindowPosition(frame)

    if frame.TitleText and frame.TitleText.SetText then
        frame.TitleText:SetText("Yapper Settings")
    end
    if frame.CloseButton ~= nil then
        frame.CloseButton:SetScript("OnClick", function(self)
            Interface:CloseFrame(self:GetParent())
        end)
    end

    -- -----------------------------------------------------------------------
    -- Sidebar
    -- -----------------------------------------------------------------------
    local P = LAYOUT
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", P.WINDOW_PADDING, -P.SIDEBAR_TOP_INSET)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P.WINDOW_PADDING, P.BOTTOM_BAR + 4)
    sidebar:SetWidth(P.SIDEBAR_WIDTH)
    frame.Sidebar = sidebar

    -- Vertical divider between sidebar and content.
    local divider = sidebar:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    divider:SetWidth(1)
    divider:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)

    -- -----------------------------------------------------------------------
    -- Font-size +/– control at the top of the sidebar.
    -- -----------------------------------------------------------------------
    local fontRow = CreateFrame("Frame", nil, sidebar)
    fontRow:SetSize(P.SIDEBAR_WIDTH - 8, 24)
    fontRow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)

    local fontLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontLabel:SetPoint("LEFT", fontRow, "LEFT", 4, 0)
    fontLabel:SetText("Font:")
    fontLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Current size readout.
    local sizeLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("CENTER", fontRow, "CENTER", 0, 0)
    frame.FontScaleLabel = sizeLabel

    -- Minus button.
    local minusBtn = CreateFrame("Button", nil, fontRow)
    minusBtn:SetSize(20, 20)
    minusBtn:SetPoint("RIGHT", sizeLabel, "LEFT", -4, 0)
    minusBtn:SetNormalFontObject(GameFontNormal)
    minusBtn:SetHighlightFontObject(GameFontHighlight)
    minusBtn:SetText("\226\128\147")  -- en-dash as minus glyph
    local minusHl = minusBtn:CreateTexture(nil, "HIGHLIGHT")
    minusHl:SetAllPoints()
    minusHl:SetColorTexture(1, 1, 1, 0.08)
    frame.FontMinusBtn = minusBtn

    -- Plus button.
    local plusBtn = CreateFrame("Button", nil, fontRow)
    plusBtn:SetSize(20, 20)
    plusBtn:SetPoint("LEFT", sizeLabel, "RIGHT", 4, 0)
    plusBtn:SetNormalFontObject(GameFontNormal)
    plusBtn:SetHighlightFontObject(GameFontHighlight)
    plusBtn:SetText("+")
    local plusHl = plusBtn:CreateTexture(nil, "HIGHLIGHT")
    plusHl:SetAllPoints()
    plusHl:SetColorTexture(1, 1, 1, 0.08)
    frame.FontPlusBtn = plusBtn

    minusBtn:SetScript("OnClick", function()
        local cur = Interface:GetUIFontOffset()
        Interface:SetUIFontOffset(cur - UI_FONT_STEP)
        Interface:RefreshFontScaleLabel()
        Interface:BuildConfigUI()
    end)
    plusBtn:SetScript("OnClick", function()
        local cur = Interface:GetUIFontOffset()
        Interface:SetUIFontOffset(cur + UI_FONT_STEP)
        Interface:RefreshFontScaleLabel()
        Interface:BuildConfigUI()
    end)

    -- Thin separator between font control and category buttons.
    local fontSep = sidebar:CreateTexture(nil, "ARTWORK")
    fontSep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    fontSep:SetHeight(1)
    fontSep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -28)
    fontSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -8, -28)

    -- Build one button per category.
    frame.SidebarButtons = {}
    local btnY = 32  -- start below font row + separator
    for _, cat in ipairs(CATEGORIES) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(P.SIDEBAR_WIDTH - 8, P.SIDEBAR_BTN_HEIGHT)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -btnY)
        btnY = btnY + P.SIDEBAR_BTN_HEIGHT + P.SIDEBAR_BTN_PAD

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", btn, "LEFT", 8, 0)
        label:SetText(cat.label)
        btn.Label = label

        -- Highlight texture
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        -- Selected indicator (left accent bar)
        local sel = btn:CreateTexture(nil, "OVERLAY")
        sel:SetColorTexture(0.9, 0.75, 0.2, 1)
        sel:SetWidth(3)
        sel:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        sel:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        sel:Hide()
        btn.SelectedBar = sel

        -- Background for selected state
        local selBg = btn:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints()
        selBg:SetColorTexture(1, 1, 1, 0.05)
        selBg:Hide()
        btn.SelectedBg = selBg

        btn.categoryId = cat.id
        btn:SetScript("OnClick", function()
            Interface._activeCategory = cat.id
            Interface:UpdateSidebarSelection()
            Interface:BuildConfigUI()
        end)

        frame.SidebarButtons[cat.id] = btn
    end

    -- Delegate scrolling to focused helpers.
    local scrollFrame = CreateScrollableContent(frame)
    CreateScrollBarForFrame(frame, scrollFrame)

    -- Bottom close button.
    local bottomClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bottomClose:SetSize(LAYOUT.CLOSE_BTN_WIDTH, LAYOUT.CLOSE_BTN_HEIGHT)
    bottomClose:SetPoint("BOTTOM", frame, "BOTTOM", 0, LAYOUT.CLOSE_BTN_OFFSET_Y)
    bottomClose:SetText("Close")
    bottomClose:SetScript("OnClick", function()
        Interface:CloseFrame(frame)
    end)
    frame.BottomCloseButton = bottomClose

    -- Apply initial sidebar selection highlight.
    self:UpdateSidebarSelection()
end

-- Refresh the visual state of sidebar buttons to reflect _activeCategory.
function Interface:UpdateSidebarSelection()
    local frame = self.MainWindowFrame
    if not frame or not frame.SidebarButtons then return end
    for catId, btn in pairs(frame.SidebarButtons) do
        local selected = (catId == self._activeCategory)
        btn.SelectedBar:SetShown(selected)
        btn.SelectedBg:SetShown(selected)
        if selected then
            btn.Label:SetFontObject(GameFontHighlight)
        else
            btn.Label:SetFontObject(GameFontNormal)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings-panel font scaling
-- ---------------------------------------------------------------------------

function Interface:GetUIFontOffset()
    local v = tonumber(self:GetConfigPath({ "FrameSettings", "UIFontOffset" }))
    if v then return v end
    return 0
end

function Interface:SetUIFontOffset(offset)
    offset = math.max(UI_FONT_MIN_OFFSET, math.min(UI_FONT_MAX_OFFSET, offset))
    self:SetLocalPath({ "FrameSettings", "UIFontOffset" }, offset)
    return offset
end

--- Return a row height scaled by the current font offset so elements don't
--- overlap when the user increases the UI font size.
function Interface:ScaledRow(base)
    return base + self:GetUIFontOffset()
end

--- Walk every FontString under the settings window and set its size to
--- the Blizzard base size + the user's offset.
function Interface:ApplyUIFontScale()
    local offset = self:GetUIFontOffset()
    local frame  = self.MainWindowFrame
    if not frame then return end

    -- Query the Blizzard base once per pass.
    local _, blizzBase = GameFontNormal:GetFont()
    blizzBase = blizzBase or 12
    local targetSize = math.max(8, blizzBase + offset)

    local function scaleRegions(parent)
        for _, region in pairs({ parent:GetRegions() }) do
            if region:IsObjectType("FontString") then
                local fontFile, _, fontFlags = region:GetFont()
                if fontFile then
                    region:SetFont(fontFile, targetSize, fontFlags or "")
                end
            end
        end
        for _, child in pairs({ parent:GetChildren() }) do
            scaleRegions(child)
        end
    end

    scaleRegions(frame)
end

--- Update the font-scale label text to reflect the current effective size.
function Interface:RefreshFontScaleLabel()
    local frame = self.MainWindowFrame
    if not frame or not frame.FontScaleLabel then return end
    local offset = self:GetUIFontOffset()
    local _, baseSize = GameFontNormal:GetFont()
    baseSize = baseSize or 12
    frame.FontScaleLabel:SetText(tostring(math.floor(baseSize + offset)))
end

-- ---------------------------------------------------------------------------
-- Dynamic config UI
-- ---------------------------------------------------------------------------

function Interface:ClearConfigControls()
    if type(self.DynamicControls) ~= "table" then
        self.DynamicControls = {}
        return
    end
    for _, widget in ipairs(self.DynamicControls) do
        self:ReleaseWidget(widget)
    end
    self.DynamicControls = {}
end

function Interface:AddControl(widget)
    if type(self.DynamicControls) ~= "table" then
        self.DynamicControls = {}
    end
    self.DynamicControls[#self.DynamicControls + 1] = widget
end

-- ---------------------------------------------------------------------------
-- WidgetShownState pooling to efficiently create frames and prevent memory leaks
-- ---------------------------------------------------------------------------

Interface.WidgetPool = {
    -- Keyed by widget type string.
    -- Values are arrays of hidden frames.
}

---@param widgetType string
---@param parent table
---@param template string?
---@param frameType string?
---@return table
function Interface:AcquireWidget(widgetType, parent, template, frameType)
    if not self.WidgetPool[widgetType] then
        self.WidgetPool[widgetType] = {}
    end

    local pool = self.WidgetPool[widgetType]
    local widget = table.remove(pool)

    if not widget then
        -- Create new if pool is empty.
        if frameType == "FontString" then
            widget = parent:CreateFontString(nil, "OVERLAY", template)
        else
            widget = CreateFrame(frameType or "Frame", nil, parent, template)
        end
        widget.widgetType = widgetType
        widget:Show()
    else
        -- Recycle existing.
        widget:SetParent(parent)
        widget:ClearAllPoints()
        widget:Show()
    end

    -- Ensure visibility above parent (fixes vanishing buttons behind backgrounds)
    if widget.SetFrameLevel then
        widget:SetFrameLevel(parent:GetFrameLevel() + 5)
    end

    return widget
end

function Interface:ReleaseWidget(widget)
    if not widget or not widget.widgetType then return end

    local pool = self.WidgetPool[widget.widgetType]
    if not pool then
        pool = {}
        self.WidgetPool[widget.widgetType] = pool
    end

    widget:Hide()
    widget:ClearAllPoints()
    widget:SetParent(nil)

    -- Clear script handlers to prevent ghost callbacks from previous lifecycle.
    if widget.SetScript then
        local scripts = {
            "OnClick", "OnEnter", "OnLeave", "OnValueChanged",
            "OnEditFocusLost", "OnEnterPressed", "OnChar", "OnTextChanged",
            "OnUpdate"
        }
        for _, scriptName in ipairs(scripts) do
            if widget:HasScript(scriptName) then
                widget:SetScript(scriptName, nil)
            end
        end
    end

    -- Reset visual state that might persist.
    widget:SetAlpha(1)
    if widget.Enable then widget:Enable() end
    if widget.SetScale then widget:SetScale(1) end

    -- FontStrings: clear stale width / word-wrap so recycled labels are clean.
    if widget.SetWidth and widget.SetWordWrap then
        widget:SetWidth(0)
        widget:SetWordWrap(false)
    end

    pool[#pool + 1] = widget
end

function Interface:GetTooltip(key)
    local tip = SETTING_TOOLTIPS[key]
    if tip and (key == "EditBox.InputBg" or key == "EditBox.LabelBg") then
        if self:GetConfigPath({ "EditBox", "UseBlizzardSkinProxy" }) == true then
            tip = tip .. "\n\n|cFFFFD100Note:|r Blizzard's skin is pre-coloured. For best results, disable the skin proxy and use Yapper's own appearance settings."
        end
    end
    return tip
end

function Interface:AttachTooltip(region, tooltipText, titleText)
    if not region or type(tooltipText) ~= "string" or tooltipText == "" then return end
    if region.EnableMouse then
        region:EnableMouse(true)
    end

    local function onEnter(selfFrame)
        -- Restore any leftover inflated fonts from a prior hover before
        -- measuring base sizes, so the offset never compounds.
        if GameTooltip._yFontBackup then
            for _, bk in ipairs(GameTooltip._yFontBackup) do
                if bk.fs and bk.file then
                    pcall(bk.fs.SetFont, bk.fs, bk.file, bk.size, bk.flags)
                end
            end
            GameTooltip._yFontBackup = nil
        end

        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
        if type(titleText) == "string" and titleText ~= "" then
            GameTooltip:AddLine(titleText, 1, 1, 1, true)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        else
            ---@diagnostic disable-next-line: param-type-mismatch
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        end
        GameTooltip:Show()

        -- Scale tooltip font proportionally with the UI font offset, but
        -- clamp so the tooltip never exceeds screen width.
        local offset = Interface:GetUIFontOffset()
        if offset ~= 0 then
            local screenW = GetScreenWidth() or 1920
            local maxTipW = screenW * 0.45  -- allow up to 45% of screen

            -- Snapshot base sizes BEFORE any modification.
            local regions = {}
            for _, region in pairs({ GameTooltip:GetRegions() }) do
                if region:IsObjectType("FontString") then
                    ---@diagnostic disable-next-line: undefined-field
                    local fontFile, fontSize, fontFlags = region:GetFont()
                    if fontFile and fontSize then
                        regions[#regions + 1] = { fs = region, file = fontFile, size = fontSize, flags = fontFlags or "" }
                    end
                end
            end

            -- Save originals so onLeave can restore them.
            GameTooltip._yFontBackup = regions

            -- Binary-search for the largest usable offset in [0, offset].
            local bestOffset = 0
            local lo, hi = 0, offset
            for _ = 1, 8 do
                local mid = math.floor((lo + hi) / 2 + 0.5)
                if mid == 0 then lo = 0; break end
                for _, r in ipairs(regions) do
                    r.fs:SetFont(r.file, r.size + mid, r.flags)
                end
                GameTooltip:Show()
                local tipW = GameTooltip:GetWidth() or 0
                if tipW <= maxTipW then
                    bestOffset = mid
                    lo = mid
                else
                    hi = mid - 1
                end
                if lo >= hi then break end
            end

            -- Apply final sizes.
            for _, r in ipairs(regions) do
                r.fs:SetFont(r.file, r.size + bestOffset, r.flags)
            end
            GameTooltip:Show()
        end
    end

    local function onLeave()
        -- Restore original font sizes before hiding so the next tooltip
        -- starts from genuine base sizes, not our inflated ones.
        if GameTooltip._yFontBackup then
            for _, bk in ipairs(GameTooltip._yFontBackup) do
                if bk.fs and bk.file then
                    pcall(bk.fs.SetFont, bk.fs, bk.file, bk.size, bk.flags)
                end
            end
            GameTooltip._yFontBackup = nil
        end
        GameTooltip:Hide()
    end

    -- Cleanly replace recycled pool widgets.
    if region.SetScript and region.HasScript
        and region:HasScript("OnEnter") then
        region:SetScript("OnEnter", onEnter)
        region:SetScript("OnLeave", onLeave)
    elseif region.HookScript then
        region:HookScript("OnEnter", onEnter)
        region:HookScript("OnLeave", onLeave)
    end
end

function Interface:CreateResetButton(parent, x, y, onClick)
    -- Shared reset control helper for scalar/color rows.
    local btn = self:AcquireWidget("ResetButton", parent, "UIPanelButtonTemplate", "Button")
    btn:SetSize(58, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText("Reset")
    btn:SetScript("OnClick", onClick)
    self:AddControl(btn)
    return btn
end

function Interface:CreateLabel(parent, text, x, y, width, tooltipText, fontObj)
    -- Labels are tracked like controls so rebuild cleanup is consistent.
    -- Default to White (GameFontHighlight) for option labels.
    local font = fontObj or "GameFontHighlight"

    local fs = self:AcquireWidget("Label", parent, font, "FontString")
    fs:SetFontObject(font)

    if font == "GameFontNormal" then
        fs:SetTextColor(1, 0.82, 0, 1) -- Gold for Titles
    else
        fs:SetTextColor(1, 1, 1, 1)    -- White for Options
    end

    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    self:AddControl(fs)

    -- Detect truncation: if the natural text width exceeds the label width,
    -- the label is being ellipsized.  In that case, show the full text as a
    -- title line above the description tooltip.
    local isTruncated = (fs.IsTruncated and fs:IsTruncated())
        or ((fs:GetStringWidth() or 0) > width)
    local titleLine = isTruncated and text or nil

    -- Build a combined tooltip: if no explicit description was provided but
    -- the label IS truncated, still show a tooltip with just the full text.
    local effectiveTooltip = tooltipText
    if not effectiveTooltip or effectiveTooltip == "" then
        if isTruncated then
            effectiveTooltip = text   -- tooltip body = full label
            titleLine = nil           -- no separate title needed
        end
    end

    -- For tooltips, spawn an invisible hit-frame sized to the actual rendered
    -- text so the tooltip appears next to the label, not out in space.
    if type(effectiveTooltip) == "string" and effectiveTooltip ~= "" then
        self:AttachTooltip(fs, effectiveTooltip, titleLine)
        local hitFrame = self:AcquireWidget("LabelHitFrame", parent, nil, "Frame")
        hitFrame:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 2)
        hitFrame:SetPoint("BOTTOMLEFT", fs, "BOTTOMLEFT", 0, -2)
        -- Size to actual text width so ANCHOR_RIGHT stays near the label.
        local textW = fs:GetStringWidth() or 100
        hitFrame:SetWidth(math.min(textW + 8, width))
        hitFrame:SetFrameLevel(parent:GetFrameLevel() + 6)
        hitFrame:EnableMouse(true)
        self:AttachTooltip(hitFrame, effectiveTooltip, titleLine)
        self:AddControl(hitFrame)
    end
    return fs
end

-- ---------------------------------------------------------------------------
-- Unified ColorPicker helper — used by both channel and config pickers.
-- ---------------------------------------------------------------------------
-- opts = {
--   color       : {r,g,b,a}   — starting colour
--   hasOpacity  : boolean      — show alpha slider?
--   onApply     : function(newColor)   — called on confirm / live tick
--   onCancel    : function(prevColor)  — called on cancel
-- }
local function OpenColorPicker(opts)
    local color       = opts.color
    local previous    = CopyColor(color)
    local liveTicker  = nil
    local lastApplied = nil

    local function sameColor(lhs, rhs)
        if type(lhs) ~= "table" or type(rhs) ~= "table" then return false end
        return lhs.r == rhs.r and lhs.g == rhs.g and lhs.b == rhs.b and lhs.a == rhs.a
    end

    local function stopLiveTicker()
        if liveTicker then
            liveTicker:Cancel(); liveTicker = nil
        end
    end

    -- Read current state from whichever picker API is available.
    local function readPickerColor(callbackData)
        local r, g, b = color.r or 1, color.g or 1, color.b or 1
        local a = color.a or 1
        local hasRgb, hasAlpha = false, false

        if type(callbackData) == "table" then
            if type(callbackData.r) == "number" then
                r, g, b, hasRgb = callbackData.r, callbackData.g, callbackData.b, true
            end
            if type(callbackData.opacity) == "number" then
                a, hasAlpha = callbackData.opacity, true
            elseif type(callbackData.a) == "number" then
                a, hasAlpha = callbackData.a, true
            end
        end

        -- Direct frame polling fallback (for live-updates).
        if not hasRgb and ColorPickerFrame then
            if ColorPickerFrame.GetColorRGB then
                local pr, pg, pb = ColorPickerFrame:GetColorRGB()
                if pr then r, g, b, hasRgb = pr, pg, pb, true end
            elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
                local picker = ColorPickerFrame.Content.ColorPicker
                if picker.GetColorRGB then
                    local pr, pg, pb = picker:GetColorRGB()
                    if pr then r, g, b, hasRgb = pr, pg, pb, true end
                end
            end
        end

        if not hasAlpha and ColorPickerFrame then
            if ColorPickerFrame.GetColorAlpha then
                local alpha = ColorPickerFrame:GetColorAlpha()
                if alpha then a, hasAlpha = alpha, true end
            elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
                local picker = ColorPickerFrame.Content.ColorPicker
                if picker.GetColorAlpha then
                    local alpha = picker:GetColorAlpha()
                    if alpha then a, hasAlpha = alpha, true end
                end
            end
            -- Last resort: legacy property check.
            if not hasAlpha and type(ColorPickerFrame.opacity) == "number" then
                a = 1 - ColorPickerFrame.opacity
            end
        end

        return Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1), Clamp01(a, 1)
    end

    local function applyCurrentColor(callbackData)
        local r, g, b, a = readPickerColor(callbackData)
        local nextColor = { r = r, g = g, b = b, a = a }
        if sameColor(lastApplied, nextColor) then return end
        lastApplied = CopyColor(nextColor)
        opts.onApply(nextColor)
    end

    local function restorePreviousColor(prev)
        stopLiveTicker()
        prev = prev or previous
        if prev then
            opts.onCancel(CopyColor(prev))
            lastApplied = CopyColor(prev)
        end
    end

    local function startLiveTicker()
        stopLiveTicker()
        if not (C_Timer and C_Timer.NewTicker) then return end
        liveTicker = C_Timer.NewTicker(0.05, function(ticker)
            if not ColorPickerFrame or not ColorPickerFrame:IsShown() then
                ticker:Cancel(); liveTicker = nil; return
            end
            applyCurrentColor()
        end)
    end

    -- Modern API path.
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        local info                      = {
            r              = color.r,
            g              = color.g,
            b              = color.b,
            opacity        = opts.hasOpacity and (color.a or 1) or nil,
            hasOpacity     = opts.hasOpacity,
            swatchFunc     = function(data) applyCurrentColor(data) end,
            opacityFunc    = opts.hasOpacity and function(data) applyCurrentColor(data) end or nil,
            cancelFunc     = function(prev) restorePreviousColor(prev) end,
            previousValues = previous,
        }
        ColorPickerFrame.previousValues = previous
        ColorPickerFrame.func           = applyCurrentColor
        ColorPickerFrame.opacityFunc    = applyCurrentColor
        ColorPickerFrame.cancelFunc     = restorePreviousColor
        ColorPickerFrame:SetupColorPickerAndShow(info)
        if opts.hasOpacity then startLiveTicker() end
        return
    end

    -- Legacy API fallback.
    if ColorPickerFrame then
        ---@diagnostic disable: undefined-field
        ColorPickerFrame.hasOpacity = opts.hasOpacity
        ColorPickerFrame.opacity    = opts.hasOpacity and (1 - (color.a or 1)) or nil
        if ColorPickerFrame.SetColorRGB then
            ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
        end
        ColorPickerFrame.previousValues = previous
        ColorPickerFrame.func           = applyCurrentColor
        ColorPickerFrame.opacityFunc    = applyCurrentColor
        ColorPickerFrame.cancelFunc     = restorePreviousColor
        ---@diagnostic enable: undefined-field
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
        if opts.hasOpacity then startLiveTicker() end
    end
end

function Interface:CreateCheckBox(parent, label, path, cursor)
    local y = cursor:Y()
    local cb = self:AcquireWidget("CheckBox", parent, "UICheckButtonTemplate", "CheckButton")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, y)


    local text = self:AcquireWidget("Label", parent, "GameFontHighlight", "FontString")
    text:SetFontObject("GameFontHighlight")
    text:SetTextColor(1, 1, 1, 1) -- Force white text (fix recycling color retention)
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetWidth(0)              -- Clear stale width from pool
    text:SetWordWrap(false)
    text:SetText(label)

    local tooltip = self:GetTooltip(JoinPath(path))

    local val = self:GetConfigPath(path)
    cb:SetChecked(val == true)
    cb:SetScript("OnClick", function(selfFrame)
        Interface:SetLocalPath(path, selfFrame:GetChecked() == true)
    end)

    self:AddControl(cb)
    self:AddControl(text)
    self:AttachTooltip(cb, tooltip)
    self:AttachTooltip(text, tooltip)

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHECKBOX))
    return cb
end

function Interface:CreateChannelOverrideControls(parent, cursor)
    -- Custom row block (outside schema renderer) for per-channel colours.
    local y = cursor:Y()
    local title = self:CreateLabel(parent, "Channel Text Colour Overrides",
        LAYOUT.WINDOW_PADDING, y, 340, self:GetTooltip("CHANNEL.HEADER"), "GameFontNormal")

    local rows = {}

    local function getChannelColor(key)
        local color = self:GetConfigPath({ "EditBox", "ChannelTextColors", key })
        if IsColorTable(color) then
            return color
        end
        local def = self:GetDefaultPath({ "EditBox", "ChannelTextColors", key })
        if IsColorTable(def) then
            return def
        end
        return { r = 1, g = 1, b = 1, a = 1 }
    end

    local function setChannelColor(key, color)
        self:SetLocalPath({ "EditBox", "ChannelTextColors", key }, color)
    end

    local function resetAllChannelColors()
        for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
            local def = self:GetDefaultPath({ "EditBox", "ChannelTextColors", option.key })
            if IsColorTable(def) then
                setChannelColor(option.key, CopyColor(def))
            end
        end
        for _, row in ipairs(rows) do
            if row.refreshColor then row.refreshColor() end
        end
    end

    local resetAllBtn = self:CreateResetButton(parent, 290, y - 2, function()
        resetAllChannelColors()
    end)
    resetAllBtn:SetSize(74, 20)
    resetAllBtn:SetText("Reset all")
    self:AttachTooltip(resetAllBtn, self:GetTooltip("CHANNEL.RESET_ALL"))

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_HEADER))
    y = cursor:Y()

    self:CreateLabel(parent, "Colour", 136, y, 60)
    self:CreateLabel(parent, "Master", 252, y, 50, self:GetTooltip("CHANNEL.MASTER"))
    self:CreateLabel(parent, "Override", 322, y, 60, self:GetTooltip("CHANNEL.OVERRIDE"))

    local masterHelp = self:AcquireWidget("HelpButton", parent, "UIPanelButtonTemplate", "Button")
    masterHelp:SetSize(14, 14)
    masterHelp:SetPoint("TOPLEFT", parent, "TOPLEFT", 236, y + 2)
    masterHelp:SetText("?")
    masterHelp:SetScript("OnEnter", function(selfFrame)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
---@diagnostic disable-next-line: missing-parameter
        GameTooltip:SetText("Master Channel")
        GameTooltip:AddLine("Choose one channel as the colour source.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Channels with Override checked", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("use the master's colour.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    masterHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:AddControl(masterHelp)

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_LABELS))
    y = cursor:Y()

    local function getMaster()
        local m = self:GetConfigPath({ "EditBox", "ChannelColorMaster" })
        if type(m) ~= "string" then return nil end
        if m == "" then return nil end
        for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
            if option.key == m then
                return m
            end
        end
        return nil
    end

    local function getOverrideValue(key)
        return self:GetConfigPath({ "EditBox", "ChannelColorOverrides", key }) == true
    end

    local function refreshRows()
        local master = getMaster()
        for _, row in ipairs(rows) do
            local isMaster = (row.key == master)
            row.master:SetChecked(isMaster)
            row.refreshColor()

            if isMaster then
                if getOverrideValue(row.key) then
                    self:SetLocalPath({ "EditBox", "ChannelColorOverrides", row.key }, false)
                end
                row.override:SetChecked(false)
                row.override:Disable()
            else
                row.override:Enable()
                row.override:SetChecked(getOverrideValue(row.key))
            end
        end
    end

    for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
        self:CreateLabel(parent, option.label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH)

        local colorBtn = self:AcquireWidget("ColorPickerButtonSmall", parent, "UIPanelButtonTemplate", "Button")
        colorBtn:SetSize(72, 20)
        colorBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 132, y + 1)
        colorBtn:SetText("Pick")

        local swatch = colorBtn.swatch
        if not swatch then
            swatch = colorBtn:CreateTexture(nil, "ARTWORK")
            swatch:SetPoint("LEFT", colorBtn, "LEFT", 6, 0)
            swatch:SetSize(14, 14)
            swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
            colorBtn.swatch = swatch
        end

        local function refreshColor()
            local c = getChannelColor(option.key) or { r = 1, g = 1, b = 1, a = 1 }
            swatch:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, 1)
        end

        colorBtn:SetScript("OnClick", function()
            local clr = CopyColor(getChannelColor(option.key))
            OpenColorPicker({
                color      = clr,
                hasOpacity = false,
                onApply    = function(newColor)
                    setChannelColor(option.key, {
                        r = newColor.r, g = newColor.g, b = newColor.b, a = 1,
                    })
                    refreshColor()
                end,
                onCancel   = function(prev)
                    setChannelColor(option.key, prev)
                    refreshColor()
                end,
            })
        end)

        local resetBtn = self:CreateResetButton(parent, 208, y + 1, function()
            local def = self:GetDefaultPath({ "EditBox", "ChannelTextColors", option.key })
            if IsColorTable(def) then
                setChannelColor(option.key, CopyColor(def))
                refreshRows()
            end
        end)
        resetBtn:SetSize(50, 20)
        resetBtn:SetText("Def")
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 208, y + 1)

        local masterCb = self:AcquireWidget("CheckBoxSmall", parent, "UICheckButtonTemplate", "CheckButton")
        masterCb:SetPoint("TOPLEFT", parent, "TOPLEFT", 258, y)

        local overrideCb = self:AcquireWidget("CheckBoxSmall", parent, "UICheckButtonTemplate", "CheckButton")
        overrideCb:SetPoint("TOPLEFT", parent, "TOPLEFT", 328, y)

        masterCb:SetScript("OnClick", function(selfFrame)
            if selfFrame:GetChecked() then
                self:SetLocalPath({ "EditBox", "ChannelColorMaster" }, option.key)
                self:SetLocalPath({ "EditBox", "ChannelColorOverrides", option.key }, false)
            else
                self:SetLocalPath({ "EditBox", "ChannelColorMaster" }, "")
            end
            refreshRows()
        end)

        overrideCb:SetScript("OnClick", function(selfFrame)
            if getMaster() == option.key then
                selfFrame:SetChecked(false)
                return
            end
            self:SetLocalPath(
                { "EditBox", "ChannelColorOverrides", option.key },
                selfFrame:GetChecked() == true
            )
            refreshRows()
        end)

        self:AddControl(colorBtn)
        self:AddControl(masterCb)
        self:AddControl(overrideCb)
        rows[#rows + 1] = {
            key = option.key,
            master = masterCb,
            override = overrideCb,
            refreshColor = refreshColor,
        }

        cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_ROW))
        y = cursor:Y()
    end

    refreshRows()
    cursor:Pad(10)
end

function Interface:CreateQueueDiagnostics(parent, cursor)
    local y = cursor:Y()
    self:CreateLabel(
        parent,
        "Queue Diagnostics",
        LAYOUT.WINDOW_PADDING,
        y,
        400,
        "Live state for the event-driven send pipeline.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    local frame = self:AcquireWidget("QueueDiagnosticsFrame", parent, nil, "Frame")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, cursor:Y())
    frame:SetSize(520, 10)
    self:AddControl(frame)

    local refreshBtn = self:AcquireWidget("QueueDiagnosticsRefresh", parent, "UIPanelButtonTemplate", "Button")
    refreshBtn:SetSize(78, 20)
    refreshBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING + 360, cursor:Y() - 2)
    refreshBtn:SetText("Refresh")
    self:AddControl(refreshBtn)

    local rows = {
        { label = "Active", key = "active" },
        { label = "Policy", key = "policyClass" },
        { label = "Chat Type", key = "chatType" },
        { label = "Expected Ack", key = "expectedAckEvent" },
        { label = "Pending Chunks", key = "pending" },
        { label = "In Flight", key = "inFlight" },
        { label = "Needs Continue", key = "needsContinue" },
        { label = "Strict Ack Match", key = "strictAck" },
    }

    local rowHeight = self:ScaledRow(22)
    local rowY = 0

    for _, row in ipairs(rows) do
        local labelFs = self:AcquireWidget("QueueDiagLabel", frame, "GameFontHighlightSmall", "FontString")
        labelFs:SetFontObject("GameFontHighlightSmall")
        labelFs:SetTextColor(0.85, 0.85, 0.85, 1)
        labelFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -rowY)
        labelFs:SetText(row.label .. ":")
        self:AddControl(labelFs)

        local valueFs = self:AcquireWidget("QueueDiagValue", frame, "GameFontHighlightSmall", "FontString")
        valueFs:SetFontObject("GameFontHighlightSmall")
        valueFs:SetTextColor(1, 1, 1, 1)
        valueFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -rowY)
        valueFs:SetText("-")
        self:AddControl(valueFs)

        row._value = valueFs
        rowY = rowY + rowHeight
    end

    frame._yDiagRows = rows
    frame._yNextUpdate = 0

    local function formatValue(value)
        if value == nil then return "-" end
        if type(value) == "boolean" then
            return value and "Yes" or "No"
        end
        return tostring(value)
    end

    local function RefreshQueueDiagnostics(selfFrame)
        local q = YapperTable.Queue
        local snapshot = q and q.GetActivePolicySnapshot and q:GetActivePolicySnapshot() or {}

        for _, row in ipairs(selfFrame._yDiagRows) do
            local value = nil
            if row.key == "needsContinue" then
                value = q and q.NeedsContinue or false
            elseif row.key == "strictAck" then
                value = q and q.StrictAckMatching or false
            else
                value = snapshot[row.key]
            end
            row._value:SetText(formatValue(value))
        end
    end

    refreshBtn:SetScript("OnClick", function()
        RefreshQueueDiagnostics(frame)
    end)

    frame:SetScript("OnUpdate", function(selfFrame, elapsed)
        if Interface.IsVisible ~= true or Interface._activeCategory ~= "diagnostics" then
            return
        end

        selfFrame._yNextUpdate = (selfFrame._yNextUpdate or 0) - elapsed
        if selfFrame._yNextUpdate > 0 then return end
        selfFrame._yNextUpdate = 0.2
        RefreshQueueDiagnostics(selfFrame)
    end)

    cursor:Advance(rowY)
    cursor:Pad(10)
end

function Interface:CreateCreditsPage(parent, cursor)
    self:CreateLabel(
        parent,
        "Credits",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        500,
        "Things used by Yapper and their licenses.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    self:CreateLabel(
        parent,
        "Spellcheck Dictionaries",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        500,
        "Spellcheck wordlists are derived from Hunspell dictionaries.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    local function addLine(text)
        local fs = self:AcquireWidget("CreditsLine", parent, "GameFontHighlightSmall", "FontString")
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(0.9, 0.9, 0.9, 1)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, cursor:Y())
        fs:SetWidth(520)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text)
        self:AddControl(fs)
        cursor:Advance(self:ScaledRow(18))
    end

    addLine("Source: https://github.com/wooorm/dictionaries")
    addLine("Each dictionary retains its original license. See dictionaries/<code>/license in the source repo.")
    cursor:Pad(6)

    addLine("Bundled dictionaries:")
    for _, entry in ipairs(CREDITS_DICTIONARIES_BUNDLED) do
        addLine(string.format(
            "%s (%s) - %s - %s",
            entry.locale,
            entry.label,
            entry.package,
            entry.license
        ))
    end

    cursor:Pad(6)
    addLine("Optional dictionary addons:")
    addLine("Install the locale addon to enable it in Yapper settings.")
    addLine("Addon naming: Yapper_Dict_<locale> (example: Yapper_Dict_frFR).")
    for _, entry in ipairs(CREDITS_DICTIONARIES_OPTIONAL) do
        addLine(string.format(
            "%s (%s) - %s - %s",
            entry.locale,
            entry.label,
            entry.package,
            entry.license
        ))
    end

    cursor:Pad(10)
end

function Interface:CreateTextInput(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local edit = self:AcquireWidget("InputBox", parent, "InputBoxTemplate", "EditBox")
    edit:SetAutoFocus(false)
    edit:SetSize(160, 22)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CONTROL_X, y)

    local current = self:GetConfigPath(path)
    if current ~= nil then
        -- For chat marker fields, show the trimmed marker (no added spacing)
        if JoinPath(path) == "Chat.DELINEATOR" or JoinPath(path) == "Chat.PREFIX" then
            edit:SetText(TrimString(current))
        else
            edit:SetText(tostring(current))
        end
    else
        edit:SetText("")
    end

    -- Commit on enter/focus loss, preserving numeric paths as numbers.
    local function commit()
        local defaults = self:GetDefaultsRoot()
        local cursor = defaults
        for i = 1, #path do
            if type(cursor) ~= "table" then break end
            cursor = cursor[path[i]]
        end

        local raw = edit:GetText() or ""
        if type(cursor) == "number" then
            local num = tonumber(raw)
            if num ~= nil then
                local stored = Interface:SetLocalPath(path, num)
                if JoinPath(path) == "FrameSettings.MouseWheelStepRate" then
                    Interface.MouseWheelStepRate = num
                end
                if stored ~= nil then
                    edit:SetText(tostring(stored))
                end
            end
        else
            local stored = Interface:SetLocalPath(path, raw)
            if type(stored) == "string" then
                -- For marker fields, display the trimmed marker to the user
                if JoinPath(path) == "Chat.DELINEATOR" or JoinPath(path) == "Chat.PREFIX" then
                    edit:SetText(TrimString(stored))
                else
                    edit:SetText(stored)
                end
            end
        end
    end

    edit:SetScript("OnEnterPressed", function(selfFrame)
        commit()
        selfFrame:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        commit()
    end)

    self:AddControl(edit)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return edit
end

function Interface:CreateColorPickerControl(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))
    local fullPath = JoinPath(path)

    local btn = self:AcquireWidget("ColorPickerButton", parent, "UIPanelButtonTemplate", "Button")
    btn:SetSize(120, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CONTROL_X, y)

    local swatch = btn.swatch
    if not swatch then
        swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("LEFT", btn, "LEFT", 6, 0)
        swatch:SetSize(16, 16)
        swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
        btn.swatch = swatch
    end

    local labelFS = btn.labelFS
    if not labelFS then
        labelFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelFS:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        labelFS:SetText("Pick colour")
        btn.labelFS = labelFS
    end

    -- Keep swatch in sync with live config state.
    local function refreshSwatch()
        local color = self:GetConfigPath(path) or { r = 1, g = 1, b = 1, a = 1 }
        if IsColorTable(color) then
            swatch:SetVertexColor(color.r, color.g, color.b, color.a or 1)
        else
            swatch:SetVertexColor(1, 1, 1, 1)
        end
        if fullPath == "EditBox.TextColor" then
            self:UpdateOverrideTextColorCheckboxState()
        end
    end

    local function applyStoredColor(colorValue)
        Interface:SetLocalPath(path, colorValue)
        refreshSwatch()
    end

    btn:SetScript("OnClick", function()
        local color = self:GetConfigPath(path) or { r = 1, g = 1, b = 1, a = 1 }
        if not IsColorTable(color) then
            color = { r = 1, g = 1, b = 1, a = 1 }
        end
        color.a = Clamp01(color.a, 1)

        OpenColorPicker({
            color      = CopyColor(color),
            hasOpacity = true,
            onApply    = function(newColor) applyStoredColor(newColor) end,
            onCancel   = function(prev) applyStoredColor(CopyColor(prev)) end,
        })
    end)

    Interface:CreateResetButton(parent, LAYOUT.RESET_X, y, function()
        local defaultColor = Interface:GetDefaultPath(path)
        if IsColorTable(defaultColor) then
            applyStoredColor(CopyColor(defaultColor))
        end
    end)

    refreshSwatch()
    self:AddControl(btn)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_COLOR_PICKER))
    return btn
end

function Interface:CreateFontSizeDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local slider = self:AcquireWidget("Slider", parent, "OptionsSliderTemplate", "Slider")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y)
    slider:SetWidth(146)
    slider:SetHeight(20)
    slider:SetMinMaxValues(8, 64)
    slider:SetValueStep(2)
    slider:SetObeyStepOnDrag(true)

    local current = RoundToEven(self:GetConfigPath(path))
    slider:SetValue(current)
    slider._lastSaved = current

    local sliderName = slider:GetName()
    local low = sliderName and _G[sliderName .. "Low"] or nil
    local high = sliderName and _G[sliderName .. "High"] or nil
    local text = sliderName and _G[sliderName .. "Text"] or nil
    if low then low:SetText(""); low:Hide() end
    if high then high:SetText(""); high:Hide() end
    if text then text:SetText(""); text:Hide() end

    local valueFs = self:AcquireWidget("Label", parent, "GameFontHighlightSmall", "FontString")
    valueFs:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    valueFs:SetText(tostring(current))

    local fontPad = self:GetUIFontOffset()
    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 155, y - 26 - fontPad)
    UIDropDownMenu_SetWidth(dd, 126)
    UIDropDownMenu_SetText(dd, tostring(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        for size = 8, 64, 2 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tostring(size)
            info.func = function()
                UIDropDownMenu_SetText(frame, tostring(size))
                slider:SetValue(size)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Slider is source of truth; dropdown mirrors and can drive slider updates.
    slider:SetScript("OnValueChanged", function(selfFrame, value)
        local even = RoundToEven(value)
        if selfFrame:GetValue() ~= even then
            selfFrame:SetValue(even)
            return
        end
        valueFs:SetText(tostring(even))
        UIDropDownMenu_SetText(dd, tostring(even))
        if selfFrame._lastSaved ~= even then
            Interface:SetLocalPath(path, even)
            selfFrame._lastSaved = even
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 44 - fontPad, function()
        local defaultSize = RoundToEven(Interface:GetDefaultPath(path))
        slider:SetValue(defaultSize)
        UIDropDownMenu_SetText(dd, tostring(defaultSize))
    end)
    self:AttachTooltip(resetBtn, "Reset font size to default.")

    -- Ensure the initial value is persisted and all controls are in sync.
    slider:SetValue(current)

    self:AddControl(slider)
    self:AddControl(valueFs)
    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_FONT_SIZE))
    return slider
end

function Interface:CreateFontOutlineDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 140)

    local current = NormalizeFontFlags(self:GetConfigPath(path))
    UIDropDownMenu_SetText(dd, GetFontFlagsLabel(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.checked = (option.value == current)
            info.func = function()
                current = option.value
                Interface:SetLocalPath(path, option.value)
                UIDropDownMenu_SetText(frame, option.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_FONT_OUTLINE))
    return dd
end

function Interface:CreateSpellcheckLocaleDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path)
    if not current or current == "" then
        current = (GetLocale and GetLocale()) or "enUS"
    end
    UIDropDownMenu_SetText(dd, tostring(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local locales = {}
        local spell = YapperTable and YapperTable.Spellcheck
        if spell and spell.GetKnownLocales then
            locales = spell:GetKnownLocales()
        elseif spell and spell.GetAvailableLocales then
            locales = spell:GetAvailableLocales()
        end
        if #locales == 0 then
            locales = { current }
        end

        for _, locale in ipairs(locales) do
            local info = UIDropDownMenu_CreateInfo()
            local available = spell and spell.IsLocaleAvailable and spell:IsLocaleAvailable(locale)
            local canLoad = spell and spell.CanLoadLocale and spell:CanLoadLocale(locale)
            local labelText = locale

            if not available then
                if canLoad then
                    labelText = locale .. " (load addon)"
                else
                    labelText = locale .. " (addon missing)"
                end
            end

            info.text = labelText
            info.checked = (locale == current)
            info.disabled = (not available and not canLoad)
            info.func = function()
                if spell and spell.EnsureLocale then
                    if not spell:EnsureLocale(locale) then
                        if spell.Notify then
                            spell:Notify("Yapper: install the " .. (spell:GetLocaleAddon(locale) or "") .. " addon to use " .. locale .. ".")
                        end
                        return
                    end
                end
                current = locale
                Interface:SetLocalPath(path, locale)
                UIDropDownMenu_SetText(frame, locale)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:CreateSpellcheckUnderlineDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path)
    if current ~= "highlight" then
        current = "line"
    end

    local function labelFor(value)
        if value == "highlight" then
            return "Highlight"
        end
        return "Underline"
    end

    UIDropDownMenu_SetText(dd, labelFor(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local options = {
            { value = "line", label = "Underline" },
            { value = "highlight", label = "Highlight" },
        }

        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.checked = (option.value == current)
            info.func = function()
                current = option.value
                Interface:SetLocalPath(path, option.value)
                UIDropDownMenu_SetText(frame, option.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:CreateThemeDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path) or (YapperTable.Theme and YapperTable.Theme._current)
    UIDropDownMenu_SetText(dd, tostring(current or "Default"))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local names = { }
        if YapperTable and YapperTable.GetRegisteredThemes then
            names = YapperTable:GetRegisteredThemes()
        elseif YapperTable and YapperTable.Theme and YapperTable.Theme.GetRegisteredNames then
            names = YapperTable.Theme:GetRegisteredNames()
        end

        -- Ensure there's at least the default entry.
        if #names == 0 then names = { "Yapper Default" } end

        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == current)
            info.func = function()
                current = name
                Interface:SetLocalPath(path, name)
                pcall(function()
                    if YapperTable and YapperTable.Utils and YapperTable.Utils.VerbosePrint then
                        YapperTable.Utils:VerbosePrint("Interface: theme selected -> " .. tostring(name))
                    end
                end)
                UIDropDownMenu_SetText(frame, name)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:BuildConfigUI()
    local frame = self.MainWindowFrame
    if not frame or not frame.ContentFrame then return end

    self:ClearConfigControls()

    -- Reset scroll position when rebuilding (e.g. category switch).
    if frame.ScrollFrame then
        frame.ScrollFrame:SetVerticalScroll(0)
        if frame.ScrollFrame.ScrollBar then
            frame.ScrollFrame.ScrollBar:SetValue(0)
        end
    end

    local schema    = self:GetRenderSchema()
    local catId     = self._activeCategory or "general"
    local activeCat = nil
    for _, c in ipairs(CATEGORIES) do
        if c.id == catId then activeCat = c; break end
    end
    if not activeCat then activeCat = CATEGORIES[1] end

    -- Build a set of paths owned by this category for fast lookup.
    local catPaths = {}
    if activeCat.paths then
        for _, p in ipairs(activeCat.paths) do
            catPaths[p] = true
        end
    end

    -- Custom flags for conditional blocks.
    local customSet = {}
    if activeCat.custom then
        for _, c in ipairs(activeCat.custom) do
            customSet[c] = true
        end
    end

    -- Small autosave hint at the top of every page.
    local autosaveLabel = self:CreateLabel(
        frame.ContentFrame,
        "Settings are saved automatically.",
        LAYOUT.WINDOW_PADDING,
        -6,
        500,
        self:GetTooltip("HEADER.AUTOSAVE")
    )
    autosaveLabel:SetFontObject(GameFontHighlightSmall)

    -- Dynamic content begins below the fixed header area.
    -- Push further down when font is scaled up so the autosave label has room.
    local cursor = LayoutCursor.New(LAYOUT.CONTENT_START_Y - self:GetUIFontOffset())

    -- Render schema items that belong to this category, preserving render
    -- order but skipping anything not claimed by the active category.
    for _, item in ipairs(schema) do
        if item.kind ~= "section" and catPaths[item.full] then
            -- Verify the key actually exists in DEFAULTS so we never render
            -- a control for a removed setting.
            local existsInDefaults = self:GetDefaultsRoot()
            local defaultsCursor = existsInDefaults
            for i = 1, #item.path do
                if type(defaultsCursor) ~= "table" then
                    defaultsCursor = nil
                    break
                end
                defaultsCursor = defaultsCursor[item.path[i]]
            end

            if defaultsCursor ~= nil then
                if item.kind == "boolean" then
                    self:CreateCheckBox(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "text" then
                    self:CreateTextInput(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "color" then
                    self:CreateColorPickerControl(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "fontsize" then
                    self:CreateFontSizeDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "fontflags" then
                    self:CreateFontOutlineDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "spellcheck_locale" then
                    self:CreateSpellcheckLocaleDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "spellcheck_underline" then
                    self:CreateSpellcheckUnderlineDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "theme" then
                    self:CreateThemeDropdown(
                        frame.ContentFrame,
                        "Active Theme",
                        item.path,
                        cursor
                    )
                end
            end
        end
    end

    ----- Custom blocks appended per-category -----

    -- Border colour: only when active theme declares a border.
    if customSet["borderColor"] then
        local activeThemeName = self:GetConfigPath({ "System", "ActiveTheme" })
            or (YapperTable.Theme and YapperTable.Theme._current)
        if activeThemeName and YapperTable and YapperTable.Theme then
            local t = YapperTable.Theme:GetTheme(activeThemeName)
            if type(t) == "table" and t.border == true then
                self:CreateColorPickerControl(
                    frame.ContentFrame,
                    "Border Colour",
                    { "EditBox", "BorderColor" },
                    cursor
                )
            end
        end
    end

    -- Channel colour overrides.
    if customSet["channelOverrides"] then
        if type(self:GetDefaultPath({ "EditBox", "ChannelColorOverrides" })) == "table" then
            self:CreateChannelOverrideControls(frame.ContentFrame, cursor)
        end
    end

    -- Queue diagnostics.
    if customSet["queueDiagnostics"] then
        self:CreateQueueDiagnostics(frame.ContentFrame, cursor)
    end

    -- Credits.
    if customSet["credits"] then
        self:CreateCreditsPage(frame.ContentFrame, cursor)
    end

    -- Message Bridges.
    if customSet["bridges"] then
        cursor:Pad(10)
        self:CreateLabel(
            frame.ContentFrame,
            "Message Bridges",
            LAYOUT.WINDOW_PADDING,
            cursor:Y(),
            500,
            "Enable or disable integration with third-party protocols.",
            "GameFontNormal"
        )
        cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

        self:CreateCheckBox(
            frame.ContentFrame,
            FRIENDLY_LABELS["System.EnableGopherBridge"],
            { "System", "EnableGopherBridge" },
            cursor
        )

        -- Visible warning note for Gopher toggle.
        local gopherWarning = self:CreateLabel(
            frame.ContentFrame,
            "BAD IDEA: Disabling this while using Gopher-powered addons (CrossRP, etc.) will cause stalls.",
            LAYOUT.WINDOW_PADDING + 28,
            cursor:Y() + 4,
            460
        )
        gopherWarning:SetFontObject(GameFontHighlightSmall)
        gopherWarning:SetTextColor(1, 0.4, 0.4, 1) -- Light red warning colour.
        cursor:Advance(14)

        self:CreateCheckBox(
            frame.ContentFrame,
            FRIENDLY_LABELS["System.EnableTypingTrackerBridge"],
            { "System", "EnableTypingTrackerBridge" },
            cursor
        )
    end

    -- Finish layout and size the content child so the scroll range is correct.
    cursor:Pad(20)
    frame.ContentFrame:SetHeight(math.abs(cursor:Y()) + 20)
    frame.ScrollFrame:UpdateScrollChildRect()

    -- Apply UI font scaling and refresh the sidebar size readout.
    self:RefreshFontScaleLabel()
    self:ApplyUIFontScale()
end

function Interface:ShowMainWindow()
    if not Interface.MainWindowFrame then
        Interface:Init()
    end
    Interface:ApplyMainWindowPosition(Interface.MainWindowFrame)
    Interface.MainWindowFrame:Show()
end

function Interface:ToggleMainWindow()
    if not Interface.MainWindowFrame then
        Interface:Init()
    end
    if Interface.MainWindowFrame:IsShown() then
        Interface:CloseFrame(Interface.MainWindowFrame)
    else
        Interface:ApplyMainWindowPosition(Interface.MainWindowFrame)
        Interface.MainWindowFrame:Show()
    end
end

local function NormalizeMouseButton(button)
    if type(button) == "number" then
        if button == 2 then return "RightButton" end
        if button == 1 then return "LeftButton" end
        return nil
    end

    if type(button) ~= "string" then return nil end
    local b = string.lower(button)
    if b == "rightbutton" or b == "rightbuttonup" then
        return "RightButton"
    end
    if b == "leftbutton" or b == "leftbuttonup" then
        return "LeftButton"
    end
    return nil
end

function Interface:HandleLauncherClick(mouseButton)
    NormalizeMouseButton(mouseButton)
    Interface:ToggleMainWindow()
end

function Yapper_FromCompartment(...)
    local button
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local normalized = NormalizeMouseButton(v)
        if normalized then
            button = normalized
            break
        end
    end
    Interface:HandleLauncherClick(button)
end

function Interface:CloseFrame(frame)
    if not frame or not frame:IsObjectType("Frame") then
        YapperTable.Utils:DebugPrint("Attempted to close an undefined frame.")
        return
    end
    self:SaveMainWindowPosition(frame)
    self:OnWindowClosed()
    frame:Hide()
end

-- Instantiation --
function Interface:Init()
    Interface:SanitizeLocalConfig()
    Interface:CreateMainWindow()
    Interface:BuildConfigUI()

    -- Then we're gonna hook into Show() and Hide() to track visibility.
    hooksecurefunc(Interface.MainWindowFrame, "Show", function()
        Interface.IsVisible = true -- Set visibility to true.
    end)
    hooksecurefunc(Interface.MainWindowFrame, "Hide", function()
        Interface.IsVisible = false
        Interface:OnWindowClosed()
    end)

    -- Create the launcher (Addon Compartment preferred, LDB fallback).
    Interface:CreateLauncher()
end

-- Create a launcher (Addon Compartment preferred, LDB fallback)
function Interface:CreateLauncher()
    if self.LauncherCreated then return end

    local tooltipLines = self:GetLauncherTooltipLines()

    -- Add to addon compartment if exists.
    ---@diagnostic disable: undefined-global
    local compartment = AddonCompartmentFrame or AddonCompartment
    if type(compartment) == "table" and type(compartment.RegisterAddon) == "function" then
        local ok, err = pcall(function()
            compartment:RegisterAddon({
                text = YapperName,
                icon = "6624474", -- fileID icon
                registerForAnyClick = true,
                func = Yapper_FromCompartment,
                funcOnEnter = function(menuItem)
                    GameTooltip:SetOwner(menuItem, "ANCHOR_BOTTOMLEFT", -15, 20)
---@diagnostic disable-next-line: missing-parameter
                    GameTooltip:SetText(YapperName)
                    GameTooltip:AddLine(" ")
                    for _, line in ipairs(tooltipLines) do
                        GameTooltip:AddLine("|cFF00FF00" .. line .. "|r")
                    end
                    GameTooltip:Show()
                end,
                funcOnLeave = function()
                    GameTooltip:Hide()
                end,
            })
        end)
        if not ok then
            -- don't fail silently
            YapperTable.Utils:DebugPrint(YapperName .. ": AddonCompartment register failed:", tostring(err))
        end
    end

    -- Minimap button implement via LibStub if available.
    local ldb = _G.LibStub and _G.LibStub("LibDataBroker-1.1", true)
    if ldb then
        if not self.MinimapLDBObject then
            self.MinimapLDBObject = ldb:NewDataObject(YapperName, {
                type = "launcher",
                icon = "6624474", -- fileID string
                OnClick = function(_, button)
                    Interface:HandleLauncherClick(button)
                end,
                OnTooltipShow = function(tt)
                    tt:AddLine(YapperName)
                    tt:AddLine(" ")
                    for _, line in ipairs(tooltipLines) do
                        tt:AddLine(line, 0.6, 0.6, 0.6)
                    end
                end,
            })
        end

        local DBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
        if DBIcon then
            self.DBIcon = DBIcon
            local minimapCfg = self:GetMinimapButtonSettings()
            pcall(function()
                DBIcon:Register(YapperName, self.MinimapLDBObject, minimapCfg)
            end)
            self:ApplyMinimapButtonVisibility()
            self.LauncherCreated = true
            return
        end
    end

    -- Manual minimap button fallback when LibStub/DBIcon are unavailable.
    if _G.Minimap then
        if not self.MinimapButton then
            local btn = CreateFrame("Button", "YapperMinimapButton", _G.Minimap)
            btn:SetSize(32, 32)
            btn:SetFrameStrata("MEDIUM")
            btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:RegisterForDrag("LeftButton")

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("6624474")
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            icon:SetAllPoints(btn)

            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            border:SetAllPoints(btn)

            btn:SetScript("OnClick", function(_, button)
                Interface:HandleLauncherClick(button)
            end)
            btn:SetScript("OnDragStart", function(selfFrame)
                selfFrame:SetScript("OnUpdate", function()
                    Interface:UpdateMinimapButtonAngleFromCursor()
                end)
            end)
            btn:SetScript("OnDragStop", function(selfFrame)
                selfFrame:SetScript("OnUpdate", nil)
            end)
            btn:SetScript("OnEnter", function(selfFrame)
                GameTooltip:SetOwner(selfFrame, "ANCHOR_TOPLEFT")
                GameTooltip:SetText(YapperName)
                GameTooltip:AddLine(" ")
                for _, line in ipairs(tooltipLines) do
                    GameTooltip:AddLine(line, 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            self.MinimapButton = btn
            self:PositionMinimapButton()
        end

        self:ApplyMinimapButtonVisibility()
    end

    self.LauncherCreated = true
end
