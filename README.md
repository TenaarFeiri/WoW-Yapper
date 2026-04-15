# Yapper EditBox & Post Splitter
Yapper is functionally a replacement of the EditBox for your chat window. It allows you to longpost as much as you like (until the server throttles you) and offers other neat features like draft recovery (if you crash or disconnect while typing), persistent chat history (recover your posts with Alt+ArrowUp/Down), and it gracefully falls back to Blizzard's default EditBox when a lockdown event is in progress.
This should allow you to RP *and* do content without having to worry about disabling an addon in the middle of a boss encounter, to ask the Havoc DH to please get back into melee.
## Please download the addon from here: https://github.com/TenaarFeiri/WoW-Yapper/releases

Yapper by Sara Schulze Øverby, aka Tenaar Feiri, Arru/Arruh and a whole bunch of other names in WoW...
Licence: [https://opensource.org/license/mit](https://opensource.org/license/mit) (go nuts)

## FAQ

### Why does Yapper use so much memory?

Short answer: the spellcheck dictionary.

Yapper ships with full English dictionaries (US and UK) stored as plain Lua tables so the spellchecker can run entirely in-game without external files. Those tables account for roughly **~58 MB** of the addon's memory footprint. The remaining **~21 MB** covers everything else — the UI, the edit box overlay, the chunker, settings, adaptive learning data, and all of Yapper's runtime state. Because english dictionaries are included by default and there's no way to load them without adding them to TOC (thus loading them into memory even if they aren't used), they account for most of that passive usage.

This is a conscious trade-off: keeping the dictionary in memory means instant lookups with zero disk I/O, which matters when we're checking every word you type in real time. WoW's Lua environment doesn't give addons access to the filesystem, so there's no way to lazy-load or stream dictionary entries from disk the way a desktop spellchecker would.

If memory is a concern, you can disable the spellchecker entirely in Yapper's settings — this prevents the dictionaries from loading and drops usage down to roughly the ~21 MB baseline.

Yapper WAS meant to be a simple, no-interface no-options works-out-of-the-box stand-in/replacement for 
addons like EmoteSplitter. It has since exploded in scope thanks to patch 12.0.0 but I'm taking up the challenge, I guess.
It's my first addon and my first foray into Lua!


<img width="397" height="119" alt="image" src="https://github.com/user-attachments/assets/f5420a4e-d607-45f4-9ad2-7d4d207662ea" />

