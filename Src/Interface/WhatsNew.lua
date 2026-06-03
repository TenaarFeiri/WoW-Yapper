--[[
    WhatsNew.lua

    Contains the WHATS_NEW table with version-specific changelog entries
    displayed in the "What's New" popup when Yapper is updated.
]]

local _, YapperTable = ...

-- ---------------------------------------------------------------------------
-- What's New notes — keyed by addon version.
-- Each entry is an array of { title, body } pairs shown in order.
-- ---------------------------------------------------------------------------
YapperTable.WHATS_NEW = {
    ["2.1.28"] = {
        {
            title = "IM Style compatibility",
            body = "Yapper now supports the IM Style setting for your chat boxes.",
        },
        {
            title = "New configuration option: Hide Blizzard editbox",
            body = "Added a new toggleable option to hide the default Blizzard editbox when using Yapper's appearance."
        },
        {
            title = "Bugfixes",
            body = "Fixed issue where Prat's frame sometimes didn't appear when in proxy mode.\n"
                .. "Fixed issue where cycling tabs in IM Style would automatically open and focus Yapper."
        },
    },
    ["2.1.17"] = {
        {
            title = "API Changes",
            body = [[- New API has been added to better support external plugins.
- With these changes, addons like CEBE can better support Yapper! :)
            ]],
        },
        {
            title = "Bugfixes",
            body = [[- Registered Yapper to Blizzard's system by recording ACTIVE_CHAT_EDIT_BOX. (as of 2.1.15)
- Due to this change, several issues bubbled up which resulted in Yapper becoming unresponsive under certain conditions. This is now fixed.
- Linking from other addons, like TRP3, should now work correctly.
            ]]
        }
    },
    ["2.1.12"] = {
        {
            title = "Emote Picker added!",
            body = "Added a new Emote Picker which can be opened by typing \"/\" "
                .. "in the chat overlay and hitting TAB! If you continue to type afterwards, "
                .. "it will narrow down the list of available emotes! "
                .. "You can also navigate the list using the UP and DOWN arrow keys, your scroll wheel "
                .. "or the scroll bar, and select your emote using ENTER or by clicking on it with your mouse. "
                .. "A new setting has been added to Yapper where you can optionally automatically "
                .. "send your emote when you select it. The default is to not immediately send the emote.",
        },
        {
            title = "Re-Whisper Added",
            body = "Yapper can now use your re-whisper keybind.",
        },
        {
            title = "Bad word filtering added",
            body = "Yapper will no longer suggest, or learn bad words and slurs. "
                .. "These are managed by the dictionaries, and you can add your own "
                .. "blocked words in the Advanced settings."
        },
        {
            title = "New Typing Tracker API",
            body = "Yapper now supports the new Typing Tracker API."
        }
    },
    ["2.1.10"] = {
        {
            title = "Adaptive Learning (YAS) Opt-Out",
            body  = "You can now suspend YAS's data collection and suggestion biasing "
                .. "while keeping the core spellchecker active. Toggle this in the "
                .. "Adaptive Learning settings or the initial setup popup.",
        },
        {
            title = "Factory Reset (Clean Slate)",
            body  = "Added a |cFFFF0000Factory Reset|r button in Advanced settings to wipe "
                .. "all data, history, and settings for a truly fresh start.",
        },
        {
            title = "Scrollable Changelog",
            body  = "This window is now scrollable! You can review the history of all "
                .. "major Yapper updates directly from this popup.",
        },
        {
            title = "Stability Fixes",
            body  = "Fixed a rare bug where closing the chat window too quickly could "
                .. "lose a message mid-send, and smoother transitions between chat modes.",
        },
    },
    ["2.1.0"] = {
        {
            title = "Global Settings Profiles",
            body  = "You can now sync your settings across all characters! Enable "
                .. "|cFF33FF99Use Global Profile|r in General settings to save your "
                .. "preferences and appearance to the account-wide |cFF33FF99YapperDB|r.",
        },
        {
            title = "Memory Optimizations",
            body  = "Dictionaries are now separate Load-on-Demand addons. This "
                .. "significantly reduces memory usage for players who only use "
                .. "one language or prefer to disable spellchecking entirely.",
        },
        {
            title = "Focus Stability",
            body  = "Completely refactored the editbox focus engine to resolve "
                .. "recursive crashes during chat transitions. Typing and "
                .. "switching channels is now more robust than ever.",
        },
    },
    ["2.0.3"] = {
        {
            title = "Spellchecking",
            body  = "Yapper now has a built-in spellchecker with per-locale dictionaries, "
                .. "underline styles, and adaptive learning (YAS) that picks up your "
                .. "vocabulary over time.",
        },
        {
            title = "Autocomplete / Ghost Text",
            body  = "As you type, a muted ghost-text prediction appears based on your "
                .. "personal vocabulary and the spellcheck dictionary. Press Tab to accept. "
                .. "Requires spellcheck to be enabled.",
        },
        {
            title = "Public API",
            body  = "Third-party addons can now register filters and callbacks through "
                .. "|cFF33FF99YapperAPI|r. Filters can modify or cancel messages before they "
                .. "are sent; callbacks fire after the fact.",
        },
        {
            title = "WIM Bridge",
            body  = "WoW Instant Messenger compatibility is now handled by a dedicated "
                .. "bridge module. If WIM is not installed the bridge is a no-op.",
        },
    },
}
