# NEW FEATURES IN 2.0
- Added a multiline editor, which supports editing long messages in a larger, resizable window with full Yapper features. Hit Shift-Enter while typing to activate the editor for easier edits. (added in 2.0.1)
- YALLM (Yapper Adaptive Language Learning Model)
  - Added adaptive YALLM learning to track common words, manual corrections, and improve autocomplete relevance over time. (added in 2.0.1)
  - Added selection bias, implicit backtrack learning, rejection feedback, phonetic pattern learning, and anti-contamination filters to make YALLM correction learning smarter and more robust. (added in 2.0.1)
  - Added YALLM-based ranking so your most-used words surface first and accepted suggestions improve ranking automatically. (added in 2.0.2)
  - Added YALLM apostrophe-prefix matching so typing `that'` still surfaces `that's`. (added in 2.0.2)
- Autocomplete enhancements
  - Added ghost-text predictive word completion with a muted caret preview and Tab acceptance. (added in 2.0.2)
  - Added a tiered autocomplete cascade using YALLM vocabulary, custom added words, locale dictionary search, and base fallback. (added in 2.0.2)
  - Added support for custom dictionary words as a second autocomplete source immediately after YALLM. (added in 2.0.2)
  - Added capitalisation mirroring for autocomplete suggestions so casing matches the typed prefix. (added in 2.0.2)
- Spellcheck improvements
  - Added capitalised spellcheck suggestions so the suggestion popup mirrors the case of the misspelled word. (added in 2.0.2)
  - Added suggestion pagination with up to six spellcheck suggestions per page and a `More Suggestions »` cycle. (added in 2.0.1)
- Settings and UI
  - Added an Adaptive Learning settings tab with live tables for learned words, corrections, phonetic patterns, and rejected suggestions. (added in 2.0.1)
  - Added tuning sliders for Vocabulary Cap, Correction Bias Cap, and Auto-learn Threshold. (added in 2.0.1)
  - Added a help page in the settings dialog with instructions for using Yapper's chat features. (added in 2.0.3)
  - Added an icon gallery for inserting raid target icons via `{star`, `{circle`, etc. (added in 2.0.3)
- Compatibility and API
  - Added the public `_G.YapperAPI` addon API with filters, callbacks, readonly accessors, and structured `API_ERROR` reporting. (added in 2.0.1)
  - Added RP Prefix compatibility so prefixes are prepended only to the first post of a split message. (added in 2.0.1)

## Patch notes
-- 2.1.5
  - *Bug Fixes:*
    - **BNet whispers:** Fixed target resolution when Gopher is active so name-based BN targets are resolved before bridge handoff.
    - **WIM compatibility:** Tightened overlay suppression to require actual WIM editbox focus, preventing non-whisper opens from being suppressed when a WIM window is only open in the background.

-- 2.1.4
  - *Bug Fixes:*
    - **Overlay language stickiness:** Fixed editbox reopen language selection so sticky `LastUsed.language` is no longer overridden by Blizzard's auto-reseeded default language on non-target opens.
    - **Slash chat mode language retention:** Fixed `/s`-family chat mode switches (`/s`, `/y`, `/p`, `/ra`, `/g`, `/i`, `/o`, `/rw`, `/e`, `/em`, `/me`, `/emote`) no longer clearing the selected language.

-- 2.1.3a
  - *Bug Fixes:*
    - **Dictionary Loading:** Fixed TOC load order issues which was preventing dictionaries from showing up under Yapper.

-- 2.1.3
  - *API & Architecture:*
    - **Internal Dogfooding:** Re-wired the message chunking module to consume the public `GetDelineator` API. This ensures that any architectural changes to configuration paths are immediately validated by the core splitting engine.
    - **Documentation:** Backfilled `GetDelineator` into the API documentation and updated all method anchors to reflect recent code shifts.

-- 2.1.2
  - *Bug Fixes:*
    - **Global Profile inheritance fixed end-to-end:** Enabling "Use Global Profile" now correctly clears character-local overrides for syncable categories so account-wide values are immediately applied (including appearance/theme colours) without requiring a reload.
    - **Push to Global now includes sync-safe System settings and deep-copies values:** Theme choice and other global-safe system options now migrate correctly, with local-only values like `FrameSettings.MainWindowPosition` staying character-specific.

-- 2.1.1
  - *Performance:*
    - **Faster autocomplete on every keystroke:** Rebuilt the personal-vocabulary (YALLM) lookup used for ghost-text predictions. Yapper previously scanned your entire learned vocabulary (up to 2,000 words) on every character typed. It now binary-searches a sorted index, so autocomplete stays smooth even when your YALLM is full and you're a fast typist.
  - *Bug Fixes:*
    - **"Maximum chat history lines" setting now actually works.** The slider in the Advanced settings page was wired to a default constant rather than the configured value, so adjusting it did nothing — Yapper always kept 50 lines. It now respects your setting.
    - **API error reporting (developers only):** Fixed two latent error paths in `_G.YapperAPI` that would have thrown "attempt to call nil" if a third-party addon ever registered more than 50 filters or callbacks on the same hook. The cap has never been hit in practice, but the error handler itself is no longer broken.
    - **Multiline Autoscroll:** Fixed an issue where the multiline editor would not automatically scroll down when you breached the bottom of the view.

-- 2.1.0
  - *Major Features:*
    - **Global Settings Profiles:** Added support for account-wide settings. Enable "Use Global Profile" in General settings to sync your preferences across all characters via the account-wide `YapperDB`.
    - **Global Sync Tool:** Added a "Push to Global" button to easily migrate your current character's setup to the new account default.
  - *Structural & Memory Optimizations:*
    - **LOD Dictionaries:** Dictionary locales have been moved to their own Load-on-Demand (LOD) addons. This significantly reduces the base memory footprint of Yapper for users who don't use the spellchecker or only use specific locales.
  - *Stability & Bug Fixes:*
    - **Focus Stability (Issue #21):** Refactored the EditBox focus engine with a triple-layered defense (deferred focus, re-entry guards, and multiline parity) to resolve C stack overflow crashes during chat transitions.
    - **Spellcheck UI:** Added an in-game warning and helpful CurseForge link when enabling spellcheck without any dictionaries installed.

-- 2.0.4a
  - *Bridge Fixes*
    - Fixed an issue where the TypingTrackerBridge would not send signals to the correct channels.

-- 2.0.4
  - *Bugfixes:*
    - Fixed an issue where Blizzard skin proxy mode made the multiline editor render transparently.
    - Fixed an issue where spellcheck highlighting desynced from the text in the multiline editor when the text wrapped across multiple lines.

-- 2.0.3
  - *Bugfixes:*
    - Fixed issue where the post queue would get stuck if you posted to Party, Instance or Raid Chat while you were a leader in one or more of these.
    - Fixed a bug where YALLM didn't correctly boost words to the autocompleter.
    - Fixed numerous visual bugs in the overlay, ghost text and the multiline editor.
    - Fixed minor alignment bugs in the settings dialog.

-- 2.0.2
  - *Bugfixes:*
    - **Multiline Underline Alignment:** Spellcheck highlight underlines in multiline mode were drawn 1 px too far right. Fixed.
    - **`math_min` crash fix:** Fixed a `nil value` error in `Autocomplete.lua` when the dismissal penalty code ran — `math_min` was used but not localised.

-- 2.0.1
  - *Structural Cleanup:*
    - **Monolith Split:** The three largest files — Interface.lua (4 100+ lines), Spellcheck.lua (3 300+ lines), and EditBox.lua (2 900+ lines) — have each been broken into focused sub-modules. Spellcheck now loads as 6 files, EditBox as 5, and Interface settings as several panel files.
    - **Spring Cleaning:** Purged a lot of legacy "orphaned" code and redundant N-gram relics that were just taking up space. The engine is leaner and faster.
    - **Hardened Initialisation:** Added better sanity checks during boot. If something critical (like the UI cache) fails to load, Yapper will now tell you exactly what went wrong instead of failing silently.
  - *Stability & Bug Fixes:*
    - **Memory Management:** Killed off several memory leaks and ensured dictionaries don't duplicate on reload.
    - **Dictionary Base Protection:** Fixed a bug where switching locale could unload the base dictionary that a delta locale (e.g. enGB) depends on, causing the spellchecker to go partially blind.
    - **Fixed "Confused" Suggestions:** Resolved a bug where the spellchecker would occasionally point at the wrong words in a sentence.
    - **UI Polish:** Fixed alignment issues in the settings menu where buttons and input boxes were getting cut off.
    - **Visual Fixes:** Suggestions no longer "travel to Narnia" on long, sideways-scrolling messages.

-- 1.2.5
  - *Major Spellcheck Overhaul:*
    - **Better Word Recognition:** Fixed cases where obvious misspellings were being ignored or given poor suggestions.
    - **Apostrophe Fix:** Fixed a bug where words with apostrophes weren't being recognized correctly.
    - **Search Logic Fix:** Repaired a hidden bug that was making the engine work way harder than it needed to, resulting in much faster and more accurate suggestions.
    - **Speed Improvements:** Removed some slow background processes that were causing the game to hang when loading large dictionaries.
    - **More Accurate Suggestions:** Increased how many words the engine looks at, ensuring high-quality suggestions for common words.
    - **Improved Accuracy:** The spellchecker is now significantly smarter, frequently guessing the right word first in our internal stress tests.

-- 1.2.4
  - *Overlay improvements:*
    - **Unfocused Persistence:** The overlay can now stay open while allowing keyboard input to propagate back to the game (WASD, abilities) when unfocused.
    - **Graceful Handoff:** Added a "wait-to-close" mechanism for combat lockdowns; Yapper now waits for you to stop typing (1.5s idle) before handing over to Blizzard's secure editbox.
    - **Keystroke Handling:** Updated focus transitions to prevent "leaking" final keystrokes (like Enter or ESC) to the game world menu systems.
    - **AutoFocus Fix:** Resolved an issue where the overlay would aggressively steal focus when attempting to click into the game world.
  - *Interface & Settings:*
    - **ESC Support:** The main Settings window can now be dismissed with the ESC key.
    - **Focus Trapping:** Text inputs in the interface now trap Enter/ESC to defocus rather than closing the entire panel.
    - **Theme Overrides:** Added `allowRoundedCorners` and `allowDropShadow` theme flags. 
    - **Live Proxy Sync:** Toggling the "Blizzard skin proxy" now applies immediately to the live overlay.
    - Visual settings are now dynamically disabled and labeled when restricted by a theme or the Blizzard skin proxy.
  - *Bug Fixes:*
    - Fixed a critical widget pool corruption bug involving `ResetButton` double-registration.
    - Resolved an issue where dropdown menus would fail to update their state after a reset.
  - *Advanced Visuals:* Added new theme customisation options for the chat overlay!
    - Added **Rounded Corners** toggle (utilises Blizzard's native tooltip toolkit).
    - Added a new, toggleable **Drop Shadow** visual to the overlay.
    - Shadows are fully configurable: adjustable thickness, colour, and opacity.
  - *Spellcheck Customisation:*
    - Added new colour pickers for the spellchecker. You can now customise the colours for both the standard underline and the highlight style, individually.
  - *Rendering Improvements:*
    - Isolated spellcheck texture rendering and font measurement to prevent layout invalidation loops.
  - *Internal Cleanup:*
    - Switched `OnCursorChanged` handling to `HookScript` for better interoperability with other UI modifications.

-- 1.2.3a
  - Fixed an issue with the fallback minimap button being misshapen.

-- 1.2.3
  - *Massive feature update:* Integrated a real-time spellchecker into the edit box!
    - Includes English (US) and English (UK) dictionaries by default.
    - Extensive customization options added to Settings (underlines, minimum word length, suggestion counts, etc.).
  - *Major backend overhaul:* The entire chat routing and queueing pipeline has been refactored to an event-based system.
    - Resolves multi-link chunking breaking and failing silently.
    - Fixes persistent stalls when posting to community channels (C_Club).
    - Removed manual batching and throttle settings as the new pipeline handles this automatically and reliably.
  - Fixes critical chunking issues with WoW's item quality colour codes, which were causing problems with item linkage.
  - Added new Editbox background theme colours specific to BNet Whispers, Channels, and Communities to match Blizzard defaults.
  - Added a new 'Recover on Escape' setting - allowing you to choose whether pressing Escape saves your text as a draft or discards it. (This was backported to 1.1.4)
  - Various performance optimizations and persistence bug fixes.
  - Fixed issue where attempting to link a transmog set from the transmog window caused a conflict.
  - Fixed issue where the Blizzard EditBox was able to open above Yapper on a second open.

-- 1.1.4a
    - Attempted to fix an issue causing text to get stuck in the Blizzard editbox, which resulted in unintended prefilling behaviour when Yapper takes over.

-- 1.1.4
  - Fixed issue where whispers initiated from UI (unit frames, friend lists, etc.) got stuck in sticky mode.

-- 1.1.3
  - Fixed a bug where character language wasn't being set correctly.
  - Started work on a frame refactor to optimise how frames are created and managed.
    (currently does not impact user)

-- 1.1.2b
  - Fixed a bug which caused the truncation of channel chatter to still engage the chunker.
  - Removed single quotes from being counted by continuation persistence.

-- 1.1.2
  - Fixed visual problems with Yapper's frame; it now resembles Blizzard's more closely.
  - Fixed issue where community names were not correctly applied to the label.
  - Fixed limited target channels (whispers, namely) from creating a weird freeze condition by simply...
    not allowing whispers to exceed 255 characters in the first place.
  - Added feature to the chunker where if you are using TotalRP 3, it will attempt to preserve
    its colouring of things like dialogue and emotes in the event of there being a post split.
  - Fixed a problem where being in Housing Editor would cause Yapper to fail to open, thus preventing
    chatting.
  - Fixed issue where the Continue frame would not show while in Housing Editor, in the event of a split
    post.
  
  a.
    - Fixed issue wherein you were unable to chat to party while in a raid. Trust Blizz to know where
      you can chat.

-- 1.1.1
  - Fixed missing colon from labels.

-- 1.1.0
  - Added experimental styling to Yapper.
  - Added experimental Blizzard skin to Yapper's overlay.
  - Fixed issue where some /-commands caused nil errors (hopefully).
  - Added ability to bypass Yapper via keybind & access normal chatbox direct (default: Shift-Enter)
  - When the user presses just /, Yapper should open with the / pre-filled.
  - Redesigned the Settings interface. It's now a lot cleaner.
  - Fixed bug where switching chat tabs opened Yapper.

-- 1.0.7
  - Fixed a bug where the unstick option ironically got stuck on the channel you were last on when unsticking.
  - Fixed a bug where the Chat Reply keybind would not open Yapper and set the whisper at all.
  - Fixed a bug where toggling the sticky channel options did not immediately update.

-- 1.0.6
  - Fixed a bug where the color picker opacity would toggle between visible and invisible or default to 0 due to inverted alpha handling.
  - Fixed a bug where the Typing Tracker Bridge toggle would not persist its enabled state or correctly initialize on startup.
  - Added experimental support for Simply Typing - Typing Tracker.
  - Improved Typing Tracker Bridge robustness: added dynamic channel detection to ensure typing indicators accurately follow slash-command channel switches (e.g., `/p` or `/w`).
  - Added support for Shift+Click quest and specialised link insertion into the overlay editbox.
  - Resolved link duplication bug caused by overlapping hooks.
  - Relaxed link-splitting restriction in Chat.lua: long messages with links can now be split safely, but you cannot send more than two links.
  - Refined chat history uniqueness: identical messages on different channels are now preserved as separate entries.
  - Added toggleable settings for enabling/disabling bridges in Advanced view.

-- 1.0.5
  - Yapper's editbox should no longer be able to be opened while UI is hidden, and will close automatically if it is open when hiding the UI.

  - Hitting Enter to chat in the event editbox is still open after a lockdown has begun, will now save it as a draft and close with a warning, instead of allowing it to trigger a reserved action error.

-- 1.0.4
  - Added channel memory to chat history. Yapper remembers which channels you sent posts to and will target those channels when you recall them with alt+up/down.
  - Fixed a bug where system chat commands (like /reload) were not added to the chat history.
  - Tightened up the use of delineators in the posting system to make it a little easier to integrate with.

-- 1.0.3
  - Reverted bugfix from 1.0.2 that unhooked LibGopher, breaking addons like CrossRP.
  - Added new bridge module that detects if LibGopher is present, and forwards our processed messages to it for queueing.

-- 1.0.2
  - Bugfix: Due to the way we now operate, the regular patch for Gopher no longer worked. Since Yapper does
            basically everything Gopher does, functionally, we just unhook it from everything when it's present.
            This had caused issued with CrossRP before, and may cause issues with other addons that implement Gopher.
            Needless to say, UCM and EmoteSplitter will not be compatible with Yapper due to this.

-- 1.0.1
  - In-game UI to change settings. See addon compartment, minimap button (if supported) or type '/yapper' in chat.

  - New accessibility options!
    - Better text styling controls, can set font size, outline mode, and per-channel colour customization!
    - Background styling for the edit box, set to any colour combination and opacity!

  - Improved chat label behavior and sticky-channel handling, including reduced BNet handoff issues.
  - Improved message-splitting marker handling and spacing behavior. Now customisable!
  - Better undo/redo reliability and local SavedVariables migration safety.

  Known Issues:
    - Rare BNet editbox contention can still occur in some whisper transition sequences.
    - Workaround: type `/s` or `/say` (without trailing whitespace) and press Enter to recover cleanly.

-- 1.0.0
    - FULL REFACTOR
    - DOES NOT TAINT BLIZZARD'S EDITBOX!
    - Improved post splitting.
    - Allows chatter to continue during lockdowns.
    - Now creates a custom chat frame while out of chat lockdown, and uses Blizzard's otherwise.
    - Near parity with Blizzard's EditBox.
    - Much-needed cleanup.
    - API compatibility system REMOVED (pending rework)
    - Began work on customisability options like font sizes and types. (Not Yet Implemented)
    - Draft system that saves your messages as you type them, and lets you recover them
      in the event you disconnect or reload, or otherwise have your editbox closed on you.
    - Per-character persistent post history (up to 50 posts saved, use alt+up/down to navigate)
    - Saves your post as a draft if you enter an encounter while typing, allowing you to recover it
      after it's over.

-- 0.9
    - New post queue system with confirmation-based ordering for EMOTE/GUILD.
    - SAY/YELL now send in batches of 3 per Enter press (avoids WoW throttle drops).
    - TRP3 integration: RP names now work correctly with message confirmation.
    - Added Escape key to cancel in-progress posts.
    - Item links now pause batching (they require hardware events).
    - Configurable throttle settings (BATCH_SIZE, BATCH_THROTTLE, STALL_TIMEOUT).
    - Code cleanup: removed unused legacy functions.

-- 0.8.2
    - Changed versioning system.
    - Implemented visual segmentation when splitting (use of >>).
    - Fixed an issue causing whispers to be erroneously attempted split.
    - Fixed a bug causing edit box to become unresponsive after an erroneous whisper split.

-- 0.8c
    - Created an early (currently clunky) framework for adding compatibility patches,
      including API exposure so developers can add their own patches. This is currently undocumented and
      extremely limited, I do not recommend using it yourselves yet.
    - Implemented compatibility patch for Gopher. *Should* preserve Gopher's own features while using
      Yapper's own chat implementations. This should allow Yapper to be used in conjunction with addons
      using Gopher, like CrossRP.
    - Implemented a fix for Prat's sticky channels.

-- 0.8b
    * Added some cleanup functions for extra memory management.
    * Patched a memory leak. You will see memory rise during active usage, but it should peak at a reasonable level and
      go back down again on its own.

-- 0.8
    * Completely refactored the entire codebase.
    * Streamlined multiple event and hooking methods.
    * Improved chat handling.
    * Error handling is better.
    * Fixed issue causing Yapper to block macros (but /target, /petattack and other protected commands don't work in the chat window)
    * Reduced throttling to 0.5s when multiposting.
    * Multiple performance optimisations; Yapper should be even faster now and able to keep up with even the most enthusiastic typist!

-- 0.7
    * Added message throttling. If post produces more than 3 messages, require enter presses at 1s intervals (enforced) to clear queue.
      Posts 2 messages at a time until queue cleared.
    * Removed RecolourEmote() function as it didn't work anyway and TRP handles that.

-- 0.6b
    * Yapper confirmed to work in Midnight Beta.

-- 0.6
	* Minor polish and practice getting metadata. The greeting looks better, I guess?
    * Removed some unused variables, cleaned out some commented-out features.
    * Added details and usage terms to yapper.lua.
    * Updated TOC.

-- 0.5
    * Added word-wrapping in an effort to stop the add-on splitting the text in the middle of a word.

-- 0.4
    * Fixed issue causing split messages to fail to display target markers like {square} etc.
