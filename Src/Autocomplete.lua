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
local string_len   = string.len
local string_byte  = string.byte
local math_floor   = math.floor
local math_max     = math.max
local table_sort   = table.sort

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

Autocomplete.GhostFS       = nil     -- FontString for the ghost-text preview
Autocomplete.CurrentSugg   = nil     -- currently displayed suggestion (full word)
Autocomplete.CurrentPrefix = nil     -- the partial word that produced it
Autocomplete.Active        = false   -- true while a suggestion is visible
Autocomplete.Enabled       = true    -- master toggle

-- Minimum characters before offering a suggestion.
local MIN_PREFIX_LEN = 2

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
-- Tier 1: YALLM personal lexicon lookup
-- ---------------------------------------------------------------------------

--- Scan YALLM's frequency table for the best match starting with `prefix`.
--- Returns the highest-frequency word, or nil.
---@param prefix string  Lowercased prefix to match.
---@return string?       Best matching word, in its original casing.
function Autocomplete:SearchYALLM(prefix)
	local yallm = YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
	if not yallm or not yallm.db or not yallm.db.freq then return nil end

	local lowerPrefix = string_lower(prefix)
	local prefixLen   = string_len(lowerPrefix)
	local bestWord    = nil
	local bestCount   = 0

	for word, entry in pairs(yallm.db.freq) do
		local count = type(entry) == "table" and entry.c or entry
		if type(count) ~= "number" then count = 0 end

		if string_len(word) > prefixLen
			and string_lower(string_sub(word, 1, prefixLen)) == lowerPrefix
			and count > bestCount then
			bestWord  = word
			bestCount = count
		end
	end

	return bestWord
end

-- ---------------------------------------------------------------------------
-- Tier 2: Dictionary binary search
-- ---------------------------------------------------------------------------

--- Binary search over a sorted word array for the first entry starting
--- with `prefix`.  Returns the shortest matching word.
---@param words  table   Sorted array of strings (dict.words).
---@param prefix string  Lowercased prefix to match.
---@return string?       Shortest dictionary word starting with prefix.
function Autocomplete:SearchDictionary(words, prefix)
	if not words or #words == 0 then return nil end

	local lowerPrefix = string_lower(prefix)
	local prefixLen   = string_len(lowerPrefix)

	-- Binary search: find the first index where words[i] >= prefix.
	local lo, hi = 1, #words
	while lo < hi do
		local mid = math_floor((lo + hi) / 2)
		if string_lower(words[mid]) < lowerPrefix then
			lo = mid + 1
		else
			hi = mid
		end
	end

	-- Scan forward from `lo` to find the shortest word that starts with prefix.
	local best = nil
	for i = lo, #words do
		local w = words[i]
		local lw = string_lower(w)
		if string_sub(lw, 1, prefixLen) ~= lowerPrefix then
			break -- past the prefix range
		end
		-- Skip exact-length matches (the word IS the prefix — nothing to complete).
		if string_len(w) > prefixLen then
			if not best or string_len(w) < string_len(best) then
				best = w
			end
		end
	end

	return best
end

-- ---------------------------------------------------------------------------
-- Cascade lookup
-- ---------------------------------------------------------------------------

--- Run the full tiered lookup: YALLM first, then dictionary.
---@param prefix string  The partial word the user is typing.
---@return string?       The best completion, or nil.
function Autocomplete:GetSuggestion(prefix)
	if not prefix or string_len(prefix) < MIN_PREFIX_LEN then return nil end

	-- Tier 1: personal lexicon.
	local yallmHit = self:SearchYALLM(prefix)
	if yallmHit then return yallmHit end

	-- Tier 2: dictionary base.
	local sc = YapperTable.Spellcheck
	if not sc or not sc.GetDictionary then return nil end
	local dict = sc:GetDictionary()
	if not dict then return nil end

	-- Search the main word list.
	local dictHit = self:SearchDictionary(dict.words, prefix)
	if dictHit then return dictHit end

	-- Try the base (parent) dictionary if the current locale extends one.
	-- (e.g. enGB extends enBase).
	if dict._base and type(dict._base.words) == "table" then
		dictHit = self:SearchDictionary(dict._base.words, prefix)
	end

	return dictHit
end

-- ---------------------------------------------------------------------------
-- Ghost text rendering
-- ---------------------------------------------------------------------------

--- Create (or return) the ghost-text FontString.
--- Parented to the overlay EditBox so it moves and scales with it.
---@return FontString?
function Autocomplete:GetGhostFS()
	if self.GhostFS then return self.GhostFS end

	local editBox = YapperTable.EditBox and YapperTable.EditBox.OverlayEdit
	if not editBox then return nil end

	local fs = editBox:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(editBox:GetFontObject())
	fs:SetTextColor(0.55, 0.55, 0.55, 0.7) -- muted ghost colour
	fs:Hide()

	self.GhostFS = fs
	return fs
end

--- Position the ghost-text FontString so it appears immediately after
--- the user's current text at the cursor position.
function Autocomplete:PositionGhost()
	local fs = self.GhostFS
	if not fs then return end

	local editBox = YapperTable.EditBox and YapperTable.EditBox.OverlayEdit
	if not editBox then return end

	-- TODO: measure the pixel width of text up to the cursor position,
	-- then anchor the ghost FS at that offset from the EditBox's LEFT edge.
	-- For now, anchor after the full text.
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", editBox, "LEFT", editBox:GetTextWidth() or 0, 0)
end

--- Show the ghost-text suffix (the part of the suggestion beyond the prefix).
---@param suggestion string  Full suggested word.
---@param prefix     string  The typed prefix.
function Autocomplete:ShowGhost(suggestion, prefix)
	local fs = self:GetGhostFS()
	if not fs then return end

	local suffix = string_sub(suggestion, string_len(prefix) + 1)
	if suffix == "" then
		self:HideGhost()
		return
	end

	fs:SetText(suffix)
	self:PositionGhost()
	fs:Show()

	self.CurrentSugg   = suggestion
	self.CurrentPrefix = prefix
	self.Active        = true
end

--- Hide the ghost-text and clear state.
function Autocomplete:HideGhost()
	if self.GhostFS then
		self.GhostFS:Hide()
		self.GhostFS:SetText("")
	end
	self.CurrentSugg   = nil
	self.CurrentPrefix = nil
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

	local suggestion = self:GetSuggestion(word)
	if suggestion then
		self:ShowGhost(suggestion, word)
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

	-- Replace the partial word with the full suggestion.
	local before  = string_sub(text, 1, wordStart - 1)
	local after   = string_sub(text, pos + 1)
	local newText = before .. self.CurrentSugg .. after
	editBox:SetText(newText)
	editBox:SetCursorPosition(wordStart - 1 + string_len(self.CurrentSugg))

	-- Record the acceptance in YALLM so the word's frequency rises.
	local yallm = YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
	if yallm and yallm.RecordUsage then
		yallm:RecordUsage(self.CurrentSugg)
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

	local editBox = YapperTable.EditBox and YapperTable.EditBox.OverlayEdit
	if not editBox then return end

	local fontObj = editBox:GetFontObject()
	if fontObj then
		fs:SetFontObject(fontObj)
	end
end
