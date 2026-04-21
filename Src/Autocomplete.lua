--[[
	Autocomplete.lua
	Predictive word completion with ghost-text preview and Tab acceptance.

	Data cascade:
		Tier 1 — YALLM personal lexicon  (freq table, ≤2000 entries)
		         Prioritises the user's own vocabulary: character names,
		         guild jargon, favourite descriptors.
		Tier 2 — Spellcheck dictionary    (sorted array, binary search)
		         Falls back to the full dictionary when YALLM has no match.

	Ghost text:
		A non-interactive FontString overlaid on the EditBox, rendered in a
		muted colour and positioned to continue from the cursor.  Updated on
		every keystroke via OnTextChanged.  Pressing Tab commits the
		suggestion; any other key dismisses or refines it.

	Performance:
		YALLM tier scans ≤2000 entries (linear, sub-ms).
		Dictionary tier uses binary search on the alphabetically sorted
		`dict.words` array — ~17 iterations for 130k words ($O(\log N)$).

	Not yet wired — this is scaffolding only.
]]

local _, YapperTable = ...

local Autocomplete = {}
YapperTable.Autocomplete = Autocomplete

-- Localise Lua globals for performance
local type         = type
local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local string_sub   = string.sub
local string_lower = string.lower
local string_upper = string.upper
local string_len   = string.len
local string_byte  = string.byte
local math_floor   = math.floor
local math_max     = math.max
local math_min     = math.min
local math_log     = math.log
local math_huge    = math.huge

--- Capitalise the first letter of `s`, leaving the rest unchanged.
local function CapFirst(s)
	if not s or s == "" then return s end
	return string_upper(string_sub(s, 1, 1)) .. string_sub(s, 2)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

Autocomplete.GhostFS       = nil     -- FontString for the ghost-text preview
Autocomplete.CurrentSugg   = nil     -- currently displayed suggestion (full word)
Autocomplete.CurrentPrefix = nil     -- the partial word that produced it
Autocomplete.PrefixText    = nil     -- full EditBox text up to (and including) the cursor
Autocomplete.Active        = false   -- true while a suggestion is visible
Autocomplete.Enabled       = true    -- master toggle
Autocomplete._activeEditBox = nil    -- the EditBox the ghost is bound to (nil = overlay)
Autocomplete._isMultiline   = false  -- true while bound to the multiline editor

-- Minimum characters before offering a suggestion.
local MIN_PREFIX_LEN = 2

-- Thresholds that control how many prefix-scan candidates are considered
-- and whether phonetic broadening is applied.
--   SHORT  (2-3 chars): scan up to SCAN_SHORT candidates; no phonetics.
--   MEDIUM (4-5 chars): scan up to SCAN_MEDIUM candidates; add phonetic matches.
--   LONG   (6+ chars):  scan up to SCAN_LONG  candidates; phonetic is tie-breaker only.
local SCAN_SHORT  = 12   -- wider net when prefix is short
local SCAN_MEDIUM = 8
local SCAN_LONG   = 4

-- Pixel gap between the caret and the first character of ghost text.
-- Prevents the caret from visually swallowing the first ghost letter.
local GHOST_CARET_PAD = 4

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

--- Check if autocomplete is enabled in user config.
--- Requires both the autocomplete toggle AND spellcheck to be on
--- (autocomplete depends on dictionary data from the spellcheck engine).
function Autocomplete:IsEnabled()
	if not self.Enabled then return false end
	local cfg = YapperTable.Config
	if cfg then
		-- Master toggle in EditBox settings.
		if cfg.EditBox and cfg.EditBox.AutocompleteEnabled == false then
			return false
		end
		-- Depends on spellcheck being active (dictionary data source).
		if cfg.Spellcheck and cfg.Spellcheck.Enabled ~= true then
			return false
		end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Word extraction
-- ---------------------------------------------------------------------------

--- Extract the word currently being typed (the token ending at the cursor).
---@param text string  Full EditBox text.
---@param pos  number  Cursor byte position (0-based, as returned by GetCursorPosition).
---@return string? word       The partial word, or nil if none.
---@return number? wordStart  1-based byte index where the word begins.
function Autocomplete:ExtractWordAtCursor(text, pos)
	if not text or pos < 1 then return nil, nil end

	-- Walk backwards from cursor to find the start of the current token.
	local startIdx = pos
	while startIdx > 0 do
		local b = string_byte(text, startIdx)
		-- Stop at whitespace or common punctuation.
		if b == 32 or b == 10 or b == 13 or b == 9 then -- space/newline/tab
			break
		end
		startIdx = startIdx - 1
	end
	startIdx = startIdx + 1

	if startIdx > pos then return nil, nil end
	local word = string_sub(text, startIdx, pos)
	if string_len(word) < MIN_PREFIX_LEN then return nil, nil end

	return word, startIdx
end

-- ---------------------------------------------------------------------------
-- Tier 2: Dictionary search with confidence-narrowing
-- ---------------------------------------------------------------------------

--- Binary search: return the first index in `words` whose lowercased value
--- is >= `lowerPrefix`.  Returns #words+1 if all entries are smaller.
---@param words       table   Sorted string array.
---@param lowerPrefix string  Already-lowercased prefix.
---@return number
local function BinarySearchFloor(words, lowerPrefix)
	local lo, hi = 1, #words
	while lo < hi do
		local mid = math_floor((lo + hi) / 2)
		if string_lower(words[mid]) < lowerPrefix then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

--- Collect up to `limit` words from `words` that start with `lowerPrefix`,
--- starting at index `startIdx`.  Skips exact-length matches (nothing to complete).
---@param words       table   Sorted string array.
---@param lowerPrefix string
---@param prefixLen   number
---@param startIdx    number
---@param limit       number
---@param out         table   Append results here as {word, isExact=bool}.
local function CollectPrefixMatches(words, lowerPrefix, prefixLen, startIdx, limit, out)
	local count = 0
	for i = startIdx, #words do
		if count >= limit then break end
		local w  = words[i]
		local lw = string_lower(w)
		if string_sub(lw, 1, prefixLen) ~= lowerPrefix then break end
		if string_len(w) > prefixLen then
			out[#out + 1] = w
			count = count + 1
		end
	end
end

--- Collect phonetic candidates from `dict` that share the same phonetic hash
--- as `prefix`, but also start with `lowerPrefix` (prefix constraint still
--- applies — phonetics is a broadening tiebreaker, not a free match).
---@param dict        table   Dictionary with .words and .phonetics.
---@param lowerPrefix string
---@param prefixLen   number
---@param limit       number
---@param out         table   Append results (word strings) here.
local function CollectPhoneticMatches(dict, lowerPrefix, prefixLen, limit, out)
	if not dict.phonetics then return end

	local sc = YapperTable.Spellcheck
	if not sc or not sc.GetPhoneticHash then return end
	local hash = sc.GetPhoneticHash(lowerPrefix)
	if not hash or hash == "" then return end

	local indices = dict.phonetics[hash]
	if not indices then return end

	local words = dict.words
	if not words then return end

	local count = 0
	for _, idx in ipairs(indices) do
		if count >= limit then break end
		local w = words[idx]
		if type(w) == "string" and string_len(w) > prefixLen then
			local lw = string_lower(w)
			if string_sub(lw, 1, prefixLen) == lowerPrefix then
				out[#out + 1] = w
				count = count + 1
			end
		end
	end
end

--- Score a candidate word given the typed prefix.
--- Higher is better.  Used to pick the single best match from the candidate pool.
---   +10  per character of prefix (longer prefix = more anchored)
---   +N   YALLM frequency bonus (log-scaled, personalised vocabulary)
---   -1   per extra character beyond the prefix (prefer shorter completions)
---   -N   negBias penalty when the user has repeatedly dismissed this word
---@param word        string
---@param lowerPrefix string
---@param prefixLen   number
---@param yallmFreq   table|nil  yallm.db.freq table, or nil.
---@param yallmNeg    table|nil  yallm.db.negBias table, or nil.
---@return number
local function ScoreCandidate(word, lowerPrefix, prefixLen, yallmFreq, yallmNeg)
	local score = prefixLen * 10

	-- Penalise length: shorter completions are preferred.
	score = score - (string_len(word) - prefixLen)

	local lword = string_lower(word)

	-- YALLM frequency bonus: words the user sends often rise to the top.
	if yallmFreq then
		local entry = yallmFreq[lword]
		local freq  = type(entry) == "table" and (entry.c or 0) or (type(entry) == "number" and entry or 0)
		if freq > 0 then
			-- log-scale so one very frequent word doesn't bury all others.
			score = score + math_max(1, math_floor(math_log(freq + 1) * 2))
		end
	end

	-- negBias penalty: words the user has dismissed for this prefix sink lower.
	-- Key format matches RecordRejection: Clean(prefix) .. ":" .. Clean(word).
	if yallmNeg then
		local key   = lowerPrefix:gsub("[%p%c%s]", "") .. ":" .. lword:gsub("[%p%c%s]", "")
		local entry = yallmNeg[key]
		if entry then
			local dismissals = type(entry) == "table" and (entry.c or 0) or 0
			-- Each dismissal costs 3 points, capped so the word can still surface
			-- when there's literally no other option.
			score = score - math_min(dismissals * 3, 12)
		end
	end

	return score
end

--- Search a single sorted word array with confidence-narrowing logic.
--- Returns the best candidate string, or nil.
---@param words       table   Sorted string array (dict.words or dict._base.words).
---@param phonetics   table|nil  Dict phonetics table for this word list.
---@param prefix      string  The user's typed partial word (original casing).
---@param yallmFreq   table|nil
---@param yallmNeg    table|nil  yallm.db.negBias table, or nil.
---@param broad       boolean|nil  When true, use widest scan + force phonetics (direction-change retry).
---@return string?
function Autocomplete:SearchDictionary(words, phonetics, prefix, yallmFreq, yallmNeg, broad)
	if not words or #words == 0 then return nil end

	local lowerPrefix = string_lower(prefix)
	local prefixLen   = string_len(lowerPrefix)

	-- Determine scan width and whether to broaden with phonetics.
	-- `broad` is set on a direction-change retry: use the widest net and
	-- always include phonetic candidates regardless of prefix length.
	local scanLimit
	local usePhonetics
	if broad then
		scanLimit    = SCAN_SHORT  -- widest net
		usePhonetics = (phonetics ~= nil)
	elseif prefixLen <= 3 then
		scanLimit    = SCAN_SHORT
		usePhonetics = false
	elseif prefixLen <= 5 then
		scanLimit    = SCAN_MEDIUM
		usePhonetics = (phonetics ~= nil)
	else
		scanLimit    = SCAN_LONG
		usePhonetics = (phonetics ~= nil)
	end

	-- Collect candidates from the sorted prefix range.
	local candidates = {}
	local startIdx   = BinarySearchFloor(words, lowerPrefix)
	CollectPrefixMatches(words, lowerPrefix, prefixLen, startIdx, scanLimit, candidates)

	-- For medium/long prefixes, broaden with phonetic neighbours.
	if usePhonetics then
		local mockDict = { words = words, phonetics = phonetics }
		CollectPhoneticMatches(mockDict, lowerPrefix, prefixLen, math_max(2, math_floor(scanLimit / 2)), candidates)
	end

	if #candidates == 0 then return nil end

	-- Score and pick the best.
	local bestWord  = nil
	local bestScore = -math_huge
	local seen = {}
	for _, w in ipairs(candidates) do
		local lw = string_lower(w)
		if not seen[lw] then
			seen[lw] = true
			local s = ScoreCandidate(w, lowerPrefix, prefixLen, yallmFreq, yallmNeg)
			if s > bestScore then
				bestScore = s
				bestWord  = w
			end
		end
	end

	return bestWord
end

-- ---------------------------------------------------------------------------
-- Cascade lookup
-- ---------------------------------------------------------------------------

--- Run the full tiered lookup: YALLM first, then dictionary with
--- confidence-narrowing based on prefix length.
---@param prefix string        The partial word the user is typing.
---@param broad  boolean|nil   When true, force widest scan + phonetics (direction-change retry).
---@return string?             The best completion, or nil.
function Autocomplete:GetSuggestion(prefix, broad)
	if not prefix or string_len(prefix) < MIN_PREFIX_LEN then return nil end

	-- Mirror the capitalisation of the first letter back onto the suggestion.
	-- Handles sentence-start capitals and user-capitalised proper nouns.
	local b1 = string_byte(prefix, 1)
	local prefixIsCapital = b1 and b1 >= 65 and b1 <= 90

	local lowerPrefix = string_lower(prefix)

	-- Fetch negBias once for use by ScoreCandidate across all tiers.
	local sc = YapperTable.Spellcheck
	local locale = sc and sc.GetLocale and sc:GetLocale() or "enBASE"
	local yallm = sc and sc.YALLM
	local yallmDB = yallm and yallm:GetLocaleDB(locale)
	local yallmNeg = yallmDB and yallmDB.negBias or nil

	-- Tier 1: personal lexicon (YALLM) — exact prefix scan.
	local yallmFreq = yallmDB and yallmDB.freq or nil
	local cleanPrefix = lowerPrefix:gsub("[%p%c%s]", "")


	if yallmFreq then
		local prefixLen      = string_len(lowerPrefix)
		local cleanPrefixLen = string_len(cleanPrefix)
		local bestWord   = nil
		local bestScore  = -math_huge
		for word, entry in pairs(yallmFreq) do
			local wordLen = string_len(word)
			-- Match on the stored (cleaned) key against both prefix forms.
			local matches = (wordLen > prefixLen
					and string_lower(string_sub(word, 1, prefixLen)) == lowerPrefix)
				or (cleanPrefixLen >= MIN_PREFIX_LEN and wordLen > cleanPrefixLen
					and string_lower(string_sub(word, 1, cleanPrefixLen)) == cleanPrefix)
			if matches then
				local freq = type(entry) == "table" and (entry.c or 0) or (type(entry) == "number" and entry or 0)
				if freq > bestScore then
					bestScore = freq
					bestWord  = word
				end
			end
		end
		if bestWord then
			return prefixIsCapital and CapFirst(bestWord) or bestWord
		end
	end

	-- Tier 1b: user's custom dictionary (words added via "Add to dictionary").
	-- This is a small array so linear scan is fine.
	local sc = YapperTable.Spellcheck
	if sc and sc.GetUserDict and sc.GetLocale then
		local userDict = sc:GetUserDict(sc:GetLocale())
		local addedWords = userDict and userDict.AddedWords
		if addedWords then
			local prefixLen = string_len(lowerPrefix)
			for _, w in ipairs(addedWords) do
				if string_len(w) > prefixLen
					and string_lower(string_sub(w, 1, prefixLen)) == lowerPrefix then
					return prefixIsCapital and CapFirst(w) or w
				end
			end
		end
	end

	-- Tier 2: dictionary with confidence-narrowing.
	if not sc or not sc.GetDictionary then return nil end
	local dict = sc:GetDictionary()
	if not dict then return nil end

	local hit = self:SearchDictionary(dict.words, dict.phonetics, prefix, yallmFreq, yallmNeg, broad)
	if hit then
		return prefixIsCapital and CapFirst(hit) or hit
	end

	-- Fallback: base dictionary (e.g. enGB extends enBase).
	if dict.extends and sc.Dictionaries then
		local base = sc.Dictionaries[dict.extends]
		if base and type(base.words) == "table" then
			hit = self:SearchDictionary(base.words, base.phonetics, prefix, yallmFreq, yallmNeg, broad)
		end
	end

	if hit then
		return prefixIsCapital and CapFirst(hit) or hit
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Ghost text rendering
-- ---------------------------------------------------------------------------

--- Create (or return) the ghost-text FontString.
--- The FS is created once and re-parented between EditBoxes as needed.
--- Parented to the active EditBox so it moves and scales with it.
--- In multiline mode the FS lives on the multiline EditBox (inside the
--- ScrollFrame) so it scrolls with the text content.
---@return FontString?
function Autocomplete:GetGhostFS()
	local editBox = self._activeEditBox
		or (YapperTable.EditBox and YapperTable.EditBox.OverlayEdit)
	if not editBox then return nil end

	-- Create the FontString once; re-parent on subsequent calls.
	if not self.GhostFS then
		local fs = editBox:CreateFontString(nil, "OVERLAY")
		fs:SetFontObject(editBox:GetFontObject())
		fs:SetTextColor(0.55, 0.55, 0.55, 0.7) -- muted ghost colour
		fs:Hide()
		self.GhostFS = fs
		self._ghostParent = editBox
	end

	-- Re-parent if the active EditBox changed (bind/unbind transition).
	if self._ghostParent ~= editBox then
		self.GhostFS:SetParent(editBox)
		self.GhostFS:SetFontObject(editBox:GetFontObject())
		self._ghostParent = editBox
	end

	-- Install the OnCursorChanged hook on the active EditBox (once per EB).
	-- We track which EB we hooked to avoid double-hooking or clobbering.
	if self._hookedEditBox ~= editBox then
		self:_InstallCursorHook(editBox)
	end

	return self.GhostFS
end

--- Install the OnCursorChanged hook on an EditBox.
--- Saves the original script so it can be restored later.
---@param editBox table
function Autocomplete:_InstallCursorHook(editBox)
	-- Restore the previous EB's script if we hooked one before.
	if self._hookedEditBox and self._hookedOrigScript ~= nil then
		self._hookedEditBox:SetScript("OnCursorChanged", self._hookedOrigScript or nil)
	end

	local ac = self
	local existing = editBox:GetScript("OnCursorChanged")

	editBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
		ac._caretX = x
		ac._caretY = y
		ac._caretH = h
		if existing then existing(self, x, y, w, h) end
		if ac.Active and ac.GhostFS then
			ac:PositionGhost()
		end
	end)

	self._hookedEditBox   = editBox
	self._hookedOrigScript = existing  -- may be nil (no prior script)
end

--- Position the ghost-text FontString immediately after the caret.
--- Uses the x coordinate from OnCursorChanged, which is frame-relative
--- and already accounts for horizontal scroll — no measurement needed.
--- In multiline mode, y is also used (the caret can be on any line).
function Autocomplete:PositionGhost()
	local fs = self.GhostFS
	if not fs then return end

	local editBox = self._activeEditBox
		or (YapperTable.EditBox and YapperTable.EditBox.OverlayEdit)
	if not editBox then return end

	-- _caretX / _caretY are set by the OnCursorChanged hook in GetGhostFS.
	-- OnCursorChanged delivers coordinates in the EditBox's local frame units.
	-- At non-100% UI scale the effective scale of the EditBox differs from
	-- UIParent's, so those frame-local units must be converted before being
	-- passed to SetPoint (which also uses UIParent-relative logical pixels).
	local uiScale  = UIParent and UIParent:GetEffectiveScale() or 1
	local ebScale  = editBox:GetEffectiveScale()
	local toUI     = ebScale / uiScale   -- eb local → UIParent logical pixels
	local pad      = GHOST_CARET_PAD / toUI  -- keep pad visually consistent

	local offsetX = (self._caretX or 0) * toUI + pad

	fs:ClearAllPoints()
	if self._isMultiline then
		-- In multiline, y from OnCursorChanged is the vertical offset from the
		-- top of the EditBox to the cursor bottom; h is the cursor height.
		--local offsetY = (self._caretY or 0) + (self._caretH or 0) * 0.5
		local offsetY = ((self._caretY or 0) - (self._caretH or 0) * 0.3) * toUI
		fs:SetPoint("TOPLEFT", editBox, "TOPLEFT", offsetX, offsetY)
	else
		fs:SetPoint("LEFT", editBox, "LEFT", offsetX, 0)
	end
end

--- Show the ghost-text suffix (the part of the suggestion beyond the prefix).
---@param suggestion    string  Full suggested word.
---@param prefix        string  The typed partial word.
---@param textUpToCursor string  Full EditBox text up to and including the cursor.
function Autocomplete:ShowGhost(suggestion, prefix, textUpToCursor)
	local fs = self:GetGhostFS()
	if not fs then return end

	local suffix = string_sub(suggestion, string_len(prefix) + 1)
	if suffix == "" then
		self:HideGhost()
		return
	end

	self.CurrentSugg   = suggestion
	self.CurrentPrefix = prefix
	self.PrefixText    = textUpToCursor or prefix
	self.Active        = true

	fs:SetText(suffix)
	self:PositionGhost()
	fs:Show()
end

--- Hide the ghost-text and clear state.
function Autocomplete:HideGhost()
	if self.GhostFS then
		self.GhostFS:Hide()
		self.GhostFS:SetText("")
	end
	self.CurrentSugg   = nil
	self.CurrentPrefix = nil
	self.PrefixText    = nil
	self.Active        = false
end

-- ---------------------------------------------------------------------------
-- Event hooks (to be wired by EditBox)
-- ---------------------------------------------------------------------------

--- Called on every keystroke (OnTextChanged).
--- Computes and displays the ghost-text suggestion.
---@param editBox table  The overlay EditBox widget.
function Autocomplete:OnTextChanged(editBox)
	if not self:IsEnabled() then
		self:HideGhost()
		return
	end

	local text = editBox:GetText()
	local pos  = editBox:GetCursorPosition()

	local word, _ = self:ExtractWordAtCursor(text, pos)
	if not word then
		self:HideGhost()
		return
	end

	-- Detect a direction change: the user typed something that no longer
	-- matches the current suggestion.  When that happens, retry with a
	-- wider search before giving up.
	local isDirChange = self.Active and self.CurrentSugg and self.CurrentPrefix
		and string_sub(string_lower(self.CurrentSugg), 1, string_len(word)) ~= string_lower(word)

	-- Record the dismissal the moment the user types away from a suggestion.
	-- Only fires once per suggestion (isDirChange is only true on the first
	-- diverging keystroke). Only records if the dismissed suggestion was a
	-- valid word so we don't pollute negBias with partial-word noise.
	if isDirChange then
		local yallm = YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
		if yallm and yallm.RecordRejection then
			-- RecordRejection expects a typo and a list of candidate objects.
			-- Use the prefix as the "typo" and the suggestion as the only candidate.
			local sc = YapperTable.Spellcheck
			local locale = sc and sc.GetLocale and sc:GetLocale() or "enBASE"
			yallm:RecordRejection(self.CurrentPrefix, { self.CurrentSugg }, locale)
		end
	end

	-- Soft approval: the user typed out the full suggested word manually instead
	-- of pressing Tab.  Detected by the word growing exactly onto CurrentSugg
	-- (CurrentPrefix is shorter, so this fires only on the completing keystroke).
	-- We give the word a small frequency nudge so it surfaces earlier next time.
	if self.Active and self.CurrentSugg and self.CurrentPrefix
		and string_lower(word) == string_lower(self.CurrentSugg)
		and string_len(word) > string_len(self.CurrentPrefix)
	then
		local yallm = YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
		if yallm then
			local sc = YapperTable.Spellcheck
			local locale = sc and sc.GetLocale and sc:GetLocale() or "enBASE"
			if yallm.RecordUsage then yallm:RecordUsage(self.CurrentSugg, locale) end
			-- Moderate bias: the user preferred this exact spelling.
			if yallm.RecordSelection then
				yallm:RecordSelection(self.CurrentPrefix, self.CurrentSugg, 0.15, locale)
			end
		end
	end

	local suggestion = self:GetSuggestion(word)
	if not suggestion and isDirChange then
		suggestion = self:GetSuggestion(word, true)  -- broad retry
	end

	if suggestion then
		self:ShowGhost(suggestion, word, string_sub(text, 1, pos))
	else
		self:HideGhost()
	end
end

--- Called when Tab is pressed.
--- If a suggestion is active, commit it and return true (consumed).
--- Otherwise return false so the caller can fall through to CycleChat.
---@param editBox table  The overlay EditBox widget.
---@return boolean       True if the Tab was consumed by autocomplete.
function Autocomplete:OnTabPressed(editBox)
	if not self.Active or not self.CurrentSugg or not self.CurrentPrefix then
		return false
	end

	local text = editBox:GetText()
	local pos  = editBox:GetCursorPosition()

	local word, wordStart = self:ExtractWordAtCursor(text, pos)
	if not word or word ~= self.CurrentPrefix then
		self:HideGhost()
		return false
	end

	-- Replace the partial word with the full suggestion.  Append a space
	-- so the user can continue typing without manually inserting one.
	local before  = string_sub(text, 1, wordStart - 1)
	local after   = string_sub(text, pos + 1)
	local trail   = (after:sub(1, 1) ~= " ") and " " or ""
	local newText = before .. self.CurrentSugg .. trail .. after
	editBox:SetText(newText)
	editBox:SetCursorPosition(wordStart - 1 + string_len(self.CurrentSugg) + string_len(trail))

	-- Record the acceptance in YALLM: strong bias signal (prefix→suggestion)
	-- in addition to frequency so the same completion surfaces faster.
	local sc = YapperTable.Spellcheck
	local yallm = sc and sc.YALLM
	if yallm then
		local locale = sc.GetLocale and sc:GetLocale() or "enBASE"
		if yallm.RecordUsage then yallm:RecordUsage(self.CurrentSugg, locale) end
		if yallm.RecordSelection then
			yallm:RecordSelection(self.CurrentPrefix, self.CurrentSugg, 0.5, locale)
		end
	end

	self:HideGhost()
	return true
end

--- Called when the overlay hides or loses focus.
function Autocomplete:OnOverlayHide()
	self:HideGhost()
end

-- ---------------------------------------------------------------------------
-- Font synchronisation
-- ---------------------------------------------------------------------------

--- Sync the ghost FS font with the EditBox (call after theme or font changes).
function Autocomplete:SyncFont()
	local fs = self.GhostFS
	if not fs then return end

	local editBox = self._activeEditBox
		or (YapperTable.EditBox and YapperTable.EditBox.OverlayEdit)
	if not editBox then return end

	local fontObj = editBox:GetFontObject()
	if fontObj then
		fs:SetFontObject(fontObj)
	end
end

-- ---------------------------------------------------------------------------
-- Multiline binding
-- ---------------------------------------------------------------------------

--- Sync the ghost FontString's font to match the active EditBox.
--- Call after changing the EditBox font (e.g. ApplyTheme / scaling).
function Autocomplete:SyncGhostFont()
	local fs = self.GhostFS
	if not fs then return end
	local editBox = self._activeEditBox
		or (YapperTable.EditBox and YapperTable.EditBox.OverlayEdit)
	if not editBox then return end
	local face, size, flags = editBox:GetFont()
	if face and size then
		fs:SetFont(face, size, flags or "")
	end
end

--- Switch the autocomplete ghost text to the multiline EditBox.
--- The FontString is re-parented (not destroyed) to avoid widget leaks.
--- Call from Multiline:Enter() after the multiline frame is shown.
---@param mlEditBox table  The multiline EditBox widget.
function Autocomplete:BindMultiline(mlEditBox)
	if not mlEditBox then return end

	self:HideGhost()

	self._activeEditBox = mlEditBox
	self._isMultiline   = true
	self._caretX        = nil
	self._caretY        = nil

	-- Re-parent and re-hook will happen lazily in GetGhostFS on next keystroke.
end

--- Return the autocomplete ghost text to the single-line overlay.
--- The FontString is re-parented (not destroyed) to avoid widget leaks.
--- Call from Multiline:Exit() before the overlay is re-shown.
function Autocomplete:UnbindMultiline()
	self:HideGhost()

	-- Restore the multiline EB's original OnCursorChanged script.
	if self._hookedEditBox and self._hookedEditBox == self._activeEditBox then
		self._hookedEditBox:SetScript("OnCursorChanged", self._hookedOrigScript or nil)
		self._hookedEditBox    = nil
		self._hookedOrigScript = nil
	end

	self._activeEditBox = nil
	self._isMultiline   = false
	self._caretX        = nil
	self._caretY        = nil

	-- Re-parent and re-hook will happen lazily in GetGhostFS on next keystroke.
end
