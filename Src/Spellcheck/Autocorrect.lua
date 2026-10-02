--[[
    Spellcheck/Autocorrect.lua
    Editing-stage autocorrect.

    When the user completes a word with a boundary keystroke (space,
    closing punctuation, closing quote), the completed word is run through
    the normal suggestion pipeline and YAS's ClassifySuggestion.  Only the
    AUTO tier mutates text: intent vetoes (INTENTIONAL/WAIVER), engine
    AutocorrectVeto/MaxConfidence and the self-eval suspension all apply
    unchanged.

    Reversion paths (all share RevertCorrection / _FlagReverted):
      * Backspace that deletes the boundary byte right after a correction
        reverts it (stateless match against the stored post-apply text).
      * Ctrl+Z via History:Undo -> OnUndo text-diff detection.
      * Toast "Undo" button, validated against YAS's undo ring.
      * Caret re-entry into a corrected word re-opens the suggestion popup
        seeded with "Restore '<original>'" (kind = "revert").

    A reverted pair is suppressed for the rest of the session so the same
    correction never re-applies immediately when the user retypes it.
]]

local _, YapperTable = ...
local Spellcheck   = YapperTable.Spellcheck
local Autocorrect  = {}
Spellcheck.Autocorrect = Autocorrect

local string_sub   = string.sub
local string_byte  = string.byte
local table_insert = table.insert
local table_remove = table.remove
local type         = type
local ipairs       = ipairs
local tostring     = tostring
local math_min     = math.min
local math_max     = math.max

local CORRECTIONS_CAP = 20 -- session ring of live corrections

Autocorrect._corrections   = {}  -- newest-last ring of live corrections
Autocorrect._suppressed    = {}  -- "typo\0correction" pairs suppressed this session

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Normalised pair key for the session suppression set.
local function PairKey(typo, correction)
    local t = Spellcheck.NormaliseWord(typo or "")
    local c = Spellcheck.NormaliseWord(correction or "")
    return t .. "\0" .. c
end

function Autocorrect:IsEnabled()
    local cfg = Spellcheck.GetConfig and Spellcheck:GetConfig() or {}
    if cfg.AutocorrectEnabled ~= true then return false end
    if not Spellcheck:IsEnabled() then return false end
    local yas = Spellcheck.YAS
    return (yas and yas.IsEnabled and yas:IsEnabled()) == true
end

--- Find the newest live (un-reverted) correction record covering the word
--- range [s, e] in `editBox`, or nil.
function Autocorrect:LiveCorrectionAt(editBox, s, e)
    if type(s) ~= "number" or type(e) ~= "number" then return nil end
    for i = #self._corrections, 1, -1 do
        local c = self._corrections[i]
        if not c.reverted and c.box == editBox
            and s <= c.eApplied and e >= c.s then
            return c
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Keystroke entry points (called from Spellcheck:OnTextChanged)
-- ---------------------------------------------------------------------------

--- Every user text change runs through here BEFORE the boundary check.
--- Detects the "backspace right after a correction" revert.
---
--- Deliberately stateless: WoW does not guarantee whether OnCursorChanged
--- or OnTextChanged fires first for a deletion, so an armed flag cleared on
--- caret moves could die before we ever see the keystroke.  Instead we
--- recognise the gesture exactly — the newest live correction on this box
--- still matches its stored post-apply text minus the boundary byte, and
--- the caret sits where deleting that byte leaves it.  Any other edit makes
--- the text stop matching, so the gesture self-invalidates; caret moves
--- cannot false-trigger it.
function Autocorrect:OnUserTextChanged(editBox, text, cursor)
    if type(text) ~= "string" or type(cursor) ~= "number" then return false end
    local c = self._corrections[#self._corrections]
    if not c or c.reverted or c.box ~= editBox then return false end

    -- In c.after, the boundary byte sits at index eA + 1 and the caret was
    -- left right after it (position eA + 1).  Deleting it leaves the text
    -- c.after minus byte (eA + 1) and caret position eA.
    local eA = c.eApplied
    if cursor ~= eA then return false end
    if text ~= string_sub(c.after, 1, eA) .. string_sub(c.after, eA + 2) then
        return false
    end

    self:RevertCorrection(editBox, c, "backspace")
    return true
end

--- Word-boundary keystroke: evaluate the completed word and apply an
--- AUTO-tier correction.  `text`/`cursor` are canonical (caret = cursor+1,
--- so the typed boundary byte sits at index `cursor`).
function Autocorrect:OnBoundaryCommit(editBox, text, cursor)
    if not self:IsEnabled() then return end
    if type(text) ~= "string" or type(cursor) ~= "number" then return end
    if cursor < 2 then return end

    -- Slash-command text is never corrected.
    if text:match("^%s*/") then return end

    local cls = Spellcheck:ClassifyBoundary(text, cursor)
    if cls ~= "commit" and cls ~= "close" then return end

    -- Mid-word guard: a boundary inserted inside a word (e.g. "hel.lo")
    -- does not complete the fragment before it.  The byte after the
    -- boundary must be a non-word byte or end-of-text.
    local afterB = string_byte(text, cursor + 1)
    if afterB and Spellcheck.IsWordByte(afterB) then return end

    -- The completed word must end exactly before the boundary byte.
    local wordEnd = cursor - 1
    local eb = string_byte(text, wordEnd)
    if not eb or not Spellcheck.IsWordByte(eb) then return end

    local s, word, prevWord
    for s0, e0, w in Spellcheck.IterWords(text) do
        if s0 > wordEnd then break end
        if e0 == wordEnd then
            s, word = s0, w
        elseif e0 < wordEnd then
            prevWord = w
        end
    end
    if not word then return end

    local engine = Spellcheck:GetActiveEngine()
    if not Spellcheck:ShouldCheckWord(word, Spellcheck:GetMinWordLength(), engine) then
        return
    end
    if Spellcheck:IsRangeIgnored(s, wordEnd, Spellcheck:GetIgnoredRanges(text)) then
        return
    end
    if Spellcheck:IsWordCorrect(word) then return end
    -- Words the user explicitly ignored are intentional by definition.
    local _, ignoredSet = Spellcheck:GetUserSets(Spellcheck:GetLocale())
    if ignoredSet and ignoredSet[Spellcheck.NormaliseWord(word)] then return end

    -- Candidates are already MatchCase'd (so "Teh" -> "The", not "the").
    -- GetSuggestions derives the bigram prevWord context from ActiveRange, so lend it the
    -- completed word's range for the duration of the call — this keeps both
    -- the scoring signal and the suggestion-cache key identical to what the
    -- suggestion panel would produce for this word.
    local prevRange, prevBox = Spellcheck.ActiveRange, Spellcheck.EditBox
    Spellcheck.ActiveRange = { startPos = s, endPos = wordEnd }
    Spellcheck.EditBox = editBox
    local okCall, suggestions = pcall(Spellcheck.GetSuggestions, Spellcheck, word)
    Spellcheck.ActiveRange, Spellcheck.EditBox = prevRange, prevBox
    if not okCall then suggestions = nil end

    -- Evaluate the top few word candidates and apply the highest-confidence
    -- AUTO-tier pick; ties keep dictionary rank order.  The panel's #1 is
    -- not always the mechanically-obvious fix ("doign" ranks "deign" over
    -- "doing"), and a suppressed pair only skips that candidate, not the
    -- whole word.
    local yas = Spellcheck.YAS
    local locale = Spellcheck:GetLocale()
    local best, bestConf
    if type(suggestions) == "table" then
        local seen = 0
        for _, entry in ipairs(suggestions) do
            local kind = (type(entry) == "table") and (entry.kind or "word") or "word"
            if kind == "word" then
                seen = seen + 1
                if seen > 5 then break end
                local cand = (type(entry) == "table") and (entry.value or entry.word) or entry
                if type(cand) == "string" and cand ~= "" and cand ~= word
                    and not self._suppressed[PairKey(word, cand)] then
                    local d = yas:ClassifySuggestion(word, cand, locale, prevWord)
                    if d and d.vetoReasons
                        and (d.vetoReasons.intentional or d.vetoReasons.waiver) then
                        return -- token-level veto applies to every candidate
                    end
                    if d and d.tier == "AUTO"
                        and (not bestConf or (d.confidence or 0) > bestConf) then
                        best, bestConf = cand, d.confidence
                    end
                end
            end
        end
    end
    if not best then return end

    self:_Apply(editBox, s, wordEnd, word, best, text, cursor, locale)
end

-- ---------------------------------------------------------------------------
-- Apply / revert
-- ---------------------------------------------------------------------------

function Autocorrect:_Apply(editBox, s, e, original, replacement, text, cursor, locale)
    local before   = string_sub(text, 1, s - 1)
    local after    = string_sub(text, e + 1)
    local newText  = before .. replacement .. after
    local newCursor = cursor + (#replacement - (e - s + 1))

    -- Undo snapshot of the pre-correction state, then splice.
    if YapperTable.History and YapperTable.History.AddSnapshot then
        YapperTable.History:AddSnapshot(editBox, true)
    end
    editBox:SetText(newText)
    editBox:SetCursorPosition(newCursor)

    local corr = {
        box      = editBox,
        s        = s,
        eApplied = s + #replacement - 1,
        original = original,
        applied  = replacement,
        before   = text,
        after    = newText,
        reverted = false,
        time     = time(),
    }
    table_insert(self._corrections, corr)
    while #self._corrections > CORRECTIONS_CAP do
        table_remove(self._corrections, 1)
    end

    -- Undo-ring record for toast Undo validation.
    local yas = Spellcheck.YAS
    if yas and yas.PushUndo then
        corr.undoEntry = {
            s = s, e = corr.eApplied,
            original = original, applied = replacement,
            before = text, after = newText,
            box = editBox, corr = corr,
        }
        yas:PushUndo(corr.undoEntry)
    end

    -- Implicit accept: the correction stays unless the user reverts it.
    -- gain 0 — an auto-apply is not a user endorsement of promotion, so it
    -- must not feed eval.promotedAccepted.
    if yas and yas.RecordSelection then
        yas:RecordSelection(original, replacement, 0, locale)
    end

    if YapperTable.API then
        YapperTable.API:Fire("AUTOCORRECT_APPLIED", original, replacement)
    end

    local cfg = Spellcheck:GetConfig()
    if cfg.AutocorrectToast ~= false and YapperTable.Toast
        and YapperTable.Toast.ShowCorrection then
        YapperTable.Toast:ShowCorrection(corr)
    end
end

--- Revert a live correction: splice the original word back over the applied
--- range in the editBox's CURRENT text (preserving whatever boundary text
--- the user has added since), record the rejection, and suppress the pair
--- for the session.  Returns true when the text was actually reverted.
function Autocorrect:RevertCorrection(editBox, corr, source)
    if not corr or corr.reverted then return false end
    if not editBox or not editBox.SetText then return false end

    local text = YapperTable.Recolour.CanonicalText(editBox)
    local s = corr.s
    local appliedEnd = s + #corr.applied - 1
    -- The applied word must still be exactly where we left it; a drifted
    -- edit means this correction is no longer cleanly revertable.
    if string_sub(text, s, appliedEnd) ~= corr.applied then return false end

    if YapperTable.History and YapperTable.History.AddSnapshot then
        YapperTable.History:AddSnapshot(editBox, true)
    end
    local newText = string_sub(text, 1, s - 1) .. corr.original
        .. string_sub(text, appliedEnd + 1)
    editBox:SetText(newText)
    -- Caret: keep the user's position when it sat after the correction
    -- (shifted by the length delta); land right after the restored word
    -- when it was inside the corrected span.
    local cur = editBox:GetCursorPosition() or appliedEnd + 1
    local delta = #corr.original - #corr.applied
    local newCur
    if cur > appliedEnd then newCur = cur + delta
    elseif cur >= s then newCur = s + #corr.original
    else newCur = cur end
    editBox:SetCursorPosition(math_max(0, math_min(newCur, #newText)))

    self:_FlagReverted(corr)
    return true
end

--- Mark a correction reverted without touching the text (undo path already
--- restored it): suppression + YAS negative signal.
function Autocorrect:_FlagReverted(corr)
    corr.reverted = true
    self._suppressed[PairKey(corr.original, corr.applied)] = true
    local yas = Spellcheck.YAS
    if yas and yas.RecordAutoReject then
        yas:RecordAutoReject(corr.original, corr.applied, Spellcheck:GetLocale())
    end
end

--- Lift the session suppression for a pair.  Called when the user manually
--- makes the same correction after reverting it — the re-pick is a stronger
--- signal than the earlier restore.
function Autocorrect:ClearSuppression(typo, correction)
    if type(typo) ~= "string" or type(correction) ~= "string" then return end
    self._suppressed[PairKey(typo, correction)] = nil
end

-- ---------------------------------------------------------------------------
-- History undo hook (called by History:Undo after the restore)
-- ---------------------------------------------------------------------------

--- Detect whether an undo transition (prevText -> restoredText) reverted one
--- of our corrections.  Exact full-text match: an undo landing on the stored
--- pre-correction state from the stored post-correction state IS the revert.
function Autocorrect:OnUndo(editBox, prevText, restoredText)
    if type(prevText) ~= "string" or type(restoredText) ~= "string" then return end
    for i = #self._corrections, 1, -1 do
        local c = self._corrections[i]
        if not c.reverted and c.box == editBox
            and c.after == prevText and c.before == restoredText then
            self:_FlagReverted(c)
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Toast undo
-- ---------------------------------------------------------------------------

--- Revert the correction described by a toast's undo record, but only when
--- it is still the newest pending undo — a stale toast must never pop a
--- newer correction's history entry.
function Autocorrect:UndoByToast(entry)
    local yas = Spellcheck.YAS
    if not (yas and yas.PeekUndo and yas.PopUndo) then return false end
    if yas:PeekUndo() ~= entry then return false end
    yas:PopUndo()
    local corr = entry.corr
    if corr then
        return self:RevertCorrection(entry.box, corr, "toast")
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Session hygiene
-- ---------------------------------------------------------------------------

--- Overlay hide / editor switch: corrections stay tracked (the undo ring and
--- toasts may still reference them once the box returns).
function Autocorrect:OnOverlayHide()
end

return Autocorrect
