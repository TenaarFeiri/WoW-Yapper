-- ===========================================================================
-- THE YAPPER WORD GAME: MAN vs MACHINE (LUA EDITION)
-- ===========================================================================

local SCORE_WEIGHTS = {
    lenDiff       = 3.0,
    longerPenalty = 2.0,
    prefix        = 1.5,
    letterBag     = 1.0,
    bigram        = 1.5,
    kbProximity   = 1.0,
    firstCharBias = 1.5,
    vowelBonus    = 2.5,
}

local KB_LAYOUT = {
    q = { 0, 0 }, w = { 1, 0 }, e = { 2, 0 }, r = { 3, 0 }, t = { 4, 0 }, y = { 5, 0 }, u = { 6, 0 }, i = { 7, 0 }, o = { 8, 0 }, p = { 9, 0 },
    a = { 0.25, 1 }, s = { 1.25, 1 }, d = { 2.25, 1 }, f = { 3.25, 1 }, g = { 4.25, 1 }, h = { 5.25, 1 }, j = { 6.25, 1 }, k = { 7.25, 1 }, l = { 8.25, 1 },
    z = { 0.75, 2 }, x = { 1.75, 2 }, c = { 2.75, 2 }, v = { 3.75, 2 }, b = { 4.75, 2 }, n = { 5.75, 2 }, m = { 6.75, 2 }
}

-- ---------------------------------------------------------------------------
-- Mock Yapper Environment
-- ---------------------------------------------------------------------------
local Dictionary = { words = {}, phonetics = {} }
_G.YapperTable = {
    Spellcheck = {
        RegisterDictionary = function(_, locale, builder)
            local d = builder()
            Dictionary.words = d.words
            Dictionary.phonetics = d.phonetics
        end
    }
}

-- ---------------------------------------------------------------------------
-- Scoring Heuristics (Ported from Spellcheck.lua)
-- ---------------------------------------------------------------------------

local function GetPhoneticHash(word)
    local hash = word:upper()
    hash = hash:gsub("[^%a]", "")
    hash = hash:gsub("(%a)%1", "%1")
    hash = hash:gsub("GHT", "T"):gsub("PH", "F"):gsub("KN", "N"):gsub("GN", "N"):gsub("WR", "R"):gsub("CH", "K"):gsub("SH", "X"):gsub("C", "K"):gsub("Q", "K"):gsub("X", "KS"):gsub("Z", "S")
    if hash:sub(-2) == "GH" then
        hash = hash:sub(1, -3) .. "F"
    else
        hash = hash:gsub("GH", "")
    end
    if hash == "" then return "" end
    local first = hash:sub(1, 1)
    local rest = hash:sub(2):gsub("[AEIOUY]", "")
    return first .. rest
end

local function Levenshtein(s, t)
    local d = {}
    local len_s, len_t = #s, #t
    for i = 0, len_s do d[i] = { [0] = i } end
    for j = 0, len_t do d[0][j] = j end
    for i = 1, len_s do
        for j = 1, len_t do
            local cost = (s:sub(i, i) == t:sub(j, j) and 0 or 1)
            d[i][j] = math.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
            if i > 1 and j > 1 and s:sub(i, i) == t:sub(j-1, j-1) and s:sub(i-1, i-1) == t:sub(j, j) then
                d[i][j] = math.min(d[i][j], d[i-2][j-2] + cost)
            end
        end
    end
    return d[len_s][len_t]
end

local function GetBagScore(s1, s2)
    local counts = {}
    for i = 1, #s1 do
        local c = s1:sub(i, i):lower()
        counts[c] = (counts[c] or 0) + 1
    end
    for i = 1, #s2 do
        local c = s2:sub(i, i):lower()
        counts[c] = (counts[c] or 0) - 1
    end
    local score = 0
    for _, v in pairs(counts) do score = score + math.abs(v) end
    return score
end

local function GetProximityBonus(s1, s2)
    local bonus = 0
    local min_len = math.min(#s1, #s2)
    for i = 1, min_len do
        local c1, c2 = s1:sub(i, i):lower(), s2:sub(i, i):lower()
        if c1 ~= c2 and KB_LAYOUT[c1] and KB_LAYOUT[c2] then
            local p1, p2 = KB_LAYOUT[c1], KB_LAYOUT[c2]
            local dist = ((p1[1]-p2[1])^2 + (p1[2]-p2[2])^2)^0.5
            if dist < 1.5 then bonus = bonus + (1.5 - dist) end
        end
    end
    return bonus
end

local function ScoreCandidate(candidate, target)
    local dist = Levenshtein(candidate, target)
    local bag = GetBagScore(candidate, target)
    local lenDiff = math.abs(#candidate - #target)
    
    local score = dist * 1.25
    score = score + (lenDiff * SCORE_WEIGHTS.lenDiff)
    score = score + (bag * SCORE_WEIGHTS.letterBag)
    
    if candidate:sub(1,1):lower() == target:sub(1,1):lower() then
        score = score - SCORE_WEIGHTS.firstCharBias
    end
    
    if GetPhoneticHash(candidate) == GetPhoneticHash(target) then
        score = score - SCORE_WEIGHTS.vowelBonus
    end
    
    local prox = GetProximityBonus(candidate, target)
    score = score - (prox * SCORE_WEIGHTS.kbProximity)
    
    return score
end

-- ===========================================================================
-- COMPETITOR 3: THE GEMINI ANAGRAM AI
-- ===========================================================================
local GeminiAI = {
    index = {},
    trained = false
}

-- Sorts a string alphabetically (e.g., "muscles" -> "celmssu")
function GeminiAI:Hash(word)
    local chars = {}
    for i = 1, #word do chars[i] = word:sub(i, i):lower() end
    table.sort(chars)
    return table.concat(chars)
end

-- Pre-computes the entire dictionary in O(N) time
function GeminiAI:Train(dictWords)
    print("Training Gemini AI (Anagram Hashing)...")
    local start = os.clock()
    for _, w in ipairs(dictWords) do
        local h = self:Hash(w)
        self.index[h] = self.index[h] or {}
        table.insert(self.index[h], w)
    end
    print(string.format("Gemini AI Trained in %.2fs", os.clock() - start))
    self.trained = true
end

-- O(1) Lookup
function GeminiAI:Guess(scrambled)
    local h = self:Hash(scrambled)
    local matches = self.index[h]
    if matches and #matches > 0 then
        -- If multiple valid English anagrams exist (e.g., "listen" and "silent"),
        -- just return the first one we find.
        return matches[1] 
    end
    return "IDK"
end

-- ---------------------------------------------------------------------------
-- Game Loop
-- ---------------------------------------------------------------------------

local function Scramble(word)
    local letters = {}
    for i = 1, #word do letters[i] = word:sub(i, i):lower() end
    for i = #letters, 2, -1 do
        local j = math.random(i)
        letters[i], letters[j] = letters[j], letters[i]
    end
    return table.concat(letters)
end

math.randomseed(os.time())

print("Loading dictionary...")
-- We execute the dictionary file; it calls RegisterDictionary
-- In Lua 5.1/WoW context, we can use dofile or loadfile
local chunk = loadfile("Src/Spellcheck/Dicts/enBase.lua")
if not chunk then error("Failed to load enBase.lua") end
chunk(nil, YapperTable) -- Pass YapperTable as the second arg

local words = Dictionary.words
if #words == 0 then error("Dictionary is empty!") end

GeminiAI:Train(words)
local player_score = 0
local algo_score = 0
local gemini_score = 0
local target_score = 5
local round = 1

print("\n" .. string.rep("=", 60))
print("THE YAPPER REMATCH: MAN vs MACHINE vs GEMINI (LUA)")
print("First to " .. target_score .. " wins.")
print(string.rep("=", 60) .. "\n")

while player_score < target_score and algo_score < target_score and gemini_score < target_score do
    local actual = words[math.random(#words)]
    -- Avoid very short words for better gameplay
    while #actual < 5 or actual:find("'") do
        actual = words[math.random(#words)]
    end
    
    local scrambled = Scramble(actual)
    
    print("ROUND " .. round)
    print("Scrambled Word: " .. scrambled)
    io.write("Your Guess? > ")
    io.stdout:flush()
    
    local start_time = os.clock()
    local guess = io.read()
    if not guess or guess == "" then break end
    guess = guess:lower()
    
    -- Algorithm Competitor logic
    -- We'll scan 1000 random words + the actual target to simulate the candidate pool
    local best_algo_guess = ""
    local best_algo_score = 999
    
    for i = 1, 1000 do
        local cand = words[math.random(#words)]
        local s = ScoreCandidate(cand, scrambled)
        if s < best_algo_score then
            best_algo_score = s
            best_algo_guess = cand
        end
    end
    -- Ensure actual word is considered
    local s_actual = ScoreCandidate(actual, scrambled)
    if s_actual < best_algo_score then
        best_algo_score = s_actual
        best_algo_guess = actual
    end

    local gemini_start = os.clock()
    local gemini_guess = GeminiAI:Guess(scrambled)
    local gemini_time = os.clock() - gemini_start

    print(string.format("\nCorrection took: %.2fs (Yapper) | %.5fs (Gemini)", os.clock() - start_time, gemini_time))
    print("Correct Word:  " .. actual)
    print("Human Guess:   " .. guess)
    print("Yapper Algo:   " .. best_algo_guess .. " (Score: " .. string.format("%.2f", best_algo_score) .. ")")
    print("Gemini AI:     " .. gemini_guess)
    
    local win_p = (guess == actual:lower())
    local win_a = (best_algo_guess:lower() == actual:lower())
    local win_g = (gemini_guess:lower() == actual:lower())
    
    local round_result = ""
    if win_p then player_score = player_score + 1 end
    if win_a then algo_score = algo_score + 1 end
    if win_g then gemini_score = gemini_score + 1 end

    if win_p and win_a and win_g then
        print(">>> TRIPLE DRAW!")
    elseif win_p or win_a or win_g then
        local winners = {}
        if win_p then table.insert(winners, "HUMAN") end
        if win_a then table.insert(winners, "YAPPER") end
        if win_g then table.insert(winners, "GEMINI") end
        print(">>> POINT TO: " .. table.concat(winners, ", "))
    else
        print(">>> ALL FAILED!")
    end
    
    print("SCORE: HUMAN " .. player_score .. " - YAPPER " .. algo_score .. " - GEMINI " .. gemini_score .. "\n")
    round = round + 1
end

if player_score >= target_score then
    print("CONGRATULATIONS! HUMANITY SAVED.")
elseif gemini_score >= target_score then
    print("GEMINI AI DOMINATION. RESISTANCE IS FUTILE.")
else
    print("THE YAPPER ALGORITHM PREVAILS. SYSTEM STABLE.")
end
