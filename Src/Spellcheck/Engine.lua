--[[
    Spellcheck/Engine.lua
    Misspelling detection, active word tracking, suggestion generation
    (with phonetic, keyboard proximity, n-gram, and adaptive learning
    scoring), Damerau-Levenshtein edit distance, and label formatting.
]]

local _, YapperTable  = ...
local Spellcheck      = YapperTable.Spellcheck


-- Re-localise shared helpers from hub.  NormaliseWord / NormaliseVowels /
-- IsWordByte / IterWords are engine-delegating closures: they resolve the
-- ACTIVE locale's language engine on each call.
local NormaliseWord   = Spellcheck.NormaliseWord
local IsWordByte      = Spellcheck.IsWordByte
local IsDebugEnabled  = Spellcheck.IsDebugEnabled
local IterWords       = Spellcheck.IterWords
local SCORE_WEIGHTS   = Spellcheck._SCORE_WEIGHTS
local RAID_ICONS      = Spellcheck._RAID_ICONS

local type            = type
local pairs           = pairs
local ipairs          = ipairs
local tostring        = tostring
local tonumber        = tonumber
local math_abs        = math.abs
local math_min        = math.min
local math_max        = math.max
local math_huge       = math.huge
local table_insert    = table.insert
local table_sort      = table.sort
local string_sub      = string.sub
local string_byte     = string.byte
local string_lower    = string.lower
local string_gsub     = string.gsub
local string_upper    = string.upper
local string_format   = string.format
local rawget          = rawget

local Utils = YapperTable.Utils

-- ---------------------------------------------------------------------------
-- Engine accessor
-- ---------------------------------------------------------------------------
-- There is no built-in language engine: a locale only spellchecks when its
-- dictionary addon has registered a contract-valid engine for its family.
-- Callers obtain the engine via self:GetActiveEngine() / _EngineForLocale.


function Spellcheck:CollectMisspellings(text, dict)
    -- PRE_SPELLCHECK filter: external addons can strip custom markup etc.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SPELLCHECK", { text = text })
        if payload == false then return nil end
        text = payload.text
    end

    local out = {}
    if not dict then return out end
    local minLen = self:GetMinWordLength()
    local ignoreRanges = self:GetIgnoredRanges(text)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    local engine = self:GetActiveEngine()

    local isSlashCommand = (text:match("^%s*/") ~= nil)
    local emotePickerVisible = false
    if isSlashCommand and YapperTable.Emotes then
        emotePickerVisible = YapperTable.Emotes:IsActive() or
        (YapperTable.Emotes.HintFrame and YapperTable.Emotes.HintFrame:IsShown())
    end
    local skipFirstWord = isSlashCommand and emotePickerVisible
    local isFirstWord = true

    for s, e, word in IterWords(text) do
        local shouldAdd = true
        if isFirstWord then
            isFirstWord = false
            if skipFirstWord then
                shouldAdd = false
            end
        end

        if shouldAdd
            and not self:IsRangeIgnored(s, e, ignoreRanges)
            and self:ShouldCheckWord(word, minLen, engine)
            and not self:IsWordCorrect(word) then
            out[#out + 1] = { startPos = s, endPos = e, word = word }
        end
    end

    return out
end

--- Scans text for words recognized via affix-stripping.
--- These are candidates for auto-learning in YAS.
function Spellcheck:CollectAffixMatches(text, dict)
    local out = {}
    if not text or text == "" then return out end
    local engine = self:GetActiveEngine()

    for s, e, word in IterWords(text) do
        if self:ShouldCheckWord(word, 3, engine) then
            local isCorrect, isAffix = self:IsWordCorrect(word)
            if isCorrect and isAffix then
                out[#out + 1] = { startPos = s, endPos = e, word = word }
            end
        end
    end

    return out
end

--- Word-shape gate: should this token be spellchecked at all?
--- The core default drops sub-minimum words, digits and SHOUTING; an engine
--- may replace the judgement entirely via ShouldCheckWord.
--- @param engine table|nil  pre-resolved engine (hot paths pass this in)
function Spellcheck:ShouldCheckWord(word, minLen, engine)
    if engine == nil then engine = self:GetActiveEngine() end
    if engine and engine.ShouldCheckWord then
        return self:_SafeEngineCall(engine, "ShouldCheckWord", false, word, minLen) == true
    end
    if #word < minLen then return false end
    if word:find("%d") then return false end
    if word:find("[A-Za-z]") and word == word:upper() then return false end
    return true
end

-- Punctuation that "closes" a word in the core default: a committed boundary
-- AND a snap-back target (an auto-inserted space hops after it).
local SNAPBACK_BYTES = {
    [46] = true, -- .
    [44] = true, -- ,
    [33] = true, -- !
    [63] = true, -- ?
    [59] = true, -- ;
    [58] = true, -- :
}

--- Classify the byte at `pos` (1-based) of canonical `text` for word-boundary
--- purposes.  An engine may override via the optional ClassifyBoundary
--- contract field; nil/"" means "no opinion" and falls through to the core
--- default below, which encodes English conventions:
---
---   "commit" — boundary that completes a word (space, newline)
---   "close"  — commit boundary that also snaps an auto-inserted space to
---              AFTER itself (.,!?;: and a parity-closing '"')
---   "open"   — opens a quote/span; not a word boundary; an auto-inserted
---              space before it stays (opening '"' under English parity)
---   "none"   — any other byte; not a word boundary
---
--- '"' is ambiguous in English: it opens or closes a quotation.  Parity of
--- the '"' bytes before `pos` decides — odd means one is unclosed, so this
--- one closes (boundary); even means it opens (not a boundary).  Completed
--- quote pairs earlier in the text cancel out automatically.
function Spellcheck:ClassifyBoundary(text, pos)
    if type(text) ~= "string" or type(pos) ~= "number" then return "none" end
    local engine = self:GetActiveEngine()
    if engine and engine.ClassifyBoundary then
        local r = self:_SafeEngineCall(engine, "ClassifyBoundary", false, text, pos)
        if r == "commit" or r == "close" or r == "open" or r == "none" then
            return r
        end
        -- nil/""/invalid: no opinion — core default below.
    end
    local b = string_byte(text, pos)
    if not b then return "none" end
    if b == 32 or b == 10 or b == 13 then return "commit" end
    if SNAPBACK_BYTES[b] then return "close" end
    if b == 34 then -- '"'
        local parity = 0
        for i = 1, pos - 1 do
            if string_byte(text, i) == 34 then parity = 1 - parity end
        end
        if parity == 1 then return "close" end
        return "open"
    end
    return "none"
end

function Spellcheck:GetIgnoredRanges(text)
    -- Called twice per spellcheck pass on identical text and does five
    -- full-text scans, so memoize on the text itself; the one-entry cache
    -- invalidates automatically when the text changes.
    if text == self._ignoredRangesText and self._ignoredRangesCache then
        return self._ignoredRangesCache
    end

    local ranges = {}
    local idx = 1
    while true do
        local s, e = text:find("|cn[^:]*:|H.-|h.-|h", idx)
        if not s then break end
        if text:sub(e + 1, e + 2) == "|r" then
            e = e + 2
        end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end

    idx = 1
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

    self._ignoredRangesText = text
    self._ignoredRangesCache = ranges
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

    local locale = self:GetLocale()
    local engine = self:GetActiveEngine()
    local norm = (engine and engine.NormaliseWord or NormaliseWord)(word)
    local addedSet, ignoredSet = self:GetUserSets(locale)

    -- 1. Check user dictionary overrides (Manual Add/Ignore)
    if (addedSet and addedSet[norm]) or (ignoredSet and ignoredSet[norm]) then
        return true
    end

    -- 2. Check base dictionary + global blocklist
    if dict.set[norm] or dict.set[word] then
        -- Even if in base dictionary, check if blocked by engine
        if self:IsWordBlocked(norm, locale, true) then
            return false
        end
        return true
    end

    -- 3. Affix-stripping fallback (engine-owned; guarded: a faulting engine
    --    is purged along with its bound dictionaries)
    if engine and engine.StripAffixes then
        local base = self:_SafeEngineCall(engine, "StripAffixes", true, norm, dict)
        if base then
            -- The stripped root must also clear the blocklist.
            if not self:IsWordBlocked(base, locale, true) then
                return true, true -- second return flags an affix match
            end
        end
    end

    return false
end

function Spellcheck:ResolveImplicitTrace(force)
    if not self._implicitTrace or not self.EditBox then return end

    local trace = self._implicitTrace
    local text, cursor = YapperTable.Recolour.CanonicalTextAndCursor(self.EditBox)
    local caret = cursor + 1

    -- Unless forced, only resolve once the cursor has clearly left the word
    -- (the boundary is generous to tolerate active typing).
    if not force then
        if caret >= trace.startPos and caret <= (trace.endPos + 1) then
            return -- still inside or at boundary
        end
    end

    -- Re-scan the traced position; the word may have changed length.
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
            -- Only learn when the user retyped it into a real word.
            if self:IsWordCorrect(currentWord) then
                if self.YAS and self.YAS.RecordImplicitCorrection then
                    local locale = self:GetLocale()
                    self.YAS:RecordImplicitCorrection(trace.word, currentWord, trace.suggestions, locale)
                end
            end
        end
    end

    self._implicitTrace = nil -- Consume trace
end

function Spellcheck:UpdateActiveWord()
    if not self.EditBox then return end

    local text, cursor = YapperTable.Recolour.CanonicalTextAndCursor(self.EditBox)
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

    -- If the user retyped a misspelling without picking a suggestion, that
    -- manual fix is worth learning (implicit trace).
    if self._implicitTrace then
        self:ResolveImplicitTrace(false)
    end

    self._revertCorrection = nil

    if not wordInfo then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    if YapperAPI:CheckWord(wordInfo.word) then
        -- A word we autocorrected stays "active" so the suggestion popup
        -- can offer "Restore '<original>'" while the correction is live.
        local ac = self.Autocorrect
        local corr = ac and ac.LiveCorrectionAt
            and ac:LiveCorrectionAt(self.EditBox, wordInfo.startPos, wordInfo.endPos)
        if not corr then
            self.ActiveWord = nil
            self.ActiveRange = nil
            self:HideSuggestions()
            return
        end
        self._revertCorrection = corr
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
            suggestions = self:_WithRevertEntry(self:GetSuggestions(self.ActiveWord))
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

--- Prepend a "Restore '<original>'" row when the active word sits inside a
--- live autocorrection.  Always copies — GetSuggestions may return a cached
--- table shared across callers.
function Spellcheck:_WithRevertEntry(suggestions)
    if type(suggestions) ~= "table" then suggestions = {} end
    local corr = self._revertCorrection
    if not corr then return suggestions end
    local out = { { kind = "revert", value = corr.original } }
    for i = 1, #suggestions do out[#out + 1] = suggestions[i] end
    return out
end

function Spellcheck:GetWordAtCursor(text, cursor)
    local caret = cursor + 1
    local ignoreRanges = self:GetIgnoredRanges(text)
    local minLen = self:GetMinWordLength()
    local engine = self:GetActiveEngine()

    local isSlashCommand = (text:match("^%s*/") ~= nil)
    local emotePickerVisible = false
    if isSlashCommand and YapperTable.Emotes then
        emotePickerVisible = YapperTable.Emotes:IsActive() or
        (YapperTable.Emotes.HintFrame and YapperTable.Emotes.HintFrame:IsShown())
    end
    local skipFirstWord = isSlashCommand and emotePickerVisible
    local isFirstWord = true

    for s, e, word in IterWords(text) do
        local isCurrentFirstWord = isFirstWord
        isFirstWord = false

        if isCurrentFirstWord and skipFirstWord then
            -- Slash command + emote picker: don't spellcheck the command word.
        elseif caret >= s and caret <= (e + 1)
            and not self:IsRangeIgnored(s, e, ignoreRanges)
            and self:ShouldCheckWord(word, minLen, engine) then
            return { word = word, startPos = s, endPos = e }
        end
    end
    return nil
end

-- ===== Suggestion helpers ===================

--- Collect prefix-indexed candidates from a dictionary (and its base if delta).
--- Interleaves base and delta so a large delta shard cannot starve base words.
local function GatherPrefixCandidates(dict, base, firstChar)
    local out     = {}
    local dictSrc = dict.index and dict.index[firstChar]
    local baseSrc = base and base.index and base.index[firstChar]
    local di, bi  = 1, 1
    local cap     = 5000

    -- Round-robin interleave: 1 delta, 1 base per pass until both exhausted or cap hit.
    while #out < cap do
        local added = false
        if dictSrc and di <= #dictSrc then
            out[#out + 1] = dictSrc[di]; di = di + 1; added = true
        end
        if baseSrc and bi <= #baseSrc and #out < cap then
            out[#out + 1] = baseSrc[bi]; bi = bi + 1; added = true
        end
        if not added then break end
    end
    return out
end

--- Collect normalised user-added words for the current locale.
local function GatherUserCandidates(self, locale)
    local out = {}
    local normFn = self:_NormForLocale(locale)
    local userDict = self:GetUserDict(locale)
    if userDict and type(userDict.AddedWords) == "table" then
        for _, uw in ipairs(userDict.AddedWords) do
            if type(uw) == "string" and uw ~= "" then
                local norm = normFn(uw)
                if norm ~= "" then out[#out + 1] = norm end
            end
        end
    end
    return out
end

--- Collect n-gram-scored candidates when the n-gram index is enabled.
local function GatherNgramCandidates(dict, base, lower, lowerLen, engine)
    local deltaHits = {}
    local baseHits = {}
    local ngramN = Spellcheck:GetNgramN()
    local n = lowerLen < 5 and ngramN or (ngramN + 1)
    local norm = engine.NormaliseVowels(lower)

    local function addHits(idx, hits)
        if not idx then return end
        for i = 1, (#norm - n + 1) do
            local g = string_sub(norm, i, i + n - 1)
            local posting = rawget(idx, g)
            if posting then
                for _, id in ipairs(posting) do
                    hits[id] = (hits[id] or 0) + 1
                end
            end
        end
    end

    local indexKey = "ngramIndex" .. n
    addHits(rawget(dict, indexKey), deltaHits)
    if base then
        addHits(rawget(base, indexKey), baseHits)
    end

    local tmp = {}
    local function appendCandidates(hits, source)
        if not source or not source.words then return end
        for id, cnt in pairs(hits) do
            local w = source.words[id]
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
    end

    appendCandidates(deltaHits, dict)
    appendCandidates(baseHits, base)

    table_sort(tmp, function(a, b)
        if a.score == b.score then return a.word < b.word end
        return a.score > b.score
    end)

    local out = {}
    for i = 1, math_min(#tmp, Spellcheck:GetNgramTopCandidates()) do
        out[#out + 1] = tmp[i].word
    end
    return out
end

--- Collect phonetically similar candidates via the phonetic index.
--- The engine call is guarded: a faulting engine is purged, not propagated.
local function GatherPhoneticCandidates(dict, lower, engine)
    local out = {}
    local phoneticHash = Spellcheck:_SafeEngineCall(engine, "GetPhoneticHash", false, lower)
    if type(phoneticHash) ~= "string" or phoneticHash == "" then return out, "" end
    -- Walk the extends chain with rawget: each level's phonetic postings are
    -- 1-based indices into THAT level's words array, and a delta entry must
    -- not shadow base postings for the same hash.
    local d, guard = dict, 0
    while d and guard < 8 do
        guard = guard + 1
        local matches = d.phonetics and rawget(d.phonetics, phoneticHash)
        if matches then
            for _, id in ipairs(matches) do
                if #out >= 2000 then break end
                local w = d.words and rawget(d.words, id)
                if w then out[#out + 1] = w end
            end
        end
        d = d.extends and Spellcheck.Dictionaries[d.extends]
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

local NIL_USER_REV_KEY = "__nil_user_rev__"

local function CtxGetMeta(ctx, candidate)
    return ctx.self:GetMeta(ctx.dict, candidate)
end

local function CtxEditDistance(ctx, a, b, max)
    return ctx.self:EditDistance(a, b, max)
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

    -- Keyboard layouts come from the engine; no engine layouts means no
    -- proximity scoring at all.
    local kbLayouts = engine and engine.KBLayouts
    local kbDist    = kbLayouts
        and Spellcheck:_GetKBDistFromLayouts(kbLayouts, self:GetKeyboardLayout())
        or nil

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

    local normVowelsFn = engine and engine.NormaliseVowels
    local lowerVowels  = normVowelsFn and normVowelsFn(lower) or lower

    return {
        dict            = dict,
        lower           = lower,
        lowerLen        = lowerLen,
        maxWrong        = maxWrong,
        lHasApostrophe  = lHasApostrophe,
        lFlat           = lFlat,
        isVariantLocale = isVariantLocale,
        variantRules    = variantRules,
        kbDist          = kbDist,
        engine          = engine,
        weights         = weights,
        lowerBytes      = lowerBytes,
        inputBag        = inputBag,
        inputBigrams    = inputBigrams,
        phoneticHash    = phoneticHash,
        normVowelsFn    = normVowelsFn,
        lowerVowels     = lowerVowels,
        locale          = locale,
        YAS           = self.YAS,
        self            = self,
    }
end

local function CommonPrefixLen(a, b)
    local len = math_min(#a, #b)
    for i = 1, len do
        if string_byte(a, i) ~= string_byte(b, i) then return i - 1 end
    end
    return len
end

local function LetterBagScore(ctx, candidate)
    local meta = CtxGetMeta(ctx, candidate)
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
    local meta = CtxGetMeta(ctx, candidate)
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
    -- Phonetic membership is a property of the word, not the generator that
    -- found it: a reshuffle variant that shares the input's hash still earns
    -- the phonetic bonus even though the phonetic pool was skipped.
    isPhonetic = isPhonetic or (ctx.phoneticSet ~= nil and ctx.phoneticSet[candidate] == true)
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

    -- Vowel-neutral match bonus
    if ctx.normVowelsFn and ctx.normVowelsFn(candidate) == ctx.lowerVowels then
        score = score - W.vowelBonus
    end

    -- Phonetic Complexity Bonus
    if isPhonetic and candidateLen > lowerLen then
        score = score - ((candidateLen - lowerLen) * 0.75)
    end

    -- Apostrophe handling: compare flat (apostrophe-stripped) forms too.
    local cHasApostrophe = candidate:find("'", 1, true)
    if cHasApostrophe or ctx.lHasApostrophe then
        local cFlat = cHasApostrophe and string_gsub(candidate, "'", "") or candidate
        if cFlat == ctx.lFlat then
            score = score - 1.5
        else
            local flatDist = CtxEditDistance(ctx, ctx.lFlat, cFlat, 3)
            if flatDist and flatDist < dist then
                score = score - ((dist - flatDist) * 0.8)
            end
        end
    end

    -- Locale variant bonus
    local variantBonus = LocaleVariantBonus(ctx, candidate)
    if variantBonus > 0 then score = score - variantBonus end

    -- Keyboard proximity bonus: only plausible for near-misses.
    if dist <= 2 and lenDiff <= 1 and ctx.kbDist then
        local kbDist    = ctx.kbDist
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
    if ctx.YAS and ctx.YAS.GetBonus then
        score = score + ctx.YAS:GetBonus(candidate, lower, ctx.phoneticHash, ctx.locale, ctx.prevWord)
    end

    out[#out + 1] = { word = candidate, dist = dist, score = score, baseScore = baseScore, bag = bagScore }
end

--- Inject direct locale variant swaps (colour<->color etc.) into the output.
local function InjectLocaleVariants(ctx, out, seenCandidates, engineHashes, engineHashFn)
    local lower = ctx.lower
    local dict = ctx.dict
    local maxDist = (ctx.lowerLen <= 4) and 2 or 3
    local function inject(variantSub, candSub)
        local varWord = string_gsub(lower, variantSub, candSub)
        if varWord ~= lower and dict.set[varWord] and not seenCandidates[varWord] then
            seenCandidates[varWord] = true

            -- Blocklist check (normalise via the engine's canonicaliser)
            local isBlocked = false
            if engineHashes and engineHashFn then
                local nw = (ctx.engine and ctx.engine.NormaliseWord or NormaliseWord)(varWord)
                if engineHashes[engineHashFn(nw)] or engineHashes[engineHashFn(Utils.Deleet(nw))] then
                    isBlocked = true
                end
            end

            if not isBlocked then
                local dist = CtxEditDistance(ctx, lower, varWord, maxDist)
                if dist and dist <= maxDist then
                    ScoreCandidate(ctx, out, varWord, dist, false)
                end
            end
        end
    end
    for i = 1, #ctx.variantRules do
        inject(ctx.variantRules[i][1], ctx.variantRules[i][2])
    end
end

--- Generate transposition / deletion / replacement reshuffles and try them.
local function TryReshuffles(self, ctx, out, seenCandidates, checks, dynamicCap, engineHashes, engineHashFn)
    local lower = ctx.lower
    local dict = ctx.dict
    local maxDist = (ctx.lowerLen <= 4) and 2 or 3
    local attempts = self:GetReshuffleAttempts() or 0
    if attempts <= 0 then return checks end
    -- Adjacent transpositions and single deletions are bounded by word
    -- length and are the classic mechanical slips; always cover them
    -- fully.  The configured budget applies to the substitution sweep
    -- on top of those.
    attempts = attempts + ((ctx.lowerLen - 1) + ctx.lowerLen)

    local variants = self._scratchVariants
    if not variants then
        variants = {}; self._scratchVariants = variants
    end
    for k in pairs(variants) do variants[k] = nil end

    local vseen = self._scratchVSeen
    if not vseen then
        vseen = {}; self._scratchVSeen = vseen
    end
    for k in pairs(vseen) do vseen[k] = nil end

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
    local alph = self._scratchAlph
    if not alph then
        alph = {}; self._scratchAlph = alph
    end
    for k in pairs(alph) do alph[k] = nil end

    for k in pairs(dict.index) do alph[#alph + 1] = k end
    for i = 1, #lower do alph[#alph + 1] = string_sub(lower, i, i) end

    local alphSeen = self._scratchAlphSeen
    if not alphSeen then
        alphSeen = {}; self._scratchAlphSeen = alphSeen
    end
    for k in pairs(alphSeen) do alphSeen[k] = nil end

    local alphaList = self._scratchAlphaList
    if not alphaList then
        alphaList = {}; self._scratchAlphaList = alphaList
    end
    for k in pairs(alphaList) do alphaList[k] = nil end

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
            local dist = CtxEditDistance(ctx, lower, var, maxDist)
            if dist and dist <= maxDist then
                local isBlocked = false
                if engineHashes and engineHashFn then
                    if engineHashes[engineHashFn(var)] or engineHashes[engineHashFn(Utils.Deleet(var))] then
                        isBlocked = true
                    end
                end
                if not isBlocked then
                    ScoreCandidate(ctx, out, var, dist, false)
                end
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
        if IsDebugEnabled() then
            self:Notify("Spellcheck:GetSuggestions no dictionary for locale")
        end
        return {}
    end

    -- No engine = no language judgement; return nothing rather than guess.
    local engine = self:GetActiveEngine()
    if not engine then
        if IsDebugEnabled() then
            self:Notify("Spellcheck:GetSuggestions no language engine for locale")
        end
        return {}
    end

    local locale = self:GetLocale()
    local userCache = self.UserDictCache[locale]
    local userRev = userCache and userCache._rev or nil
    local maxCount = self:GetMaxSuggestions()
    local lower = self:_SafeEngineCall(engine, "NormaliseWord", false, word)
    if type(lower) ~= "string" then lower = "" end
    local lowerLen = #lower
    if lowerLen == 0 then return {} end
    local first = lower:sub(1, 1)
    local maxCandidates = self:GetMaxCandidates() or 1000

    -- Context for the YAS bigram feature: the word immediately preceding
    -- the active range.  Extracted before the cache lookup because it is
    -- part of the cache key — the same typo under different preceding
    -- words must not share a cached result.
    local prevWord
    if self.ActiveRange and self.EditBox and YapperTable.Recolour then
        local canon = YapperTable.Recolour.CanonicalText(self.EditBox)
        if type(canon) == "string" then
            local pre = string_sub(canon, 1, self.ActiveRange.startPos - 1)
            for _, _, w in IterWords(pre) do prevWord = w end
        end
    end
    local prevNorm = prevWord and self:_SafeEngineCall(engine, "NormaliseWord", false, prevWord) or ""

    -- Suggestion cache: reuse result for the same normalised word+locale+userRev+maxCount+yasRev+prevWord.
    self._suggestionCache = self._suggestionCache or {}
    self._suggestionCacheCount = self._suggestionCacheCount or 0
    local sc = self._suggestionCache
    local userRevKey = (userRev == nil) and NIL_USER_REV_KEY or userRev
    -- Include YAS db revision so learning writes invalidate cached scores.
    local yasDb = self.YAS and self.YAS:GetLocaleDB(locale, true)
    local yasRev = (yasDb and yasDb._rev) or 0
    local cacheKey = lower ..
    "\0" .. locale .. "\0" .. tostring(userRevKey) .. "\0" .. tostring(maxCount) .. "\0" .. tostring(yasRev)
    .. "\0" .. prevNorm
    if sc[cacheKey] then
        return sc[cacheKey]
    end

    -- Base dict if this is a delta
    local base                             = dict.extends and self.Dictionaries[dict.extends]

    -- Gather candidate lists
    local prefixCandidates                 = GatherPrefixCandidates(dict, base, first)
    local addedCandidates                  = GatherUserCandidates(self, locale)

    local useNgram                         = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck
        and YapperTable.Config.Spellcheck.UseNgramIndex) or false
    local ngramCandidates                  = useNgram and GatherNgramCandidates(dict, base, lower, lowerLen, engine) or
        nil

    local phoneticCandidates, phoneticHash = GatherPhoneticCandidates(dict, lower, engine)

    -- YAS bias injection: learned corrections go straight into the pool so
    -- they aren't starved by shard caps.
    local learnedCandidates                = {}
    if self.YAS and self.YAS.GetBiasTargets then
        local targets = self.YAS:GetBiasTargets(lower, locale)
        if targets then
            for _, t in ipairs(targets) do
                table.insert(learnedCandidates, t)
            end
        end
    end

    if IsDebugEnabled() then
        self:Notify(string_format(
            "Spellcheck:GetSuggestions word='%s' lower='%s' prefCands=%d learnedCands=%d",
            tostring(word), tostring(lower), #prefixCandidates, #learnedCandidates))
    end

    -- Build scoring context
    local inputBag, inputBigrams = BuildInputMeta(self, lower)
    local ctx = MakeScoringContext(self, dict, lower, inputBag, inputBigrams, phoneticHash, locale, engine)
    ctx.prevWord = prevNorm ~= "" and prevNorm or nil
    if #phoneticCandidates > 0 then
        local set = {}
        for _, c in ipairs(phoneticCandidates) do set[c] = true end
        ctx.phoneticSet = set
    end

    local addedSet, ignoredSet, userBlockedSet = self:GetUserSets(self:GetLocale())
    local _, _, engineHashes, engineHashFn = self:GetBlockData(locale)
    local out = {}
    local maxDist = (lowerLen <= 4) and 2 or 3
    local maxLenDiff = maxDist + 1

    local dynamicCap = maxCandidates
    if lowerLen <= 4 then
        dynamicCap = math_min(maxCandidates * 4, 5000)
    end

    -- Candidate evaluation pipeline
    local checks = 0
    local seenCandidates = {}

    local function tryCandidates(list, isPhonetic)
        for _, candidate in ipairs(list) do
            if #out >= 100 then return true end
            if not seenCandidates[candidate] then
                seenCandidates[candidate] = true

                local isBlocked = false
                if addedSet and addedSet[candidate] then
                    -- explicit override
                elseif userBlockedSet and userBlockedSet[candidate] then
                    isBlocked = true
                elseif engineHashes and engineHashFn then
                    local nw = engine.NormaliseWord(candidate)
                    if engineHashes[engineHashFn(nw)] or engineHashes[engineHashFn(Utils.Deleet(nw))] then
                        isBlocked = true
                    end
                end

                if not isBlocked and not (ignoredSet and ignoredSet[candidate]) then
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

    -- 1. User-added words and YAS-learned bias targets (highest priority)
    if (addedCandidates and #addedCandidates > 0) or (#learnedCandidates > 0) then
        if addedCandidates then aborted = tryCandidates(addedCandidates) end
        if not aborted and #learnedCandidates > 0 then
            aborted = tryCandidates(learnedCandidates)
        end
    end

    -- 2. Reshuffles (mechanical slips: transposes, deletes, near-key
    --    replacements).  Highest-precision structural candidates, run
    --    before phonetics and the broad prefix sweep — on a large
    --    dictionary those pools can exhaust the shared check budget and
    --    reshuffles would never run.
    if not aborted and #out < maxCount and checks < dynamicCap then
        checks = TryReshuffles(self, ctx, out, seenCandidates, checks, dynamicCap, engineHashes, engineHashFn)
    end

    -- 3. Phonetic candidates (high priority)
    if not aborted and #phoneticCandidates > 0 then
        aborted = tryCandidates(phoneticCandidates, true)
    end

    -- 4. Direct locale variant injection (only when the active engine has variant rules)
    if ctx.isVariantLocale then
        InjectLocaleVariants(ctx, out, seenCandidates, engineHashes, engineHashFn)
    end

    -- 5. Bucket prefix candidates (2-char > 1-char > other)
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

    if IsDebugEnabled() then
        self:Notify(string_format(
            "Spellcheck:GetSuggestions buckets p2=%d p1=%d other=%d dynamicCap=%d maxDist=%d maxLenDiff=%d",
            #pref2, #pref1, #other, dynamicCap, maxDist, maxLenDiff))
    end

    -- 6. N-gram candidates
    if not aborted and ngramCandidates and #ngramCandidates > 0 then
        aborted = tryCandidates(ngramCandidates)
    end

    -- 7. Prefix buckets (ordered by relevance)
    if not aborted then aborted = tryCandidates(pref2) end
    if not aborted then aborted = tryCandidates(pref1) end
    if not aborted then tryCandidates(other) end

    if IsDebugEnabled() then
        self:Notify("Spellcheck:GetSuggestions finished checks=" ..
            tostring(checks) .. " candidatesFound=" .. tostring(#out))
    end

    -- Sort + output
    table_sort(out, function(a, b)
        if a.score == b.score then
            if a.dist == b.dist then return a.word < b.word end
            return a.dist < b.dist
        end
        return a.score < b.score
    end)

    -- Autocorrect scaffold (Phase 4): when shadow logging is enabled,
    -- classify the top-ranked candidate — tiers/vetoes/confidence are
    -- recorded for observation only; nothing is applied to the text.
    if self.YAS and self.YAS.ShadowClassify and out[1] then
        self.YAS:ShadowClassify(lower, out[1].word, locale,
            prevNorm ~= "" and prevNorm or nil)
    end

    local final = {}
    local poolSize = math_min(maxCount * 3, #out)
    for i = 1, poolSize do
        local o = out[i]
        final[i] = { kind = "word", value = o.word, score = o.score, baseScore = o.baseScore }
    end

    -- Add optional "add to dictionary" / "ignore" actions after the words.
    local addedSet2, ignoredSet2 = self:GetUserSets(self:GetLocale())
    if word and word ~= "" then
        local norm = engine.NormaliseWord(word)
        if not (addedSet2 and addedSet2[norm]) then
            final[#final + 1] = { kind = "add", value = word }
        end
        if not (ignoredSet2 and ignoredSet2[norm]) then
            final[#final + 1] = { kind = "ignore", value = word }
        end
    end

    -- Casing mirror.  An engine-provided MatchCase owns the judgement
    -- entirely (e.g. a language may capitalise nouns regardless of input);
    -- otherwise the core default capitalises suggestions when the input
    -- word started with an ASCII uppercase letter.
    local matchCase = engine.MatchCase
    local wb = string_byte(word, 1)
    if matchCase or (wb and wb >= 65 and wb <= 90) then
        for _, entry in ipairs(final) do
            if entry.kind == "word" then
                if matchCase then
                    local v = self:_SafeEngineCall(engine, "MatchCase", false, word, entry.value)
                    if type(v) == "string" then entry.value = v end
                else
                    entry.value = string_upper(string_sub(entry.value, 1, 1)) .. string_sub(entry.value, 2)
                end
            end
        end
    end

    -- Compound split detection: is the token two valid words run together
    -- (e.g. "I'msupposed" -> "I'm supposed")? YAS is bypassed for splits since
    -- both halves are already valid words, so there is nothing to learn.
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

    -- PRE_SPELLCHECK_SUGGESTIONS filter: plugins can mutate the suggestion list.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SPELLCHECK_SUGGESTIONS", {
            word = word,
            suggestions = final,
            locale = locale,
        })
        if payload == false then
            return {}
        end
        if type(payload) == "table" and type(payload.suggestions) == "table" then
            final = payload.suggestions
        end
    end

    local cacheCap = self:GetSuggestionCacheSize() or 5000
    if cacheCap > 0 then
        if self._suggestionCacheCount >= cacheCap then
            self:ClearSuggestionCache()
            sc = self._suggestionCache
        end
        if sc[cacheKey] == nil then
            self._suggestionCacheCount = (self._suggestionCacheCount or 0) + 1
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

    for j = 0, lenB do prev[j] = j end -- init prev row

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

        -- Rotate row buffers instead of reallocating.
        prevPrev, prev, cur = prev, cur, prevPrev
    end

    -- Persist the rotated buffers for the next call.
    self._ed_prev_prev = prevPrev
    self._ed_prev = prev
    self._ed_cur = cur

    return prev[lenB]
end

function Spellcheck:FormatSuggestionLabel(entry, index)
    local L = YapperTable.Strings
    if not L then
        -- Test harnesses / early-boot path without the Strings module.
        if type(entry) == "string" then return index .. ". " .. entry end
        if type(entry) ~= "table" then return index .. ". -" end
        local v = entry.value or entry.word or ""
        if entry.kind == "split"  then return index .. ". Split: " .. v end
        if entry.kind == "add"    then return index .. ". Add \"" .. v .. "\" to dictionary" end
        if entry.kind == "ignore" then return index .. ". Ignore \"" .. v .. "\"" end
        if entry.kind == "revert" then return index .. ". Restore \"" .. v .. "\"" end
        return index .. ". " .. v
    end
    if type(entry) == "string" then
        return L:Get("ui.spellcheck.row", index, entry)
    end
    if type(entry) ~= "table" then
        return L:Get("ui.spellcheck.row.empty", index)
    end
    if entry.kind == "split" then
        return L:Get("ui.spellcheck.split", index, entry.value or "")
    end
    if entry.kind == "add" then
        return L:Get("ui.spellcheck.add", index, entry.value or "")
    end
    if entry.kind == "ignore" then
        return L:Get("ui.spellcheck.ignore", index, entry.value or "")
    end
    if entry.kind == "revert" then
        return L:Get("ui.spellcheck.revert", index, entry.value or "")
    end
    return L:Get("ui.spellcheck.row", index, entry.value or entry.word or "")
end

return Spellcheck
