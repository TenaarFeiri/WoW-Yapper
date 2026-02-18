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
}

local CHANNEL_OVERRIDE_OPTIONS = {
    { key = "SAY",           label = "Say" },
    { key = "YELL",          label = "Yell" },
    { key = "PARTY",         label = "Party" },
    { key = "WHISPER",       label = "Whisper" },
    { key = "INSTANCE_CHAT", label = "Instance" },
    { key = "RAID",          label = "Raid" },
    { key = "RAID_WARNING",  label = "Raid Warning" },
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
    ["Chat.USE_DELINEATORS"] = "Add marker text between split chunks.",
    ["Chat.DELINEATOR"] = "Single marker token used for both suffix and prefix; spacing is auto-managed.",
    ["Chat.MIN_POST_INTERVAL"] = "Minimum delay between sends.",
    ["Chat.POST_TIMEOUT"] = "How long to wait before a send attempt is considered stalled.",
    ["Chat.BATCH_SIZE"] = "How many chunks are sent per batch.",
    ["Chat.BATCH_THROTTLE"] = "Delay between chunk batches.",
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
    ["EditBox.MinHeight"] =
    "Sets a minimum height for the chat input box. Only takes effect if larger than the game's native editbox height.",
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
    ["System.EnableGopherBridge"] = "Enable Gopher Bridge",
    ["System.EnableTypingTrackerBridge"] = "Enable Typing Tracker Bridge",

    ["Chat.USE_DELINEATORS"] = "Add split marker",
    ["Chat.DELINEATOR"] = "Split marker text",
    ["Chat.MIN_POST_INTERVAL"] = "Minimum send delay",
    ["Chat.POST_TIMEOUT"] = "Send timeout",
    ["Chat.BATCH_SIZE"] = "Messages per batch",
    ["Chat.BATCH_THROTTLE"] = "Batch delay",
    ["Chat.MAX_HISTORY_LINES"] = "Saved message history",

    ["EditBox.InputBg"] = "Input background colour",
    ["EditBox.LabelBg"] = "Label background colour",
    ["EditBox.FontFace"] = "Font file path",
    ["EditBox.FontFlags"] = "Font outline mode",
    ["EditBox.FontSize"] = "Font size",
    ["EditBox.AutoFitLabel"] = "Auto-fit long labels",
    ["EditBox.StickyChannel"] = "Remember last channel",
    ["EditBox.StickyGroupChannel"] = "Keep group channels sticky",
    ["EditBox.MinHeight"] = "Minimum input height",
}

-- Paths hidden in Basic mode and shown in Advanced mode.
local ADVANCED_PATHS = {
    ["System.DEBUG"] = true,
    ["System.RUN_ALL_PATCHES"] = true,
    ["System.VERBOSE"] = true,
    ["Chat.MIN_POST_INTERVAL"] = true,
    ["Chat.POST_TIMEOUT"] = true,
    ["Chat.BATCH_SIZE"] = true,
    ["Chat.BATCH_THROTTLE"] = true,
    ["Chat.MAX_HISTORY_LINES"] = true,
    ["EditBox.FontFace"] = true,
    ["EditBox.MinHeight"] = true,
    ["System.EnableGopherBridge"] = true,
    ["System.EnableTypingTrackerBridge"] = true,
}

-- ---------------------------------------------------------------------------
-- Layout constants — every pixel value centralised in one place.
-- ---------------------------------------------------------------------------
local LAYOUT = {
    -- Main window
    WINDOW_WIDTH           = 420,
    WINDOW_HEIGHT          = 640,
    WINDOW_PADDING         = 8,
    SCROLLBAR_WIDTH        = 14,
    SCROLLBAR_GAP          = 2,
    TITLE_INSET            = 28,
    BOTTOM_BAR             = 36,

    -- Widget row heights
    ROW_CHECKBOX           = 30,
    ROW_TEXT_INPUT         = 30,
    ROW_COLOR_PICKER       = 30,
    ROW_FONT_OUTLINE       = 30,
    ROW_FONT_SIZE          = 84,
    ROW_SECTION            = 24,
    ROW_CHANNEL_ROW        = 26,
    ROW_CHANNEL_HEADER     = 22,
    ROW_CHANNEL_LABELS     = 16,

    -- Starting Y for dynamic content (below fixed header area)
    CONTENT_START_Y        = -68,

    -- Horizontal positions
    LABEL_X                = 10,
    LABEL_WIDTH            = 160,
    CONTROL_X              = 180,
    RESET_X                = 306,

    -- Close button
    CLOSE_BTN_WIDTH        = 120,
    CLOSE_BTN_HEIGHT       = 24,
    CLOSE_BTN_OFFSET_Y     = 10,

    -- Scrollbar fixed offsets
    SCROLLBAR_TOP_INSET    = 48,
    SCROLLBAR_BOTTOM_INSET = 44,
}

-- ---------------------------------------------------------------------------
-- LayoutCursor — replaces manual `y = y - N` tracking.
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

-- Compare two colours including alpha, with implicit alpha=1 fallback.
local function IsColorEqual(lhs, rhs)
    if not IsColorTable(lhs) or not IsColorTable(rhs) then
        return false
    end
    local la = lhs.a ~= nil and lhs.a or 1
    local ra = rhs.a ~= nil and rhs.a or 1
    return lhs.r == rhs.r and lhs.g == rhs.g and lhs.b == rhs.b and la == ra
end

-- Copy a color table safely, supplying sane defaults.
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

-- Normalize legacy/variant font flag values into known dropdown options.
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

function Interface:SettingsChanged()
    local root = self:GetLocalConfigRoot()
    return type(root.System) == "table" and root.System.SettingsHaveChanged == true
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

function Interface:IsTextColorDefault()
    local current = self:GetConfigPath({ "EditBox", "TextColor" })
    local default = self:GetDefaultPath({ "EditBox", "TextColor" })
    return IsColorEqual(current, default)
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
        _G.YapperDB.minimapbutton = { hide = false }
    end
    return _G.YapperDB.minimapbutton
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
end

function Interface:GetSettingsViewMode()
    -- Any unexpected value falls back to Basic to keep UI simple by default.
    local mode = self:GetConfigPath({ "FrameSettings", "SettingsViewMode" })
    if mode == "advanced" then
        return "advanced"
    end
    return "basic"
end

function Interface:GetFriendlyLabel(item)
    if not item then return "" end
    if item.kind == "section" then
        return FRIENDLY_LABELS["SECTION." .. item.full] or item.key
    end
    return FRIENDLY_LABELS[item.full] or item.key
end

-- Advanced filtering is path-driven so data model stays unchanged.
function Interface:IsAdvancedItem(item)
    if not item or item.kind == "section" then return false end
    return ADVANCED_PATHS[item.full] == true
end

function Interface:IsItemVisibleForMode(item, mode)
    if mode == "advanced" then return true end
    return not self:IsAdvancedItem(item)
end

local function IsDescendantPath(path, ancestor)
    -- True when path starts with ancestor and is deeper than it.
    if type(path) ~= "table" or type(ancestor) ~= "table" then return false end
    if #path <= #ancestor then return false end
    for i = 1, #ancestor do
        if path[i] ~= ancestor[i] then
            return false
        end
    end
    return true
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
        if full == "System.SettingsHaveChanged"
            or full == "System.VERSION"
            or full == "System.FRAME_ID_PARENT"
            or full == "FrameSettings.MouseWheelStepRate"
            or full == "FrameSettings.MainWindowPosition"
            or full == "FrameSettings.SettingsViewMode"
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
                or path[2] == "TextColor") then
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
local function CreateScrollableContent(parent)
    local P = LAYOUT
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    parent.ScrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", P.WINDOW_PADDING, -P.TITLE_INSET)
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
            "OnEditFocusLost", "OnEnterPressed", "OnChar", "OnTextChanged"
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

    pool[#pool + 1] = widget
end

function Interface:GetTooltip(key)
    return SETTING_TOOLTIPS[key]
end

function Interface:AttachTooltip(region, tooltipText)
    if not region or type(tooltipText) ~= "string" or tooltipText == "" then return end
    if region.EnableMouse then
        region:EnableMouse(true)
    end

    local function onEnter(selfFrame)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end

    local function onLeave()
        GameTooltip:Hide()
    end

    if region.HookScript then
        region:HookScript("OnEnter", onEnter)
        region:HookScript("OnLeave", onLeave)
    elseif region.SetScript then
        region:SetScript("OnEnter", onEnter)
        region:SetScript("OnLeave", onLeave)
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
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    self:AddControl(fs)
    self:AttachTooltip(fs, tooltipText)
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

    cursor:Advance(LAYOUT.ROW_CHECKBOX)
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

    cursor:Advance(LAYOUT.ROW_CHANNEL_HEADER)
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
        GameTooltip:SetText("Master Channel")
        GameTooltip:AddLine("Choose one channel as the colour source.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Channels with Override checked", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("use the master's colour.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    masterHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:AddControl(masterHelp)

    cursor:Advance(LAYOUT.ROW_CHANNEL_LABELS)
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

        cursor:Advance(LAYOUT.ROW_CHANNEL_ROW)
        y = cursor:Y()
    end

    refreshRows()
    cursor:Pad(10)
end

function Interface:CreateTextInput(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local edit = self:AcquireWidget("InputBox", parent, "InputBoxTemplate", "EditBox")
    edit:SetAutoFocus(false)
    edit:SetSize(180, 22)
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
    cursor:Advance(LAYOUT.ROW_TEXT_INPUT)
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
    cursor:Advance(LAYOUT.ROW_COLOR_PICKER)
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
    if low then low:SetText("8") end
    if high then high:SetText("64") end
    if text then text:SetText(tostring(current)) end

    local valueFs = self:AcquireWidget("Label", parent, "GameFontHighlightSmall", "FontString")
    valueFs:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    valueFs:SetText(tostring(current))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 155, y - 20)
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
        if text then text:SetText(tostring(even)) end
        valueFs:SetText(tostring(even))
        UIDropDownMenu_SetText(dd, tostring(even))
        if selfFrame._lastSaved ~= even then
            Interface:SetLocalPath(path, even)
            selfFrame._lastSaved = even
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 44, function()
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
    cursor:Advance(LAYOUT.ROW_FONT_SIZE)
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
    cursor:Advance(LAYOUT.ROW_FONT_OUTLINE)
    return dd
end

function Interface:BuildConfigUI()
    local frame = self.MainWindowFrame
    if not frame or not frame.ContentFrame then return end

    self:ClearConfigControls()

    local schema = self:GetRenderSchema()
    local autosaveLabel = self:CreateLabel(
        frame.ContentFrame,
        "Settings are saved automatically.",
        LAYOUT.WINDOW_PADDING,
        -8,
        360,
        self:GetTooltip("HEADER.AUTOSAVE")
    )
    autosaveLabel:SetFontObject(GameFontHighlightSmall)

    -- View mode toggle lives in header area and rebuilds UI on change.
    local mode = self:GetSettingsViewMode()
    local modeLabel = self:CreateLabel(
        frame.ContentFrame,
        "View",
        LAYOUT.WINDOW_PADDING,
        -30,
        72,
        self:GetTooltip("HEADER.VIEWMODE")
    )
    modeLabel:SetFontObject(GameFontHighlightSmall)

    local modeDd = self:AcquireWidget("Dropdown", frame.ContentFrame, "UIDropDownMenuTemplate", "Frame")
    modeDd:SetPoint("TOPLEFT", frame.ContentFrame, "TOPLEFT", 50, -38)
    UIDropDownMenu_SetWidth(modeDd, 110)
    UIDropDownMenu_SetText(modeDd, mode == "advanced" and "Advanced" or "Basic")
    UIDropDownMenu_Initialize(modeDd, function(dropdown, level)
        local basic = UIDropDownMenu_CreateInfo()
        basic.text = "Basic"
        basic.checked = (mode == "basic")
        basic.func = function()
            Interface:SetLocalPath({ "FrameSettings", "SettingsViewMode" }, "basic")
            Interface:BuildConfigUI()
        end
        UIDropDownMenu_AddButton(basic, level)

        local advanced = UIDropDownMenu_CreateInfo()
        advanced.text = "Advanced"
        advanced.checked = (mode == "advanced")
        advanced.func = function()
            Interface:SetLocalPath({ "FrameSettings", "SettingsViewMode" }, "advanced")
            Interface:BuildConfigUI()
        end
        UIDropDownMenu_AddButton(advanced, level)
    end)
    self:AddControl(modeDd)
    self:AttachTooltip(modeDd, self:GetTooltip("HEADER.VIEWMODE"))

    -- Dynamic content begins below the fixed header.
    local cursor = LayoutCursor.New(LAYOUT.CONTENT_START_Y)

    -- Prevent section labels from showing when all children are filtered out.
    local function sectionHasVisibleChildren(sectionIndex)
        local sectionItem = schema[sectionIndex]
        if not sectionItem or sectionItem.kind ~= "section" then return false end
        for idx = sectionIndex + 1, #schema do
            local candidate = schema[idx]
            if IsDescendantPath(candidate.path, sectionItem.path)
                and candidate.kind ~= "section"
                and Interface:IsItemVisibleForMode(candidate, mode) then
                return true
            end
        end
        return false
    end

    for index, item in ipairs(schema) do
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
            if item.kind == "section" then
                if sectionHasVisibleChildren(index) then
                    local label = self:CreateLabel(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        LAYOUT.WINDOW_PADDING,
                        cursor:Y(),
                        340,
                        self:GetTooltip("SECTION." .. item.full),
                        "GameFontNormal"
                    )
                    cursor:Advance(LAYOUT.ROW_SECTION)
                end
            elseif item.kind == "boolean" then
                if Interface:IsItemVisibleForMode(item, mode) then
                    local cb = self:CreateCheckBox(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                end
            elseif item.kind == "text" then
                if Interface:IsItemVisibleForMode(item, mode) then
                    self:CreateTextInput(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                end
            elseif item.kind == "color" then
                if Interface:IsItemVisibleForMode(item, mode) then
                    self:CreateColorPickerControl(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                end
            elseif item.kind == "fontsize" then
                if Interface:IsItemVisibleForMode(item, mode) then
                    self:CreateFontSizeDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                end
            elseif item.kind == "fontflags" then
                if Interface:IsItemVisibleForMode(item, mode) then
                    self:CreateFontOutlineDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                end
            end
        end
    end

    -- Manually append "Message Bridges" section at the bottom (Advanced only)
    if mode == "advanced" then
        cursor:Pad(10)
        self:CreateLabel(
            frame.ContentFrame,
            "Message Bridges",
            LAYOUT.WINDOW_PADDING,
            cursor:Y(),
            340,
            "Enable or disable integration with third-party protocols.",
            "GameFontNormal"
        )
        cursor:Advance(LAYOUT.ROW_SECTION)

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
            320
        )
        gopherWarning:SetFontObject(GameFontHighlightSmall)
        gopherWarning:SetTextColor(1, 0.4, 0.4, 1) -- Light red warning color.
        cursor:Advance(14)                         -- Extra space for the warning note.

        self:CreateCheckBox(
            frame.ContentFrame,
            FRIENDLY_LABELS["System.EnableTypingTrackerBridge"],
            { "System", "EnableTypingTrackerBridge" },
            cursor
        )
    end

    if type(self:GetDefaultPath({ "EditBox", "ChannelColorOverrides" })) == "table" then
        self:CreateChannelOverrideControls(frame.ContentFrame, cursor)
    end

    -- Finish layout
    cursor:Pad(20)
    frame.ContentFrame:SetHeight(math.abs(cursor:Y()) + 20)
    frame.ScrollFrame:UpdateScrollChildRect()
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

    self.LauncherCreated = true
end
