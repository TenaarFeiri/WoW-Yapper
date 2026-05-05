# Yapper EditBox & Post Splitter
Yapper is functionally a replacement of the EditBox for your chat window. It allows you to longpost as much as you like (until the server throttles you) and offers other neat features like draft recovery (if you crash or disconnect while typing), persistent chat history (recover your posts with Alt+ArrowUp/Down), and it gracefully falls back to Blizzard's default EditBox when a lockdown event is in progress.
This should allow you to RP *and* do content without having to worry about disabling an addon in the middle of a boss encounter, to ask the Havoc DH to please get back into melee.
## Please download the addon from here: https://github.com/TenaarFeiri/WoW-Yapper/releases

Yapper by Sara Schulze Øverby, aka Tenaar Feiri, Arru/Arruh and a whole bunch of other names in WoW...
Licence: [https://opensource.org/license/mit](https://opensource.org/license/mit) (go nuts)

## FAQ

### Why does Yapper use so much memory?

Short answer: Spellchecking.

Longer answer: Without spellchecking enabled, Yapper should sit comfortably in the <10MB range (before learning data), but for optimisation's sake, spellchecking trades memory for speed. Its dictionaries use a lot of precomputed data to stop Yapper needing to do a lot of background work while you're typing, which generates better spellchecking suggestions for you BUT uses more memory than, say, WoW-Misspelled.
This is a deliberate trade-off, as memory is in far greater supply than CPU capacity, and you will much quicker feel high CPU usage than high memory usage. Even so, potentially a few hundred megabytes on larger dictionaries should still be manageable for a computer that's capable of running WoW. The memory usage is fine, the problems happen if Yapper starts lagging your game, which it goes to great lengths to avoid.

----------------


<img width="397" height="119" alt="image" src="https://github.com/user-attachments/assets/f5420a4e-d607-45f4-9ad2-7d4d207662ea" />

## On AI Usage
Yapper is built with AI assistance, but AI is not the final authority on any part of the program. All code that is written or suggested by AI, gets reviewed, refined and/or refactored as needed, and undergoes extensive testing both in- and out of game before it's pushed to release.
