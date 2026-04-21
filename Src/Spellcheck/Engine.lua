--[[
    Spellcheck/Engine.lua
    Misspelling detection, active word tracking, suggestion generation
    (with phonetic, keyboard proximity, n-gram, and adaptive learning
    scoring), Damerau-Levenshtein edit distance, and label formatting.
]]

local _, YapperTable  = ...
local Spellcheck      = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local Clamp           = Spellcheck.Clamp
local NormaliseWord   = Spellcheck.NormaliseWord
local NormaliseVowels = Spellcheck.NormaliseVowels  -- built-in fallback
local SuggestionKey   = Spellcheck.SuggestionKey
local IsWordByte      = Spellcheck.IsWordByte
local IsWordStartByte = Spellcheck.IsWordStartByte
local SCORE_WEIGHTS   = Spellcheck._SCORE_WEIGHTS
local RAID_ICONS      = Spellcheck._RAID_ICONS

-- Re-localise Lua globals.
local type            = type
local pairs           = pairs
local ipairs          = ipairs
local tostring        = tostring
local tonumber        = tonumber
local math_abs        = math.abs
local math_min        = math.min
local math_max        = math.max
local math_floor      = math.floor
local math_huge       = math.huge
local table_insert    = table.insert
local table_sort      = table.sort
local string_sub      = string.sub
local string_byte     = string.byte
local string_lower    = string.lower
local string_gsub     = string.gsub
local string_upper    = string.upper
local string_match    = string.match
local string_char     = string.char
local string_format   = string.format

-- ---------------------------------------------------------------------------
-- Engine accessor helper
-- ---------------------------------------------------------------------------
-- Returns the active language engine if one is registered for the current
-- locale's family, otherwise a synthetic table that delegates to the
-- built-in English helpers so all call-sites can be written uniformly.
local VARIANT_RULES   = {
    { "or",  "our" }, { "our", "or" },
    { "ize", "ise" }, { "ise", "ize" },
    { "er", "re" }, { "re", "er" },
    { "og", "ogue" }, { "ogue", "og" },
    { "l", "ll" }, { "ll", "l" },
}

local _builtinEngine
local function GetEngineFor(self)
    local eng = self:GetActiveEngine()
    if eng then return eng end

    -- Lazily build the built-in fallback once.
    if not _builtinEngine then
        _builtinEngine = {
            GetPhoneticHash = function(w) return string_upper(w) end, -- Simple fallback
            NormaliseVowels = NormaliseVowels,
            HasVariantRules = true,
            VariantRules    = VARIANT_RULES,
            ScoreWeights    = nil,
            KBLayouts       = nil,
        }
    end
    return _builtinEngine
end


function Spellcheck:CollectMisspellings(text, dict)
    -- PRE_SPELLCHECK filter: external addons can strip custom markup etc.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SPELLCHECK", { text = text })
        if payload == false then return nil end
        text = payload.text
    end

    local out = {}
    local minLen = self:GetMinWordLength()
    local ignoreRanges = self:GetIgnoredRanges(text)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())

    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end

        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            local norm = NormaliseWord(word)
            if not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen)
                and not (ignoredSet and ignoredSet[norm])
                and not (addedSet and addedSet[norm])
                and not dict.set[norm]
                and not dict.set[word] then
                out[#out + 1] = { startPos = s, endPos = e, word = word }
            end
        else
            idx = idx + 1
        end
    end

    return out
end

function Spellcheck:ShouldCheckWord(word, minLen)
    if #word < minLen then return false end
    if word:find("%d") then return false end
    if word:find("[A-Za-z]") and word == word:upper() then return false end
    return true
end

function Spellcheck:GetIgnoredRanges(text)
    local ranges = {}
    local idx = 1
    while true do
        local s, e = text:find("|H.-|h.-|h", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|c%x%x%x%x%x%x%x%x.-|r", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|T.-|t", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|A.-|a", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end

    -- Ignore complete Raid Icons and custom markers
    local searchPos = 1
    while true do
        local s, e = text:find("{[^}]-}", searchPos)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        searchPos = e + 1
    end

    return ranges
end

function Spellcheck:IsRangeIgnored(startPos, endPos, ranges)
    for _, range in ipairs(ranges) do
        if startPos <= range.endPos and endPos >= range.startPos then
            return true
        end
    end
    return false
end

function Spellcheck:IsWordCorrect(word)
    if not word or word == "" then return false end
    local dict = self:GetDictionary()
    if not dict then return false end

    local norm = NormaliseWord(word)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())

    -- Correct if in dictionary (original or normalised) or in user-added set
    if dict.set[norm] or dict.set[word] or (addedSet and addedSet[norm]) then
        return true
    end
    -- Explicitly ignored words are treated as "correct" for learning purposes
    if ignoredSet and ignoredSet[norm] then
        return true
    end

    return false
end

function Spellcheck:ResolveImplicitTrace(force)
    if not self._implicitTrace or not self.EditBox then return end

    local trace = self._implicitTrace
    local text = self.EditBox:GetText() or ""
    local cursor = self.EditBox:GetCursorPosition() or #text
    local caret = cursor + 1

    -- If not forced, only resolve if the cursor has left the word boundaries
    -- (accounting for potential length changes).
    if not force then
        -- We use a slightly generous boundary check to handle active typing
        -- but trigger once they are clearly elsewhere.
        if caret >= trace.startPos and caret <= (trace.endPos + 1) then
            return -- Still inside or at boundary
        end
    end

    -- Dynamic Resolution: Re-scan the word at the trace position to find its
    -- current length.
    if #text >= trace.startPos then
        local s = trace.startPos
        local e = s
        while e <= #text do
            local b = text:byte(e)
            if not b or not IsWordByte(b) then break end
            e = e + 1
        end
        e = e - 1

        local currentWord = text:sub(s, e)
        if currentWord ~= "" and currentWord ~= trace.word then
            -- IsSaneWord guards against keyboard-smash or junk.
            if self:IsWordCorrect(currentWord) then
                if self.YALLM and self.YALLM.RecordImplicitCorrection then
                    local locale = self:GetLocale()
                    self.YALLM:RecordImplicitCorrection(trace.word, currentWord, trace.suggestions, locale)
                end
            end
        end
    end

    self._implicitTrace = nil -- Consume trace
end

function Spellcheck:UpdateActiveWord()
    if not self.EditBox then return end

    local text = self.EditBox:GetText() or ""
    local cursor = self.EditBox:GetCursorPosition() or #text
    local dict = self:GetDictionary()
    local prevWord = self.ActiveWord
    local prevSuggestions = self.ActiveSuggestions
    local prevIndex = self.ActiveIndex

    if not dict or text == "" then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    local wordInfo = self:GetWordAtCursor(text, cursor)

    -- Implicit learning: check if the user manually corrected without using a suggestion
    if self._implicitTrace then
        self:ResolveImplicitTrace(false) -- Non-forced check
    end

    if not wordInfo then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    if self:IsWordCorrect(wordInfo.word) then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    self.ActiveWord = wordInfo.word
    self.ActiveRange = { startPos = wordInfo.startPos, endPos = wordInfo.endPos }

    if self:IsSuggestionOpen() then
        local currentText = text or ""
        local locale = self:GetLocale()
        local userCache = self.UserDictCache[locale]
        local userRev = userCache and userCache._rev or nil

        local needCompute = false
        if self._textChangedFlag then
            needCompute = true
        elseif not self._lastSuggestionsText or self._lastSuggestionsText ~= currentText
            or self._lastSuggestionsLocale ~= locale
            or self._lastSuggestionsUserRev ~= userRev then
            needCompute = true
        end

        local suggestions = nil
        if needCompute then
            suggestions = self:GetSuggestions(self.ActiveWord)
            self._lastSuggestionsText = currentText
            self._lastSuggestionsLocale = locale
            self._lastSuggestionsUserRev = userRev
            self._textChangedFlag = false
        else
            suggestions = self.ActiveSuggestions or {}
        end

        if #suggestions == 0 then
            self:HideSuggestions()
        else
            self.ActiveSuggestions = suggestions
            if prevWord == self.ActiveWord and self:SuggestionsEqual(prevSuggestions, suggestions) then
                self.ActiveIndex = prevIndex or 1
            else
                self.ActiveIndex = 1
            end
            self:ShowSuggestions()
        end
    end
end

function Spellcheck:GetWordAtCursor(text, cursor)
    local caret = cursor + 1
    local ignoreRanges = self:GetIgnoredRanges(text)
    local minLen = self:GetMinWordLength()
    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end
        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            if caret >= s and caret <= (e + 1)
                and not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen) then
                return { word = word, startPos = s, endPos = e }
            end
        else
            idx = idx + 1
        end
    end
    return nil
end

-- ===== Suggestion helpers ===================

--- Collect prefix-indexed candidates from a dictionary (and its base if delta).
local function GatherPrefixCandidates(dict, base, firstChar)
    local out = {}
    local function add(d)
        local src = d.index and d.index[firstChar]
        if src then
            for _, v in ipairs(src) do
                if #out >= 2000 then break end
                out[#out + 1] = v
            end
        end
    end
    add(dict)
    if base then add(base) end
    return out
end

--- Collect normalised user-added words for the current locale.
local function GatherUserCandidates(self, locale)
    local out = {}
    local userDict = self:GetUserDict(locale)
    if userDict and type(userDict.AddedWords) == "table" then
        for _, uw in ipairs(userDict.AddedWords) do
            if type(uw) == "string" and uw ~= "" then
                local norm = NormaliseWord(uw)
                if norm ~= "" then out[#out + 1] = norm end
            end
        end
    end
    return out
end

--- Collect n-gram-scored candidates when the n-gram index is enabled.
local function GatherNgramCandidates(dict, base, lower, lowerLen, engine)
    local hits = {}
    local n = lowerLen < 5 and 2 or 3
    -- Use the engine's NormaliseVowels if it has one, otherwise the built-in.
    local normVowels = (engine and engine.NormaliseVowels) or NormaliseVowels
    local norm = normVowels(lower)

    local function addHits(node, wordsTable)
        if not node then return end
        local idx = node["ngramIndex" .. n]
        if not idx then return end
        for i = 1, (#norm - n + 1) do
            local g = string_sub(norm, i, i + n - 1)
            local posting = idx[g]
            if posting then
                for _, id in ipairs(posting) do
                    local key = (wordsTable == dict.words) and id or (-id)
                    hits[key] = (hits[key] or 0) + 1
                end
            end
        end
    end

    addHits(dict.ngramIndex2 and dict or nil, dict.words)
    if base then addHits(base, base.words) end

    local tmp = {}
    for key, cnt in pairs(hits) do
        local dObj = (key > 0) and dict or base
        local id = math_abs(key)
        local w = dObj.words[id]
        if w then
            local wLen = #w
            local lenDiff = math_abs(wLen - lowerLen)
            local score = (2 * cnt) / (lowerLen + wLen) - (lenDiff * 0.1)
            if string_byte(w, 1) == string_byte(lower, 1) then
                score = score + 0.5
            end
            tmp[#tmp + 1] = { word = w, score = score }
        end
    end
    table_sort(tmp, function(a, b)
        if a.score == b.score then return a.word < b.word end
        return a.score > b.score
    end)

    local out = {}
    for i = 1, math_min(#tmp, 500) do
        out[#out + 1] = tmp[i].word
    end
    return out
end

--- Collect phonetically similar candidates via the phonetic index.
local function GatherPhoneticCandidates(dict, lower, engine)
    local out = {}
    local phoneticHash = engine.GetPhoneticHash(lower)
    if phoneticHash == "" then return out, phoneticHash end
    local matches = dict.phonetics and dict.phonetics[phoneticHash]
    if matches then
        for _, id in ipairs(matches) do
            if #out >= 2000 then break end
            local w = dict.words[id]
            if w then out[#out + 1] = w end
        end
    end
    return out, phoneticHash
end

--- Build input-word metadata (letter bag + bigrams) into reusable scratch tables.
local function BuildInputMeta(self, lower)
    local bag = self._scratchBag
    if not bag then
        bag = {}; self._scratchBag = bag
    end
    for k in pairs(bag) do bag[k] = nil end
    for i = 1, #lower do
        local ch = string_byte(lower, i)
        bag[ch] = (bag[ch] or 0) + 1
    end

    local bigrams = self._scratchBigrams
    if not bigrams then
        bigrams = {}; self._scratchBigrams = bigrams
    end
    for k in pairs(bigrams) do bigrams[k] = nil end
    if #lower >= 2 then
        for i = 1, (#lower - 1) do
            local g = string_sub(lower, i, i + 1)
            bigrams[g] = (bigrams[g] or 0) + 1
        end
    end
    return bag, bigrams
end

--- Pre-compute a scoring context table that is shared across all candidates.
--- This avoids re-fetching config values and rebuilding lookup structures
--- inside the per-candidate scoring loop.
local function MakeScoringContext(self, dict, lower, inputBag, inputBigrams, phoneticHash, locale, engine)
    local lowerLen        = #lower
    local maxWrong        = self:GetMaxWrongLetters() or 4
    local lHasApostrophe  = lower:find("'", 1, true)
    local lFlat           = lHasApostrophe and string_gsub(lower, "'", "") or lower
    local isVariantLocale = (engine and engine.HasVariantRules) == true
    local variantRules    = (engine and engine.VariantRules) or {}

    -- Keyboard layout: prefer the engine's layouts, fall back to built-in.
    local kbLayouts       = (engine and engine.KBLayouts) or Spellcheck._KB_LAYOUTS

    -- Score weights: start from the built-in base and overlay engine overrides.
    local weights         = SCORE_WEIGHTS
    if engine and type(engine.ScoreWeights) == "table" then
        weights = {}
        for k, v in pairs(SCORE_WEIGHTS) do weights[k] = v end
        for k, v in pairs(engine.ScoreWeights) do weights[k] = v end
    end

    -- Pre-convert input word to byte array for proximity scan (reuse buffer)
    local lowerBytes = self._kbLowerBytes
    if not lowerBytes then
        lowerBytes = {}; self._kbLowerBytes = lowerBytes
    end
    for i = 1, lowerLen do lowerBytes[i] = string_byte(lower, i) end

    return {
        dict            = dict,
        lower           = lower,
        lowerLen        = lowerLen,
        maxWrong        = maxWrong,
        lHasApostrophe  = lHasApostrophe,
        lFlat           = lFlat,
        isVariantLocale = isVariantLocale,
        variantRules    = variantRules,
        kbLayouts       = kbLayouts,
        weights         = weights,
        lowerBytes      = lowerBytes,
        inputBag        = inputBag,
        inputBigrams    = inputBigrams,
        phoneticHash    = phoneticHash,
        locale          = locale,
        YALLM           = self.YALLM,
        -- closures that need self
        GetMeta         = function(candidate) return self:GetMeta(dict, candidate) end,
        EditDistance    = function(a, b, max) return self:EditDistance(a, b, max) end,
    }
end

-- The fallback VARIANT_RULES was moved to the top of the file to
-- correctly populate _builtinEngine on first use.

local function CommonPrefixLen(a, b)
    local len = math_min(#a, #b)
    for i = 1, len do
        if string_byte(a, i) ~= string_byte(b, i) then return i - 1 end
    end
    return len
end

local function LetterBagScore(ctx, candidate)
    local meta = ctx.GetMeta(candidate)
    if not meta or not meta.bag then return 999 end
    local score = 0
    for ch, cnt in pairs(meta.bag) do
        local inCnt = ctx.inputBag[ch] or 0
        local d = cnt - inCnt
        if d ~= 0 then score = score + math_abs(d) end
    end
    for ch, cnt in pairs(ctx.inputBag) do
        if not meta.bag[ch] then score = score + math_abs(cnt) end
    end
    return score
end

local function BigramOverlap(ctx, candidate)
    local meta = ctx.GetMeta(candidate)
    if not meta or not meta.bigrams then return 0 end
    local count = 0
    for g, cnt in pairs(meta.bigrams) do
        local inCnt = ctx.inputBigrams[g] or 0
        if inCnt > 0 then count = count + math_min(cnt, inCnt) end
    end
    return count
end

local function LocaleVariantBonus(ctx, candidate)
    if not ctx.isVariantLocale then return 0 end
    local input = ctx.lower
    for i = 1, #ctx.variantRules do
        local r = ctx.variantRules[i]
        if input:find(r[1], 1, true) then
            if string_gsub(input, r[1], r[2]) == candidate then
                return (i <= 2) and 5.0 or 3.5
            end
        end
    end
    return 0
end

--- Score a single candidate and append to the output list if it passes.
local function ScoreCandidate(ctx, out, candidate, dist, isPhonetic)
    local lower = ctx.lower
    local lowerLen = ctx.lowerLen
    local candidateLen = #candidate
    local lenDiff = math_abs(candidateLen - lowerLen)
    local prefix = CommonPrefixLen(lower, candidate)
    local bagScore = LetterBagScore(ctx, candidate)
    local bigramScore = BigramOverlap(ctx, candidate)
    local W = ctx.weights

    local longerPenalty = 0
    if candidateLen > lowerLen then
        local over = (candidateLen - lowerLen)
        local factor = 1 + ((bagScore / math_max(1, ctx.maxWrong)) * 0.5)
        longerPenalty = over * W.longerPenalty * factor
    end

    local score = dist
        + (lenDiff * W.lenDiff)
        + longerPenalty
        - (prefix * W.prefix)
        + (bagScore * W.letterBag)
        - (bigramScore * W.bigram)
        - (isPhonetic and 7.0 or 0)

    -- First-Character Anchor Bias
    if string_byte(candidate, 1) == string_byte(lower, 1) then
        score = score - W.firstCharBias
    end

    -- Vowel-Neutral Match Bonus
    if NormaliseVowels(candidate) == NormaliseVowels(lower) then
        score = score - W.vowelBonus
    end

    -- Phonetic Complexity Bonus
    if isPhonetic and candidateLen > lowerLen then
        score = score - ((candidateLen - lowerLen) * 0.75)
    end

    -- Apostrophe handling
    local cHasApostrophe = candidate:find("'", 1, true)
    if cHasApostrophe or ctx.lHasApostrophe then
        local cFlat = cHasApostrophe and string_gsub(candidate, "'", "") or candidate
        if cFlat == ctx.lFlat then
            score = score - 1.5
        else
            local flatDist = ctx.EditDistance(ctx.lFlat, cFlat, 3)
            if flatDist and flatDist < dist then
                score = score - ((dist - flatDist) * 0.8)
            end
        end
    end

    -- Locale variant bonus
    local variantBonus = LocaleVariantBonus(ctx, candidate)
    if variantBonus > 0 then score = score - variantBonus end

    -- Keyboard proximity bonus
    if dist <= 2 and lenDiff <= 1 and ctx.kbLayouts then
        -- Build or reuse the KB distance table for this context's layout.
        local layout    = Spellcheck:GetKeyboardLayout()
        local layouts   = ctx.kbLayouts
        local kbDist    = Spellcheck:_GetKBDistFromLayouts(layouts, layout)
        local proxScore = 0
        local proxCount = 0
        local scanLen   = math_min(lowerLen, candidateLen)
        for i = 1, scanLen do
            local lb = ctx.lowerBytes[i]
            local cb = string_byte(candidate, i)
            if lb ~= cb then
                if lb >= 97 and lb <= 122 and cb >= 97 and cb <= 122 then
                    local kd = kbDist[(lb - 97) * 26 + (cb - 97) + 1]
                    if kd < 1.5 then
                        proxScore = proxScore + (1.5 - kd)
                        proxCount = proxCount + 1
                    end
                end
            end
        end
        if proxCount > 0 then
            score = score - (proxScore * W.kbProximity)
        end
    end

    -- Exact-length preference
    local maxDist = (lowerLen <= 4) and 2 or 3
    if candidateLen == lowerLen then
        if bagScore <= ctx.maxWrong then
            score = score - (W.lenDiff * 1.5)
        else
            score = score + ((bagScore - ctx.maxWrong) * 0.5)
        end
    elseif lenDiff == 1 and dist == 1 then
        if ctx.isVariantLocale then
            if bagScore <= (ctx.maxWrong + 1) then
                score = score - (W.lenDiff * 1.0)
            end
        end
    end

    -- Personalised learning bonus
    local baseScore = score
    if ctx.YALLM and ctx.YALLM.GetBonus then
        score = score + ctx.YALLM:GetBonus(candidate, lower, ctx.phoneticHash, ctx.locale)
    end

    out[#out + 1] = { word = candidate, dist = dist, score = score, baseScore = baseScore, bag = bagScore }
end

--- Inject direct locale variant swaps (colour↔color etc.) into the output.
local function InjectLocaleVariants(ctx, out, seenCandidates)
    local lower = ctx.lower
    local dict = ctx.dict
    local maxDist = (ctx.lowerLen <= 4) and 2 or 3
    local function inject(variantSub, candSub)
        local varWord = string_gsub(lower, variantSub, candSub)
        if varWord ~= lower and dict.set[varWord] and not seenCandidates[varWord] then
            seenCandidates[varWord] = true
            local dist = ctx.EditDistance(lower, varWord, maxDist)
            if dist and dist <= maxDist then
                ScoreCandidate(ctx, out, varWord, dist, false)
            end
        end
    end
    for i = 1, #ctx.variantRules do
        inject(ctx.variantRules[i][1], ctx.variantRules[i][2])
    end
end

--- Generate transposition / deletion / replacement reshuffles and try them.
local function TryReshuffles(self, ctx, out, seenCandidates, checks, dynamicCap)
    local lower = ctx.lower
    local dict = ctx.dict
    local maxDist = (ctx.lowerLen <= 4) and 2 or 3
    local attempts = self:GetReshuffleAttempts() or 0
    if attempts <= 0 then return checks end

    local variants = {}
    local vseen = {}
    local maxWrong = ctx.maxWrong
    local function addIfAcceptable(v)
        if not v or v == lower then return end
        if vseen[v] or #variants >= attempts then return end
        local bagScore = LetterBagScore(ctx, v)
        if bagScore and bagScore <= (maxWrong * 2) then
            vseen[v] = true
            variants[#variants + 1] = v
        end
    end

    -- Adjacent transpositions
    for i = 1, (#lower - 1) do
        if #variants >= attempts then break end
        addIfAcceptable(
            string_sub(lower, 1, i - 1)
            .. string_sub(lower, i + 1, i + 1)
            .. string_sub(lower, i, i)
            .. string_sub(lower, i + 2)
        )
    end

    -- Single deletions
    for i = 1, #lower do
        if #variants >= attempts then break end
        addIfAcceptable(string_sub(lower, 1, i - 1) .. string_sub(lower, i + 1))
    end

    -- Single replacements using likely letters
    local alph = {}
    for k in pairs(dict.index) do alph[#alph + 1] = k end
    for i = 1, #lower do alph[#alph + 1] = string_sub(lower, i, i) end
    local alphSeen = {}
    local alphaList = {}
    for _, ch in ipairs(alph) do
        if not alphSeen[ch] then
            alphSeen[ch] = true; alphaList[#alphaList + 1] = ch
        end
    end
    for i = 1, #lower do
        if #variants >= attempts then break end
        for _, ch in ipairs(alphaList) do
            if #variants >= attempts then break end
            addIfAcceptable(string_sub(lower, 1, i - 1) .. ch .. string_sub(lower, i + 1))
        end
    end

    for _, var in ipairs(variants) do
        if checks > dynamicCap then break end
        if dict.set[var] and not seenCandidates[var] then
            seenCandidates[var] = true
            checks = checks + 1
            local dist = ctx.EditDistance(lower, var, maxDist)
            if dist and dist <= maxDist then
                ScoreCandidate(ctx, out, var, dist, false)
            end
        end
    end

    return checks
end

-- ===== Main suggestion entry point =========================================

function Spellcheck:GetSuggestions(word)
    -- Intercept Raid Icons
    if string_sub(word, 1, 1) == "{" then
        local suggestions = {}
        local lowerWord = string_lower(word)
        for _, icon in ipairs(RAID_ICONS) do
            if string_sub(string_lower(icon), 1, #lowerWord) == lowerWord then
                table_insert(suggestions, { word = icon, score = 0 })
            end
        end
        return suggestions
    end

    local dict = self:GetDictionary()
    if not dict then
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions no dictionary for locale")
        end
        return {}
    end

    local locale = self:GetLocale()
    local userCache = self.UserDictCache[locale]
    local userRev = userCache and userCache._rev or nil
    local maxCount = self:GetMaxSuggestions()
    local lower = NormaliseWord(word)
    local lowerLen = #lower
    local first = lower:sub(1, 1)
    local maxCandidates = (type(self.GetMaxCandidates) == "function") and self:GetMaxCandidates() or 1000

    -- Resolve the active language engine once for this suggestion pass.
    local engine = GetEngineFor(self)

    -- Suggestion cache: reuse result for the same normalised word+locale+userRev+maxCount.
    self._suggestionCache = self._suggestionCache or {}
    local sc = self._suggestionCache
    local cacheKey = lower .. "|" .. locale .. "|" .. tostring(userRev) .. "|" .. tostring(maxCount)
    if sc[cacheKey] then
        return sc[cacheKey]
    end

    -- Base dict if this is a delta
    local base                             = dict.extends and self.Dictionaries[dict.extends]

    -- ── Gather candidate lists ───────────────────────────────────────
    local prefixCandidates                 = GatherPrefixCandidates(dict, base, first)
    local addedCandidates                  = GatherUserCandidates(self, locale)

    local useNgram                         = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck
        and YapperTable.Config.Spellcheck.UseNgramIndex) or false
    local ngramCandidates                  = useNgram and GatherNgramCandidates(dict, base, lower, lowerLen, engine) or
    nil

    local phoneticCandidates, phoneticHash = GatherPhoneticCandidates(dict, lower, engine)

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions word='" .. tostring(word) ..
            "' lower='" .. tostring(lower) .. "' locale='" .. tostring(locale) ..
            "' prefixCandidates=" .. tostring(#prefixCandidates))
    end

    -- ── Build scoring context ────────────────────────────────────────
    local inputBag, inputBigrams = BuildInputMeta(self, lower)
    local ctx = MakeScoringContext(self, dict, lower, inputBag, inputBigrams, phoneticHash, locale, engine)

    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    local out = {}
    local maxDist = (lowerLen <= 4) and 2 or 3
    local maxLenDiff = maxDist + 1

    local dynamicCap = maxCandidates
    if lowerLen <= 4 then
        dynamicCap = math_min(maxCandidates * 4, 5000)
    end

    -- ── Candidate evaluation pipeline ────────────────────────────────
    local checks = 0
    local seenCandidates = {}

    local function tryCandidates(list, isPhonetic)
        for _, candidate in ipairs(list) do
            if #out >= 100 then return true end
            if not seenCandidates[candidate] then
                seenCandidates[candidate] = true
                if not (ignoredSet and ignoredSet[candidate]) then
                    local lenDiff = math_abs(#candidate - lowerLen)
                    local isUserWord = addedSet and addedSet[candidate]
                    local isLongPrefix = isUserWord and (#candidate > lowerLen) and
                        (string_sub(candidate, 1, lowerLen) == lower)

                    if isPhonetic or lenDiff <= maxLenDiff or isLongPrefix then
                        checks = checks + 1
                        if not isPhonetic and checks > dynamicCap then return true end

                        local effectiveMax = isPhonetic and 6 or maxDist
                        local dist = isLongPrefix and lenDiff or self:EditDistance(lower, candidate, effectiveMax)
                        if dist and (dist <= effectiveMax or isLongPrefix) then
                            ScoreCandidate(ctx, out, candidate, dist, isPhonetic)
                        end
                    end
                end
            end
        end
        return false
    end

    local aborted = false

    -- 1. User-added words (unconditional, before array caps)
    if addedCandidates and #addedCandidates > 0 then
        aborted = tryCandidates(addedCandidates)
    end

    -- 2. Phonetic candidates (high priority)
    if not aborted and #phoneticCandidates > 0 then
        aborted = tryCandidates(phoneticCandidates, true)
    end

    -- 3. Direct locale variant injection (only when the active engine has variant rules)
    if ctx.isVariantLocale then
        InjectLocaleVariants(ctx, out, seenCandidates)
    end

    -- 4. Bucket prefix candidates (2-char > 1-char > other)
    local pref2 = {}
    local pref1 = {}
    local other = {}
    local p2 = string_sub(lower, 1, 2) or ""
    local p1 = string_sub(lower, 1, 1) or ""
    local catCount = 0
    for _, c in ipairs(prefixCandidates) do
        catCount = catCount + 1
        if catCount > 5000 then break end
        if string_sub(c, 1, 2) == p2 and p2 ~= "" then
            pref2[#pref2 + 1] = c
        elseif string_sub(c, 1, 1) == p1 then
            pref1[#pref1 + 1] = c
        else
            other[#other + 1] = c
        end
    end

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify(string_format(
            "Spellcheck:GetSuggestions buckets p2=%d p1=%d other=%d dynamicCap=%d maxDist=%d maxLenDiff=%d",
            #pref2, #pref1, #other, dynamicCap, maxDist, maxLenDiff))
    end

    -- 5. N-gram candidates
    if not aborted and ngramCandidates and #ngramCandidates > 0 then
        aborted = tryCandidates(ngramCandidates)
    end

    -- 6. Prefix buckets (ordered by relevance)
    if not aborted then aborted = tryCandidates(pref2) end
    if not aborted then aborted = tryCandidates(pref1) end
    if not aborted then tryCandidates(other) end

    -- 7. Reshuffle fallback
    if not aborted and #out < maxCount and checks < dynamicCap then
        checks = TryReshuffles(self, ctx, out, seenCandidates, checks, dynamicCap)
    end

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions finished checks=" ..
            tostring(checks) .. " candidatesFound=" .. tostring(#out))
    end

    -- ── Sort + output ────────────────────────────────────────────────
    table_sort(out, function(a, b)
        if a.score == b.score then
            if a.dist == b.dist then return a.word < b.word end
            return a.dist < b.dist
        end
        return a.score < b.score
    end)

    local final = {}
    local poolSize = math_min(maxCount * 3, #out)
    for i = 1, poolSize do
        local o = out[i]
        final[i] = { kind = "word", value = o.word, score = o.score, baseScore = o.baseScore }
    end

    -- Add optional actions
    local addedSet2, ignoredSet2 = self:GetUserSets(self:GetLocale())
    if word and word ~= "" then
        local norm = NormaliseWord(word)
        if not (addedSet2 and addedSet2[norm]) then
            final[#final + 1] = { kind = "add", value = word }
        end
        if not (ignoredSet2 and ignoredSet2[norm]) then
            final[#final + 1] = { kind = "ignore", value = word }
        end
    end

    -- Update suggestion cache
    -- Mirror capitalisation: if the user's original word started with an
    -- uppercase letter, capitalise the first letter of every word suggestion.
    -- This preserves sentence-start capitalisation and conscious proper nouns.
    local wb = string_byte(word, 1)
    if wb and wb >= 65 and wb <= 90 then
        for _, entry in ipairs(final) do
            if entry.kind == "word" then
                entry.value = string_upper(string_sub(entry.value, 1, 1)) .. string_sub(entry.value, 2)
            end
        end
    end

    -- ── Compound split detection ─────────────────────────────────────────
    -- Check if the misspelled token is two valid dictionary words run together
    -- (e.g. "I'msupposed" → "I'm supposed"). Exact splits only; YALLM is
    -- intentionally bypassed for these entries since both halves are already
    -- valid words and there is nothing for the learner to remember.
    local minSplitLen = math_max(2, self:GetMinWordLength())
    if lowerLen > minSplitLen * 2 then
        local splitResults = {}
        for i = minSplitLen, lowerLen - minSplitLen do
            local left  = lower:sub(1, i)
            local right = lower:sub(i + 1)
            if self:IsWordCorrect(left) and self:IsWordCorrect(right) then
                splitResults[#splitResults + 1] = {
                    kind  = "split",
                    value = word:sub(1, i) .. " " .. word:sub(i + 1),
                }
                if #splitResults >= 3 then break end
            end
        end
        if #splitResults > 0 then
            local nSplits = #splitResults
            for i = #final, 1, -1 do
                final[i + nSplits] = final[i]
            end
            for i, s in ipairs(splitResults) do
                final[i] = s
            end
        end
    end

    local cacheCap = (type(self.GetSuggestionCacheSize) == "function") and self:GetSuggestionCacheSize() or 50
    if cacheCap > 0 then
        local count = 0
        for _ in pairs(sc) do count = count + 1 end
        if count >= cacheCap then
            wipe(sc)
        end
        sc[cacheKey] = final
    end

    return final
end

function Spellcheck:EditDistance(a, b, maxDist)
    if a == b then return 0 end
    local lenA = #a
    local lenB = #b
    if math_abs(lenA - lenB) > (maxDist or 0) then return nil end

    -- Convert to byte arrays once to avoid string.sub in the inner loop
    local aBytes = self._ed_aBytes
    if not aBytes then
        aBytes = {}; self._ed_aBytes = aBytes
    end
    local bBytes = self._ed_bBytes
    if not bBytes then
        bBytes = {}; self._ed_bBytes = bBytes
    end
    for i = 1, lenA do aBytes[i] = string_byte(a, i) end
    for j = 1, lenB do bBytes[j] = string_byte(b, j) end

    local prev = self._ed_prev
    local cur = self._ed_cur
    local prevPrev = self._ed_prev_prev

    -- init prev row
    for j = 0, lenB do prev[j] = j end

    for i = 1, lenA do
        cur[0] = i
        local ai = aBytes[i]
        local minRow = i

        local jstart = 1
        local jend = lenB
        if maxDist then
            jstart = math_max(1, i - maxDist)
            jend = math_min(lenB, i + maxDist)
        end

        if jstart > 1 then cur[jstart - 1] = math_huge end

        for j = jstart, jend do
            local cost = (ai == bBytes[j]) and 0 or 1
            local left = (cur[j - 1] or math_huge) + 1
            local above = (prev[j] or math_huge) + 1
            local diag = (prev[j - 1] or math_huge) + cost
            local val = left
            if above < val then val = above end
            if diag < val then val = diag end
            -- transposition check
            if i > 1 and j > 1 then
                if ai == bBytes[j - 1] and aBytes[i - 1] == bBytes[j] then
                    local prevPrevVal = prevPrev[j - 2] or math_huge
                    if prevPrevVal + 1 < val then val = prevPrevVal + 1 end
                end
            end
            cur[j] = val
            if val < minRow then minRow = val end
        end

        if minRow > (maxDist or 0) then return nil end

        -- O(1) swap of buffers
        self._ed_prev_prev, self._ed_prev, self._ed_cur = self._ed_prev, self._ed_cur, self._ed_prev_prev
        prevPrev = self._ed_prev_prev
        prev = self._ed_prev
        cur = self._ed_cur
    end

    return prev[lenB]
end

function Spellcheck:FormatSuggestionLabel(entry, index)
    if type(entry) == "string" then
        return index .. ". " .. entry
    end
    if type(entry) ~= "table" then
        return index .. ". -"
    end
    if entry.kind == "split" then
        return index .. ". Split: " .. (entry.value or "")
    end
    if entry.kind == "add" then
        return index .. ". Add \"" .. (entry.value or "") .. "\" to dictionary"
    end
    if entry.kind == "ignore" then
        return index .. ". Ignore \"" .. (entry.value or "") .. "\""
    end
    return index .. ". " .. (entry.value or entry.word or "")
end

return Spellcheck
