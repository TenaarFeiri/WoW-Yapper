#!/usr/bin/env python3
"""
Split Spellcheck.lua into sub-files.
Run from repo root: python3 tools/split_spellcheck.py
"""
import os

SRC = "Src/Spellcheck.lua.bak"
OUT_DIR = "Src/Spellcheck"
OUT_HUB = "Src/Spellcheck.lua"

def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.readlines()

def write_file(path, content):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  wrote {path} ({content.count(chr(10))} lines)")

def extract(lines, start, end_):
    """Extract lines[start-1:end_] (1-indexed inclusive)."""
    return "".join(lines[start - 1 : end_])

def main():
    lines = read_lines(SRC)
    print(f"Read {len(lines)} lines from {SRC}")

    # -----------------------------------------------------------------------
    # Hub (Spellcheck.lua): module + state + constants + utility locals +
    #   Init + config getters + user dict
    # Lines: 1-306 (header through GetPhoneticHash),
    #        732-990 (config getters through GetKBDistTable)
    # -----------------------------------------------------------------------
    hub_content = extract(lines, 1, 306)
    hub_content += "\n"
    hub_content += extract(lines, 732, 990)

    # Export shared locals for sub-files.
    hub_content += '''
-- Export shared locals for sub-files to re-localise.
Spellcheck._SCORE_WEIGHTS     = SCORE_WEIGHTS
Spellcheck._MAX_SUGGESTION_ROWS = MAX_SUGGESTION_ROWS
Spellcheck._RAID_ICONS        = RAID_ICONS
Spellcheck._KB_LAYOUTS        = KB_LAYOUTS
Spellcheck._DICT_CHUNK_SIZE   = DICT_CHUNK_SIZE or 2000
Spellcheck.Clamp              = Clamp
Spellcheck.NormaliseWord      = NormaliseWord
Spellcheck.NormaliseVowels    = NormaliseVowels
Spellcheck.SuggestionKey      = SuggestionKey
Spellcheck.IsWordByte         = IsWordByte
Spellcheck.IsWordStartByte    = IsWordStartByte
'''
    write_file(OUT_HUB, hub_content)

    # -----------------------------------------------------------------------
    # Dictionary.lua: dictionary loading, registration, locale management
    # Lines: 307-730
    # -----------------------------------------------------------------------
    dict_header = '''\
--[[
    Spellcheck/Dictionary.lua
    Async dictionary loading, registration, locale availability checking,
    dictionary inheritance, and memory management.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local Clamp          = Spellcheck.Clamp

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local string_lower = string.lower
local string_format = string.format
local table_insert  = table.insert

-- Chunk size for async loading (from hub).
local DICT_CHUNK_SIZE = Spellcheck._DICT_CHUNK_SIZE

'''
    dict_body = extract(lines, 307, 730)
    write_file(os.path.join(OUT_DIR, "Dictionary.lua"), dict_header + dict_body)

    # -----------------------------------------------------------------------
    # UI.lua: binding, text events, font/measurement, hint, suggestion dropdown
    # Lines: 992-1859
    # -----------------------------------------------------------------------
    ui_header = '''\
--[[
    Spellcheck/UI.lua
    EditBox binding, text input event handlers, font measurement,
    hint frame, suggestion dropdown display and keyboard navigation,
    and suggestion application.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local SuggestionKey  = Spellcheck.SuggestionKey
local MAX_SUGGESTION_ROWS = Spellcheck._MAX_SUGGESTION_ROWS

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local string_sub = string.sub
local string_format = string.format

'''
    ui_body = extract(lines, 992, 1859)
    write_file(os.path.join(OUT_DIR, "UI.lua"), ui_header + ui_body)

    # -----------------------------------------------------------------------
    # Underline.lua: underline rendering, texture pooling, multiline
    # Lines: 1860-2353
    # -----------------------------------------------------------------------
    underline_header = '''\
--[[
    Spellcheck/Underline.lua
    Single-line and multi-line underline rendering, texture pooling,
    font measurement for wrapped text, and scroll-offset handling.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise Lua globals.
local type       = type
local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local math_abs   = math.abs
local string_sub = string.sub
local string_byte = string.byte

'''
    underline_body = extract(lines, 1860, 2353)
    write_file(os.path.join(OUT_DIR, "Underline.lua"), underline_header + underline_body)

    # -----------------------------------------------------------------------
    # Engine.lua: misspelling detection, word tracking, suggestion generation,
    #   edit distance, scoring
    # Lines: 2354-3351
    # -----------------------------------------------------------------------
    engine_header = '''\
--[[
    Spellcheck/Engine.lua
    Misspelling detection, active word tracking, suggestion generation
    (with phonetic, keyboard proximity, n-gram, and adaptive learning
    scoring), Damerau-Levenshtein edit distance, and label formatting.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local Clamp            = Spellcheck.Clamp
local NormaliseWord    = Spellcheck.NormaliseWord
local NormaliseVowels  = Spellcheck.NormaliseVowels
local SuggestionKey    = Spellcheck.SuggestionKey
local IsWordByte       = Spellcheck.IsWordByte
local IsWordStartByte  = Spellcheck.IsWordStartByte
local SCORE_WEIGHTS    = Spellcheck._SCORE_WEIGHTS
local RAID_ICONS       = Spellcheck._RAID_ICONS

-- Re-localise Lua globals.
local type         = type
local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local tonumber     = tonumber
local math_abs     = math.abs
local math_min     = math.min
local math_max     = math.max
local math_floor   = math.floor
local math_huge    = math.huge
local table_insert = table.insert
local table_sort   = table.sort
local string_sub   = string.sub
local string_byte  = string.byte
local string_lower = string.lower
local string_gsub  = string.gsub
local string_upper = string.upper
local string_match = string.match
local string_char  = string.char
local string_format = string.format

'''
    engine_body = extract(lines, 2354, 3351)
    write_file(os.path.join(OUT_DIR, "Engine.lua"), engine_header + engine_body)

    print("\nDone! Verify with: wc -l Src/Spellcheck.lua Src/Spellcheck/*.lua")

if __name__ == "__main__":
    main()
