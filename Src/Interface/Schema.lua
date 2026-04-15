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

-- Re-localise Lua globals.
local type       = type
local ipairs     = ipairs
local pairs      = pairs
local table_sort = table.sort

local COLOUR_KEYS                   = {
    InputBg = true,
    LabelBg = true,
    TextColor = true,
    BorderColor = true,
    ShadowColor = true,
    UnderlineColor = true,
    HighlightColor = true,
}

local CHANNEL_OVERRIDE_OPTIONS      = {
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

local CREDITS_DICTIONARIES_BUNDLED  = {
    { locale = "enUS", label = "English (US)", package = "dictionary-en",    license = "MIT AND BSD" },
    { locale = "enGB", label = "English (UK)", package = "dictionary-en-GB", license = "MIT AND BSD" },
}

local CREDITS_DICTIONARIES_OPTIONAL = {
    { locale = "frFR", label = "French",              package = "dictionary-fr",    license = "MPL-2.0" },
    { locale = "deDE", label = "German",              package = "dictionary-de",    license = "GPL-2.0 OR GPL-3.0" },
    { locale = "esES", label = "Spanish",             package = "dictionary-es",    license = "GPL-3.0 OR LGPL-3.0 OR MPL-1.1" },
    { locale = "esMX", label = "Spanish (Mexico)",    package = "dictionary-es-MX", license = "GPL-3.0 OR LGPL-3.0 OR MPL-1.1" },
    { locale = "itIT", label = "Italian",             package = "dictionary-it",    license = "GPL-3.0" },
    { locale = "ptBR", label = "Portuguese (Brazil)", package = "dictionary-pt",    license = "LGPL-3.0 OR MPL-2.0" },
    { locale = "ruRU", label = "Russian",             package = "dictionary-ru",    license = "BSD-3-Clause" },
}

-- Friendly dropdown values for font outline modes.
local FONT_OUTLINE_OPTIONS          = {
    { value = "",             label = "Default (None)" },
    { value = "OUTLINE",      label = "Outline" },
    { value = "THICKOUTLINE", label = "Thick Outline" },
}

-- Tooltip copy keyed by setting path / synthetic header keys.
local SETTING_TOOLTIPS              = {
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
    ["Spellcheck.Locale"] =
    "Select the dictionary locale to use for spellchecking. Warning: some locales (for example German) include very large word lists and may take many seconds to load or increase /reload time and memory usage.",
    ["Spellcheck.KeyboardLayout"] =
    "Specify your physical keyboard layout (QWERTY, QWERTZ, or AZERTY) to improve suggestion accuracy by accounting for physical key proximity.",
    ["Spellcheck.UnderlineStyle"] = "Choose between straight underline or highlight style.",
    ["Spellcheck.MinWordLength"] = "Ignore words shorter than this length.",
    ["Spellcheck.UnderlineColor"] = "Change the colour of the standard spellcheck underline.",
    ["Spellcheck.HighlightColor"] = "Change the colour of the spellcheck highlight style.",
    ["Spellcheck.MaxCandidates"] = "Limit how many candidate words are checked (higher = more accurate, slower).",
    ["Spellcheck.MaxSuggestions"] = "Maximum number of suggestions shown (1-4).",
    ["Spellcheck.YALLMFreqCap"] = "Maximum number of unique vocabulary words YALLM tracks. Older and less-used words are pruned first when this cap is hit.",
    ["Spellcheck.YALLMBiasCap"] = "Maximum number of typo→correction pairs stored by YALLM. Lower-utility pairs are pruned first.",
    ["Spellcheck.YALLMAutoThreshold"] = "How many times you must send a word before YALLM automatically adds it to your personal dictionary.",
    ["Spellcheck.NgramKeyCapSize"] =
    "Maximum number of unique n-gram index keys built when loading the dictionary. Higher values improve suggestion recall for uncommon words but directly increase memory usage by roughly 1-2 MB per 10,000 extra keys. Set to 0 to remove the cap entirely (maximum accuracy, higher memory cost).",
    ["Chat.USE_DELINEATORS"] = "Add marker text between split chunks.",
    ["Chat.DELINEATOR"] = "Single marker token used for both suffix and prefix; spacing is auto-managed.",
    ["Chat.MAX_HISTORY_LINES"] = "How many previous messages are kept in local history.",
    ["EditBox.InputBg"] = "Background colour of the input area.",
    ["EditBox.LabelBg"] = "Background colour for the channel label area.",
    ["EditBox.TextColor"] = "Colour for the typed text.",
    ["EditBox.BorderColor"] = "Colour for the active channel border outline (when enabled).",
    ["EditBox.FontSize"] = "Size of the font in the chat box.",
    ["EditBox.FontFlags"] = "Visual outline or monochrome styling for the font.",
    ["EditBox.RoundedCorners"] =
    "Use a fully rounded backdrop for the chat overlay instead of simple flat textures. May potentially be flattened by other addons.",
    ["EditBox.Shadow"] = "Render a soft drop-shadow behind the chat overlay.",
    ["EditBox.ShadowSize"] = "Size/thickness of the drop-shadow rendering effect.",
    ["EditBox.ShadowColor"] = "Colour and base opacity of the drop-shadow effect.",
    ["EditBox.FontFace"] = "Custom font file path. Leave empty to use default font.",
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
    ["EditBox.StorytellerAutoExpand"] =
    "When enabled, the chat box smoothly slides and expands into multi-line mode as soon as your text reaches the edge of the screen. Great for long-form storyteller posts!",
    ["EditBox.StorytellerShowHint"] =
    "If automatic expansion is off, Yapper can show a subtle glow and a reminder text (once per session) to let you know you can trigger multi-line mode manually with your bind.",
    ["System.StorytellerSlideSpeed"] =
    "How fast the chat box should slide and expand when entering storyteller mode. Lower values are snappier.",
}

-- UI-only aliases to not scare the normies.
local FRIENDLY_LABELS               = {
    ["SECTION.Chat"] = "Message Sending",
    ["SECTION.EditBox"] = "Chat Input Appearance",
    ["SECTION.FrameSettings"] = "Window & Scrolling",
    ["FrameSettings.EnableMinimapButton"] = "Show minimap button",
    ["FrameSettings.MinimapButtonOffset"] = "Minimap button offset",
    ["Spellcheck.Enabled"] = "Enable spellcheck",
    ["Spellcheck.Locale"] = "Spellcheck locale",
    ["Spellcheck.KeyboardLayout"] = "Keyboard layout",
    ["Spellcheck.UnderlineStyle"] = "Underline style",
    ["Spellcheck.UnderlineColor"] = "Underline colour",
    ["Spellcheck.HighlightColor"] = "Highlight colour",
    ["Spellcheck.MinWordLength"] = "Minimum word length",
    ["Spellcheck.MaxSuggestions"] = "Max suggestions",
    ["Spellcheck.MaxCandidates"] = "Max word candidates checked",
    ["Spellcheck.YALLMFreqCap"] = "Vocabulary cap",
    ["Spellcheck.YALLMBiasCap"] = "Correction bias cap",
    ["Spellcheck.YALLMAutoThreshold"] = "Auto-learn threshold",
    ["Spellcheck.NgramKeyCapSize"] = "N-gram key cap (0 = uncapped)",
    ["System.EnableGopherBridge"] = "Enable Gopher Bridge",
    ["System.EnableTypingTrackerBridge"] = "Enable Typing Tracker Bridge",

    ["Chat.USE_DELINEATORS"] = "Add split marker",
    ["Chat.DELINEATOR"] = "Split marker text",
    ["Chat.MAX_HISTORY_LINES"] = "Saved message history",

    ["EditBox.InputBg"] = "Chat background",
    ["EditBox.LabelBg"] = "Channel label background",
    ["EditBox.TextColor"] = "Text colour",
    ["EditBox.BorderColor"] = "Border colour",
    ["EditBox.FontSize"] = "Font size",
    ["EditBox.FontFlags"] = "Font style",
    ["EditBox.RoundedCorners"] = "Rounded corners",
    ["EditBox.Shadow"] = "Enable drop shadow",
    ["EditBox.ShadowSize"] = "Shadow thickness",
    ["EditBox.ShadowColor"] = "Shadow colour",
    ["EditBox.FontFace"] = "Font file path",
    ["EditBox.AutoFitLabel"] = "Auto-fit long labels",
    ["EditBox.StickyChannel"] = "Remember last channel",
    ["EditBox.StickyGroupChannel"] = "Keep group channels sticky",
    ["EditBox.RecoverOnEscape"] = "Recover text after ESC",
    ["EditBox.MinHeight"] = "Minimum input height",
    ["EditBox.UseBlizzardSkinProxy"] = "Use Blizzard skin proxy",
    ["EditBox.BlizzardSkinProxyPad"] = "Skin proxy padding",
    ["EditBox.StorytellerAutoExpand"] = "Automatic expansion",
    ["EditBox.StorytellerShowHint"] = "Show storyteller mode hint",
    ["System.StorytellerSlideSpeed"] = "Animation duration",
}

-- ---------------------------------------------------------------------------
-- Category system -- each entry defines a sidebar tab and the settings it owns.
-- Settings are referenced by their JoinPath() key (e.g. "EditBox.FontSize").
-- A nil/empty `paths` list means "render nothing from the schema" (the page
-- builder can still emit custom controls).
-- ---------------------------------------------------------------------------
local CATEGORIES                    = {
    {
        id    = "general",
        label = "General",
        icon  = nil, -- reserved for future icon support
        paths = {
            -- Minimap button
            "FrameSettings.EnableMinimapButton",
            "FrameSettings.MinimapButtonOffset",
            -- Spellcheck
            "Spellcheck.Enabled",
            "Spellcheck.Locale",
            "Spellcheck.KeyboardLayout",
            "Spellcheck.UnderlineStyle",
            "Spellcheck.MaxCandidates",
            "Spellcheck.ReshuffleAttempts",
            "Spellcheck.MaxWrongLetters",
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
        id     = "appearance",
        label  = "Appearance",
        icon   = nil,
        paths  = {
            -- Theme
            "System.ActiveTheme",
            -- Visuals
            "EditBox.RoundedCorners",
            "EditBox.Shadow",
            "EditBox.ShadowSize",
            -- Colours
            "EditBox.InputBg",
            "EditBox.LabelBg",
            "EditBox.ShadowColor",
            "Spellcheck.UnderlineColor",
            "Spellcheck.HighlightColor",
            -- Font
            "EditBox.FontSize",
            "EditBox.FontFlags",
        },
        -- Channel override controls and border colour (conditional) are
        -- appended by custom logic inside the page builder.
        custom = { "channelOverrides", "borderColor" },
    },
    {
        id     = "advanced",
        label  = "Advanced",
        icon   = nil,
        paths  = {
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
            "Spellcheck.NgramKeyCapSize",
        },
        -- Bridges are appended by custom logic.
        custom = { "bridges", "spellcheckUserDict" },
    },
    {
        id     = "learning",
        label  = "Adaptive Learning",
        icon   = nil,
        paths  = {
            "Spellcheck.YALLMFreqCap",
            "Spellcheck.YALLMBiasCap",
            "Spellcheck.YALLMAutoThreshold",
        },
        custom = { "yallmLearning" },
    },
    {
        id     = "diagnostics",
        label  = "Diagnostics",
        icon   = nil,
        paths  = {},
        custom = { "queueDiagnostics" },
    },
    {
        id     = "credits",
        label  = "Credits",
        icon   = nil,
        paths  = {},
        custom = { "credits" },
    },
}

-- Quick lookup: path -> category id.
local PATH_TO_CATEGORY              = {}
for _, cat in ipairs(CATEGORIES) do
    if cat.paths then
        for _, p in ipairs(cat.paths) do
            PATH_TO_CATEGORY[p] = cat.id
        end
    end
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
                    if IsColourTable(value) and COLOUR_KEYS[key] then
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
        table_sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, key in ipairs(keys) do
            local value = tbl[key]
            local nextPath = ClonePath(path)
            nextPath[#nextPath + 1] = key

            if not shouldSkipPath(nextPath) then
                if type(value) == "table" then
                    if IsColourTable(value) and COLOUR_KEYS[key] then
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
                    elseif JoinPath(nextPath) == "Spellcheck.KeyboardLayout" then
                        kind = "spellcheck_keyboard_layout"
                    elseif JoinPath(nextPath) == "Spellcheck.UnderlineStyle" then
                        kind = "spellcheck_underline"
                    elseif JoinPath(nextPath) == "Spellcheck.NgramKeyCapSize" then
                        -- HIDDEN: No longer a user-facing setting but functionality remains
                        kind = "hidden"
                    end
                    if kind ~= "hidden" then
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
