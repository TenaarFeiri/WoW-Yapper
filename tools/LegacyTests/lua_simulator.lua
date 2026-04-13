-- lua_simulator.lua
-- Headless Lua 5.1 simulator for Yapper Spellcheck

-- 1. Mock WoW Environment
local YapperTable = {
    Config = {
        Spellcheck = {
            NgramN = 2,
            NgramMaxPosting = 200,
        },
        System = {
            DEBUG = true
        }
    },
    Utils = {
        Print = function(self, kind, msg) print("[" .. kind:upper() .. "] " .. msg) end
    }
}

local MockFrame = {}
function MockFrame:new()
    local o = {}
    setmetatable(o, { __index = self })
    return o
end

function MockFrame:SetPoint() end

function MockFrame:Hide() end

function MockFrame:Show() end

function MockFrame:SetText() end

function MockFrame:SetWidth() end

function MockFrame:SetHeight() end

function MockFrame:SetAlpha() end

function MockFrame:SetParent() end

function MockFrame:SetScript() end

function MockFrame:SetBackdrop() end

function MockFrame:SetBackdropColor() end

function MockFrame:CreateFontString() return MockFrame:new() end

_G.CreateFrame = function() return MockFrame:new() end
_G.UIParent = {}
_G.C_Timer = {
    After = function(sec, func) func() end -- Synchronous execution for simulation
}
_G.GetTime = function() return os.clock() end
_G.GetLocale = function() return "enUS" end -- Default
_G.table_insert = table.insert              -- Some files might use this from global if not localized

-- 2. Load Spellcheck.lua core
local spellcheckFunc = loadfile("Src/Spellcheck.lua")
if not spellcheckFunc then error("Could not load Src/Spellcheck.lua") end
local Spellcheck = spellcheckFunc(nil, YapperTable)

-- 3. Utility to switch locales
local function SetSimulationLocale(locale)
    _G.GetLocale = function() return locale end

    -- Load Base if not already present
    if not Spellcheck.Dictionaries["enBase"] then
        local baseFunc = loadfile("Src/Spellcheck/Dicts/enBase.lua")
        if baseFunc then
            baseFunc(nil, YapperTable)
            Spellcheck:LoadDictionary("enBase")
        end
    end

    if locale ~= "enBase" then
        local localeFunc = loadfile("Src/Spellcheck/Dicts/" .. locale .. ".lua")
        if localeFunc then
            localeFunc(nil, YapperTable)
            Spellcheck:LoadDictionary(locale)
        end
    end
end

-- 4. Test Suite
local function RunTests(locale, testCases, silent)
    if not silent then
        print(string.format("\n=== Simulation: %s ===", locale))
        print("| Input | Expected | Rank | Typo Score | Typing Velocity |")
        print("|-------|----------|------|------------|-----------------|")
    end

    local totalTypoScore = 0
    local totalVelocity = 0
    local count = 0

    local keys = {}
    for k in pairs(testCases) do table.insert(keys, k) end
    table.sort(keys)

    for _, input in ipairs(keys) do
        local expected = testCases[input]
        local results = Spellcheck:GetSuggestions(input)
        local rank = "Miss"
        local suggestionStr = ""
        for i, res in ipairs(results) do
            if i > 1 then suggestionStr = suggestionStr .. ", " end
            suggestionStr = suggestionStr .. res.word
            if res.word:lower() == expected:lower() then
                rank = tostring(i)
                break
            end
        end

        local typoScore = (rank == "1") and 1 or ((rank ~= "Miss") and 4 or 10)

        local velocity = 0
        for i = 1, #expected do
            local partial = expected:sub(1, i)
            local pResults = Spellcheck:GetSuggestions(partial)
            if pResults[1] and pResults[1].word:lower() == expected:lower() then
                velocity = i / #expected
                break
            end
        end

        if not silent then
            print(string.format("| %-10s | %-10s | %-4s | %-3d | %s", input, expected, rank, typoScore, suggestionStr))
        end

        totalTypoScore = totalTypoScore + typoScore
        totalVelocity = totalVelocity + velocity
        count = count + 1
    end

    if not silent then
        print(string.format("\n**Average Typo Score (%s): %.2f**", locale, totalTypoScore / count))
        print(string.format("**Average ID Velocity (%s): %.2f**", locale, totalVelocity / count))
    end
    return totalTypoScore / count, totalVelocity / count
end

-- 5. Organic Typo Engine
local KB_LAYOUTS = {
    QWERTY = {
        q = { 0, 0 },
        w = { 1, 0 },
        e = { 2, 0 },
        r = { 3, 0 },
        t = { 4, 0 },
        y = { 5, 0 },
        u = { 6, 0 },
        i = { 7, 0 },
        o = { 8, 0 },
        p = { 9, 0 },
        a = { 0.25, 1 },
        s = { 1.25, 1 },
        d = { 2.25, 1 },
        f = { 3.25, 1 },
        g = { 4.25, 1 },
        h = { 5.25, 1 },
        j = { 6.25, 1 },
        k = { 7.25, 1 },
        l = { 8.25, 1 },
        z = { 0.75, 2 },
        x = { 1.75, 2 },
        c = { 2.75, 2 },
        v = { 3.75, 2 },
        b = { 4.75, 2 },
        n = { 5.75, 2 },
        m = { 6.75, 2 },
    }
}
local KB_NEIGHBORS = {}
for k, coord in pairs(KB_LAYOUTS.QWERTY) do
    KB_NEIGHBORS[k] = {}
    for k2, coord2 in pairs(KB_LAYOUTS.QWERTY) do
        if k ~= k2 then
            local dx = coord[1] - coord2[1]
            local dy = coord[2] - coord2[2]
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 1.5 then table.insert(KB_NEIGHBORS[k], k2) end
        end
    end
end

math.randomseed(os.time())

local function GenerateOrganicTypo(word)
    local len = #word
    if len < 2 then return word .. "z" end
    local rand = math.random(1, 100)
    local i = math.random(1, len)
    local char = word:sub(i, i):lower()

    if rand <= 40 then -- Fat-Finger (Keyboard Proximity)
        local neighbors = KB_NEIGHBORS[char]
        if neighbors and #neighbors > 0 then
            local replacement = neighbors[math.random(1, #neighbors)]
            return word:sub(1, i - 1) .. replacement .. word:sub(i + 1)
        end
    elseif rand <= 60 then                                 -- Doubling / De-doubling
        if i < len and word:sub(i, i) == word:sub(i + 1, i + 1) then
            return word:sub(1, i) .. word:sub(i + 2)       -- De-double
        else
            return word:sub(1, i) .. char .. word:sub(i + 1) -- Double
        end
    elseif rand <= 75 then                                 -- Vowel Confusion
        local vowels = { a = "e", e = "i", i = "e", o = "u", u = "o", y = "i" }
        if vowels[char] then
            return word:sub(1, i - 1) .. vowels[char] .. word:sub(i + 1)
        end
    elseif rand <= 90 then -- Transposition
        local j = (i == len) and (i - 1) or (i + 1)
        local b1, b2 = word:sub(i, i), word:sub(j, j)
        if i < j then
            return word:sub(1, i - 1) .. b2 .. b1 .. word:sub(j + 1)
        else
            return word:sub(1, j - 1) .. b1 .. b2 .. word:sub(i + 1)
        end
    else -- Apostrophe Neglect
        if word:find("'") then
            return word:gsub("'", "")
        else
            return word:sub(1, i) .. "'" .. word:sub(i + 1)
        end
    end
    return word .. "s" -- Fallback
end

-- 6. Test Suite
local function RunTests(locale, testCases, silent)
    local results_audit = {}
    local totalTypoScore, totalVelocity, count = 0, 0, 0

    local keys = {}
    for k in pairs(testCases) do table.insert(keys, k) end

    for _, input in ipairs(keys) do
        local expected = testCases[input]
        local results = Spellcheck:GetSuggestions(input)
        local rank = "Miss"
        for i, res in ipairs(results) do
            if res.value:lower() == expected:lower() then
                rank = tostring(i)
                break
            end
        end

        local typoScore = (rank == "1") and 1 or ((rank ~= "Miss") and 4 or 10)

        local velocity = 1
        for i = 1, #input do
            local partial = input:sub(1, i)
            local pResults = Spellcheck:GetSuggestions(partial)
            if pResults[1] and pResults[1].value:lower() == expected:lower() then
                velocity = i / #input
                break
            end
        end

        table.insert(results_audit,
            { input = input, expected = expected, rank = rank, score = typoScore, vel = velocity })
        totalTypoScore = totalTypoScore + typoScore
        totalVelocity = totalVelocity + velocity
        count = count + 1
    end

    table.sort(results_audit, function(a, b) return a.score < b.score end)
    local median = results_audit[math.floor(#results_audit / 2)].score

    if not silent then
        print(string.format("\n=== Simulation: %s (Median Score: %.2f) ===", locale, median))
        print(string.format("**Average Typo Score: %.2f**", totalTypoScore / count))
        print(string.format("**Average ID Velocity: %.2f**", totalVelocity / count))
    end
    return totalTypoScore / count, totalVelocity / count, median, results_audit
end

local function RunRandomStressTest(locale, count)
    local base = Spellcheck.Dictionaries["enBase"]
    local testData = {}
    local wordsFound = 0
    while wordsFound < count do
        local id = math.random(1, 133694)
        local w = base.words[id]
        if w and #w > 3 then
            testData[GenerateOrganicTypo(w)] = w
            wordsFound = wordsFound + 1
        end
    end
    return RunTests(locale, testData, true)
end

-- 7. Execute Simulations
-- 7. Execute Simulations
local all_battery_reports = {}

local function RunBattery(name, locale, iterations, count)
    count = count or 5000
    SetSimulationLocale(locale)
    print(string.format("\n--- Battery: %s (%s, %d words each) ---", name, locale, count))

    local battery_results = {}
    local summary_lines = {}
    table.insert(summary_lines, string.format("### Battery: %s (%s)", name, locale))
    table.insert(summary_lines, "| Iteration | Avg Typo Score | Avg Velocity | Median |")
    table.insert(summary_lines, "|-----------|----------------|--------------|--------|")

    for i = 1, iterations do
        local score, vel, med, audit = RunRandomStressTest(locale, count)
        print(string.format("  Iteration %d: Score=%.2f, Vel=%.2f, Med=%d", i, score, vel, med))
        table.insert(summary_lines, string.format("| %-9d | %-14.2f | %-12.2f | %-6d |", i, score, vel, med))
        for _, a in ipairs(audit) do table.insert(battery_results, a) end
    end

    table.sort(battery_results, function(a, b) return a.score < b.score end)

    local report = {
        name = name,
        summary = table.concat(summary_lines, "\n"),
        top = {},
        worst = {}
    }

    for i = 1, math.min(500, #battery_results) do
        local r = battery_results[i]
        table.insert(report.top,
            string.format("  - %s -> %s (Rank: %s, Score: %d)", r.input, r.expected, r.rank, r.score))
    end
    for i = #battery_results, math.max(1, #battery_results - 499), -1 do
        local r = battery_results[i]
        table.insert(report.worst,
            string.format("  - %s -> %s (Rank: %s, Score: %d)", r.input, r.expected, r.rank, r.score))
    end
    table.insert(all_battery_reports, report)
end

RunBattery("Regional enGB", "enGB", 3, 10000)
RunBattery("Regional enUS", "enUS", 3, 10000)
RunBattery("Universal Base", "enBase", 3, 10000)

-- Write final report
local f = io.open("tools/authoritative_report_1.2.5.md", "w")
f:write("# Authoritative Spellcheck Performance Report v1.2.5\n\n")
f:write("Total Words Tested: 90,000\n\n")
for _, b in ipairs(all_battery_reports) do
    f:write(b.summary .. "\n\n")
    f:write("#### Top 500 Best Results (Excerpts):\n")
    f:write(table.concat(b.top, "\n", 1, 50) .. "\n... (truncated to 50 for brevity, full data in memory dump) ...\n\n")
    f:write("#### Worst 500 Results:\n")
    f:write(table.concat(b.worst, "\n") .. "\n\n")
    f:write("---\n\n")
end
f:close()

print("\nOrganic Simulation Complete. Report written to tools/authoritative_report_1.2.5.md")
