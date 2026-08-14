#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_help_content.lua — user-facing Help page regression checks
-- Run from the repo root: lua tools/2.0testsuites/test_help_content.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        io.write("  [" .. PASS .. "] " .. label .. "\n")
    else
        FAILURES = FAILURES + 1
        io.write("  [" .. FAIL .. "] " .. label .. "\n")
    end
end

local function readFile(path, message)
    local file = assert(io.open(path, "r"), message)
    local source = file:read("*a")
    file:close()
    return source
end

local source = readFile("Src/Interface/HelpContent.lua", "failed to open Help content source")
local renderer = readFile("Src/Interface/Pages.lua", "failed to open Help renderer source")
local whatsNew = readFile("Src/Interface/WhatsNew.lua", "failed to open What's New content source")

local helpTable = {}
local helpLoader = assert(loadfile("Src/Interface/HelpContent.lua"), "failed to load Help content")
helpLoader("Yapper", helpTable)
local exposedHelp = helpTable.HelpContent

print("Help page: stale wording")
check("does not describe misspellings as underlined",
    not source:find("Misspelled words are underlined", 1, true))
check("does not claim multiline opens automatically",
    not source:find("automatically opens the multiline editor", 1, true))
check("does not promise draft recovery after a few uses",
    not source:find("after a few uses", 1, true))
check("does not claim undo is only at word boundaries",
    not source:find("Snapshots are taken at word boundaries", 1, true))

print("Help page: user-facing feature coverage")
check("documents reply slash input separately from Raid",
    source:find("/r message", 1, true) and source:find("/ra", 1, true))
check("documents the multiline entry key",
    source:find("expands it into the multiline editor", 1, true))
check("documents history navigation",
    source:find("sent-message history", 1, true))
check("documents the emote picker",
    source:find("browse emotes", 1, true))
check("documents the raid-icon picker",
    source:find("raid-icon picker", 1, true))
check("documents the native-editor bypass",
    source:find("Bypass Yapper", 1, true))
check("documents Escape draft recovery setting",
    source:find("Recover text after ESC", 1, true))
check("documents all Yapper command groups",
    source:find("/yapper export", 1, true)
        and source:find("/yapper changelog", 1, true))
check("Pages renders the extracted Help content",
    renderer:find("YapperTable.HelpContent", 1, true)
        and renderer:find("help.ForEachItem(function(item)", 1, true)
        and renderer:find("parts.ForEach(appendPart)", 1, true))
check("What's New demonstrates note and release helpers",
    whatsNew:find("local function note", 1, true)
        and whatsNew:find("local function release", 1, true)
        and whatsNew:find('["2.4.2"] = release(', 1, true))

print("Help page: read-only exposure")
check("exposes readable Help content",
    exposedHelp.Title == "How to use Yapper" and exposedHelp.Items[1].text == "Getting Started")
local itemCount = 0
local firstBodyParts
exposedHelp.ForEachItem(function(item)
    itemCount = itemCount + 1
    if not firstBodyParts and item.kind == "body" then
        firstBodyParts = item.parts
    end
end)
check("read-only proxy remains traversable", itemCount > 0)
local partCount = 0
if firstBodyParts and type(firstBodyParts.ForEach) == "function" then
    firstBodyParts.ForEach(function()
        partCount = partCount + 1
    end)
end
check("nested body parts remain traversable", partCount > 0)
local canChangeRoot = pcall(function()
    exposedHelp.Title = "Changed by another addon"
end)
local canChangeNested = pcall(function()
    exposedHelp.Items[1].text = "Changed by another addon"
end)
local canChangeParts = pcall(function()
    firstBodyParts[1] = "Changed by another addon"
end)
local canChangeMetatable = pcall(setmetatable, exposedHelp, {})
check("rejects root content mutation", not canChangeRoot)
check("rejects nested content mutation", not canChangeNested)
check("rejects body-part mutation", not canChangeParts)
check("rejects metatable replacement", not canChangeMetatable)

print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
