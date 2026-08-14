--[[
    Interface/HelpContent.lua
    User-facing Help page content. Rendering and layout live in Pages.lua.
]]

local _, YapperTable = ...

local HelpContent = {}
local ReadOnlyProxies = {}

local function ReadOnly(source, label)
    if type(source) ~= "table" then
        return source
    end

    local proxy = ReadOnlyProxies[source]
    if proxy then
        return proxy
    end

    proxy = {}
    ReadOnlyProxies[source] = proxy
    setmetatable(proxy, {
        __index = function(_, key)
            if key == "ForEach" then
                return function(callback)
                    if type(callback) ~= "function" then return end
                    for index, value in ipairs(source) do
                        callback(ReadOnly(value, label .. "[" .. index .. "]"), index)
                    end
                end
            end
            return ReadOnly(source[key], label .. "." .. tostring(key))
        end,
        __newindex = function()
            error(label .. " is read-only", 2)
        end,
        __metatable = "read-only",
    })
    return proxy
end

local function key(text)
    return { kind = "key", text = text }
end

local function heading(text)
    return { kind = "heading", text = text }
end

local function body(...)
    return { kind = "body", parts = { ... } }
end

local function separator()
    return { kind = "separator" }
end

HelpContent.Title = "How to use Yapper"
HelpContent.Subtitle = "A quick reference for Yapper's chat features."

-- Content helpers keep copy separate from rendering while preserving the
-- gold key labels used by the in-game Help page.
HelpContent.Items = {
    heading("Getting Started"),
    body("Press your normal Open Chat key (default ", key("Enter"), ") to start typing. "
        .. "Yapper opens its chat box when the addon is active."),
    body(key("Enter"), " — send the message. ", key("Escape"), " — close the chat box. "
        .. "If a menu or suggestion popup is open, Escape closes that first. Enter selects an open menu item."),
    body("While the Yapper chat box is open, ", key("Shift+Enter"), " expands it into the multiline editor. "
        .. "To use Blizzard's chat box instead, use the ", key("Bypass Yapper"),
        " key binding (default ", key("Shift+Enter"), "). Bindings can be changed in WoW's Key Bindings menu."),

    separator(),

    heading("Channels and Whispers"),
    body(key("Tab"), " — cycle forward through available channels. ",
        key("Shift+Tab"), " — cycle backwards when spellcheck suggestions are not available."),
    body("The cycle includes Say, Emote, Yell, Party, Instance, Raid, Raid Warning, Guild, "
        .. "and Officer when those channels are available."),
    body("You can type channel commands directly: ", key("/s"), " Say, ", key("/e"),
        " Emote, ", key("/p"), " Party, ", key("/ra"), " Raid, ", key("/g"),
        " Guild, or a numbered channel such as ", key("/1"), "."),
    body(key("/w Name message"), " whispers to a player. ", key("/r message"),
        " replies to the most recent whisper. Use ", key("/yell"), ", ", key("/i"),
        ", ", key("/rw"), ", and ", key("/o"), " for other supported channels."),
    body("Yapper can remember your last channel. Change Remember last channel, group-channel, "
        .. "or whisper settings in General to control this behaviour."),

    separator(),

    heading("Autocomplete"),
    body("When autocomplete and spellcheck are enabled and a dictionary is available, "
        .. "Yapper may show a grey ghost word after a two-character prefix."),
    body(key("Tab"), " — accept the ghost word and add a space. Keep typing to choose a "
        .. "different word or refine the suggestion."),

    separator(),

    heading("Spellcheck"),
    body("Misspelled words are coloured. Place the cursor in a marked word and press ",
        key("Shift+Tab"), " to open its suggestions. You can also right-click the word or hint."),
    body("Use the number shown beside a suggestion, ", key("Up"), " / ", key("Down"),
        ", and ", key("Enter"), " to choose and apply it. ", key("Escape"),
        " closes the suggestion list without changing the word."),
    body("Yapper can learn words you send repeatedly and remember correction preferences. "
        .. "Adaptive learning and its threshold are configurable in Spellcheck settings."),

    separator(),

    heading("Multiline Editor (Storyteller)"),
    body("Press ", key("Shift+Enter"), " while the single-line chat box is open to expand it."),
    body(key("Enter"), " — send. ", key("Shift+Enter"), " — insert a line break. "
        .. "A blank line separates paragraphs; each paragraph is sent as a separate message."),
    body(key("Escape"), " — return to the single-line box with your draft. ",
        key("Tab"), " accepts autocomplete, and ", key("Shift+Tab"),
        " opens spellcheck suggestions when a word is eligible."),

    separator(),

    heading("Draft Recovery"),
    body("If you reload or log out while editing, Yapper can restore your unfinished draft "
        .. "the next time you open chat. Multiline drafts keep their paragraph breaks."),
    body("To keep a single-line draft after pressing Escape, enable "
        .. "Recover text after ESC in General settings. Otherwise, non-empty text closed with "
        .. "Escape is placed in chat history instead of being restored as a draft."),

    separator(),

    heading("Undo / Redo"),
    body(key("Ctrl+Z"), " — undo. ", key("Ctrl+Y"), " — redo."),
    body("Use these while editing in either the single-line or multiline chat box."),

    separator(),

    heading("History and Pickers"),
    body(key("Up"), " / ", key("Down"), " — recall messages from Yapper's sent-message history."),
    body("Type ", key("/"), " and press ", key("Tab"), " to browse emotes. Type to filter, "
        .. "then use the mouse or ", key("Up"), " / ", key("Down"), " and ", key("Enter"),
        " to choose one. Whether it sends immediately is controlled by Auto-send chosen emotes in General settings."),
    body("Type an open ", key("{"), " to open the raid-icon picker. Choose an icon with the "
        .. "mouse or keys 1–8; ", key("Escape"), " closes the picker."),

    separator(),

    heading("Yapper Commands"),
    body(key("/yapper"), " or ", key("/yapper toggle"), " — toggle settings."),
    body(key("/yapper open"), " / ", key("/yapper show"), " — open settings. ",
        key("/yapper close"), " / ", key("/yapper hide"), " — close settings."),
    body(key("/yapper help"), " or ", key("/yapper ?"), " — open this Help page."),
    body(key("/yapper whatsnew"), " or ", key("/yapper changelog"),
        " — open What's New. ", key("/yapper export"), " — export learned spellcheck data."),
    body("Right-click the minimap or addon-compartment icon to open this Help page."),
}

-- Lua 5.1's ipairs bypasses __index proxies, so expose a safe iterator for
-- consumers instead of requiring them to iterate the protected Items table.
function HelpContent.ForEachItem(callback)
    if type(callback) ~= "function" then return end
    for index, item in ipairs(HelpContent.Items) do
        callback(ReadOnly(item, "Yapper.HelpContent.Items[" .. index .. "]"), index)
    end
end

-- Expose only the read-only proxy; the mutable source table stays local.
YapperTable.HelpContent = ReadOnly(HelpContent, "Yapper.HelpContent")
