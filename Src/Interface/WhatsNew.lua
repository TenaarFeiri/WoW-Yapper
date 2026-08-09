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
    ["2.4.1"] = {
        {
            title = "Bug Fixes",
            body = "- Fixed issue where the new colour sanitiser was too aggressive and broke item links.\n\n"
                .. "- Fixed issue where links were unable to be added to the multiline editor.",
        },
    },
    ["2.4.0"] = {
        {
            title = "Spellcheck now colours misspelled words",
            body  = "Misspelled words are now coloured directly instead of being underlined or highlighted. "
                .. "The marking stays with the text when you scroll, resize the window, or wrap lines in multiline mode.",
        },
        {
            title = "Simpler spellcheck settings",
            body  = "The old underline-style setting and its two colour pickers have been replaced by one Misspelling Colour option. "
                .. "Your previous underline colour is migrated automatically.",
        },
        {
            title = "Multiline mode is easier to discover",
            body  = "A first-use hint now reminds you to press Shift-Enter to enter multiline mode. "
                .. "It appears once per session and does not interrupt future opens.",
        },
        {
            title = "Multiline and spellcheck fixes",
            body  = "The spellcheck suggestion list and hint now appear at the caret, even on wrapped lines. "
                .. "Multiline background colour changes also apply immediately while proxy mode is enabled.",
        },
        {
            title = "Colour codes are removed before sending",
            body  = "Colour codes pasted into chat, including spellcheck markings, are removed before sending. "
                .. "They can no longer leak into chat, history, or Blizzard's editbox during combat handoff.",
        },
        {
            title = "Bug fixes",
            body = "- Fixed issue where post duplication occurred when interrupting Yapper's sending state. "
                .. "This could most often be triggered by opening Yapper while emotes are in transit. "
                .. "You should no longer be able to open Yapper while it's multiposting.\n\n"
                .. "- Fixed multiline mode not updating its background colour immediately when proxy mode was enabled. Changes now apply without requiring a reload.",
        },
    },
    ["2.3.0"] = {
        {
            title = "Languages integration overhauled",
            body  = "Yapper now uses the Languages addon's public API for dialects and language tags. "
                .. "Multiline posts, combat/faction/TRP3 rules, and per-paragraph handling now match Languages' own behaviour. "
                .. "Recalling and re-sending a message no longer stacks a second [Language] tag.",
        },
        {
            title = "Multiline and history fixes",
            body  = "Multiline and single-line editors now share one send pipeline, so filters, stall recovery, "
                .. "split-post errors, and cancelled-send handling work the same in both. History now records what you typed, "
                .. "not the rewritten message, and multi-paragraph pastes create separate recallable entries.",
        },
    },
    ["2.2.6"] = {
        {
            title = "Combat lockdown channel fix",
            body  = "Entering combat lockdown no longer reverts your chat channel to Say, "
                .. "fixing channel desync in dungeons and other instanced content.",
        },
    },
    ["2.2.5"] = {
        {
            title = "Slash-open double input fixed",
            body  = "Pressing a slash key to open chat no longer produces duplicated input.",
        },
        {
            title = "WhisperMessenger support",
            body  = "Added compatibility for WhisperMessenger. "
                .. "Note: some reply keybinds may still briefly activate WM's window.",
        },
    },
    ["2.2.4"] = {
        {
            title = "Addon-driven editbox and sticky fixes",
            body  = "Addons that call ActivateChat to SetText, SendText, or Deactivate are now less likely to have "
                .. "their messages or commands silently dropped. Sticky whisper and label resizing are also more consistent.",
        },
        {
            title = "New sticky-whisper setting",
            body  = "You can now enable sticky whisper in non-whisper tabs via the settings.",
        },
    },
    ["2.2.3"] = {
        {
            title = "German dictionary and lockdown fixes",
            body  = "Fixed a German dictionary syntax error that could block loading, "
                .. "and reduced lag when opening the editbox after combat or zoning.",
        },
        {
            title = "Faster editbox open",
            body  = "Keybind handling and label rendering are now cached, so the chat window opens more quickly.",
        },
    },
    ["2.2.2"] = {
        {
            title = "Taint and whisper fixes",
            body  = "Right-click menu options like 'Copy Character Name' and 'Set Focus' no longer get blocked by Yapper. "
                .. "Battle.Net and normal whisper /r behaviour should be more consistent.",
        },
    },
    ["2.2.1"] = {
        {
            title = "Channel switching and whisper reliability",
            body  = "Clicking channel links now opens Yapper on the right channel. Slash channels like /1, /g, and /p "
                .. "switch cleanly without showing raw text. Whisper opens share a common retarget path, "
                .. "and chat falling back to Blizzard's native editbox is recorded in Yapper history.",
        },
        {
            title = "Proxy mode and live channel sync",
            body  = "Proxy-mode stability is improved, and changing channel via slash commands while Yapper is open "
                .. "now syncs to Blizzard's editbox in most cases. Yapper no longer delegates posting through LibGopher "
                .. "and warns when it is present.",
        },
    },
    ["2.2.0"] = {
        {
            title = "IM mode overhaul",
            body  = "Yapper now anchors to whichever docked or floating chat window you click, follows focus when "
                .. "switching tabs, minimizing, or closing, and restores the channel per window. "
                .. "ChatFrame1 is the final fallback when nothing else is open.",
        },
        {
            title = "Multiline and click-to-chat fixes",
            body  = "The expanded multiline editor anchors to the window you opened it from and avoids clipping off-screen. "
                .. "Clicking the chat message area in IM mode now opens Yapper instead of Blizzard's editbox.",
        },
    },
    ["2.1.29"] = {
        {
            title = "Whisper Integration Fix",
            body = "Fixed a bug where right-clicking a player's frame to whisper would open Blizzard's default editbox and ignore the first message sent."
        },
    },
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
