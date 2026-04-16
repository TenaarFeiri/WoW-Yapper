--[[
	Multiline.lua
	Expanded multi-line editor frame for storyteller-mode posts.

	When the user's text exceeds the single-line overlay or they trigger the
	toggle keybind, Yapper smoothly transitions from the slim chat-bar overlay
	into a larger, resizable editing surface.  The multi-line frame is a
	standalone ScrollingEditBox that lives above (or replaces) the single-line
	overlay and feeds its final text back through Chat:OnSend on submit.

	Lifecycle:
		EditBox overlay visible  ──► user triggers expand (keybind / auto)
		  └─► Multiline:Enter(text, chatType, target)
		        ├ captures current text + channel context
		        ├ hides single-line overlay
		        └ shows expanded frame, sets focus

		User presses Enter / submit  ──► Multiline:Submit()
		  └─► passes text to Chat:OnSend
		  └─► Multiline:Exit()

		User presses Escape / cancel ──► Multiline:Exit()
		  └─► optionally restores text to the single-line overlay
		  └─► re-shows single-line overlay

	Not yet wired — this is scaffolding only.
]]

local _, YapperTable = ...

local Multiline = {}
YapperTable.Multiline = Multiline

-- Localise Lua globals for performance
local type       = type
local tostring   = tostring
local math_max    = math.max
local math_min    = math.min
local math_abs    = math.abs
local table_insert = table.insert

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

Multiline.Frame       = nil   -- main container frame
Multiline.ScrollFrame = nil   -- scroll wrapper (ScrollFrame)
Multiline.EditBox     = nil   -- the actual multi-line EditBox widget
Multiline.LabelFS     = nil   -- channel label FontString
Multiline.Active      = false -- true while the expanded editor is shown
Multiline.ChatType    = nil   -- current channel type (SAY, YELL, …)
Multiline.Language    = nil   -- language index
Multiline.Target      = nil   -- whisper / channel target

-- ---------------------------------------------------------------------------
-- Label helpers
-- ---------------------------------------------------------------------------

--- Refresh the multiline frame's channel label and edit-text colour.
--- Mirrors the label-building logic from EditBox.RefreshLabel but is
--- intentionally simpler: channel colour master/override chains and theme
--- integration are omitted to keep this maintainable independently.
--- For EMOTE the player's character name is shown as the uneditable label.
local function RefreshMLLabel(ml)
	local BuildLabelText = YapperTable.EditBox and YapperTable.EditBox._BuildLabelText
	local chatType    = ml.ChatType or "SAY"
	local target      = ml.Target
	local eb          = YapperTable.EditBox
	local channelName = eb and eb.ChannelName

	local label, r, g, b
	if BuildLabelText then
		label, r, g, b = BuildLabelText(chatType, target, channelName)
	else
		label = "[" .. chatType .. "]"
		r, g, b = 1, 0.82, 0
	end

	-- Apply any per-channel colour overrides from config.
	local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
	local channelColors = cfg.ChannelTextColors
	if channelColors and type(channelColors[chatType]) == "table" then
		local c = channelColors[chatType]
		if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
			r, g, b = c.r, c.g, c.b
		end
	end

	if ml.LabelFS then
		ml.LabelFS:SetText(label)
		ml.LabelFS:SetTextColor(r, g, b)
	end
	-- Tint input text to match the channel colour.
	if ml.EditBox then
		ml.EditBox:SetTextColor(r, g, b)
	end
end

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

--- Return the storyteller / multiline configuration subtable.
local function GetConfig()
	local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
	return {
		autoExpand     = cfg.StorytellerAutoExpand ~= false,
		showHint       = cfg.StorytellerShowHint == true,
		slideSpeed     = (YapperTable.Config and YapperTable.Config.System
		                  and YapperTable.Config.System.StorytellerSlideSpeed) or 0.25,
		defaultWidth   = cfg.StorytellerWidth  or 400,
		defaultHeight  = cfg.StorytellerHeight or 250,
	}
end

-- ---------------------------------------------------------------------------
-- Frame creation (lazy)
-- ---------------------------------------------------------------------------

--- Build the multi-line editor frame.  Called once on first Enter().
function Multiline:CreateFrame()
	if self.Frame then return end

	local cfg = GetConfig()

	-- Container
	local f = CreateFrame("Frame", "YapperMultilineFrame", UIParent, "BackdropTemplate")
	f:SetSize(cfg.defaultWidth, cfg.defaultHeight)
	f:SetFrameStrata("HIGH")  -- above DIALOG overlay and chat messages
	f:SetClampedToScreen(true)
	f:Hide()
	self.Frame = f

	-- Backdrop: background fill and border.  Colors are overridden immediately
	-- by ApplyTheme() which reads live config; these are safe defaults only.
	f:SetBackdrop({
		bgFile   = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 10,
		insets   = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Channel label
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
	label:SetText("")
	self.LabelFS = label

	-- Scroll wrapper
	local sf = CreateFrame("ScrollFrame", "YapperMultilineScroll", f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
	sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 8)
	self.ScrollFrame = sf

	-- Editable region
	local edit = CreateFrame("EditBox", "YapperMultilineEdit", sf)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	-- Width is set to a safe fixed default here; it's updated in Enter() once
	-- the scroll frame has been laid out and GetWidth() returns a real value.
	local innerW = cfg.defaultWidth - 40  -- 8 outer pad + 28 scroll bar + 4 spare
	edit:SetWidth(innerW)
	-- Explicit height required: without it the EditBox has zero height and
	-- text renders invisibly (clipped to 0px).  OnTextChanged grows it.
	edit:SetHeight(cfg.defaultHeight)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetScript("OnEscapePressed", function()
		-- If a spellcheck suggestion panel is open, ESC closes only the
		-- panel rather than exiting the multiline editor entirely.
		if YapperTable.Spellcheck
				and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function"
				and YapperTable.Spellcheck:IsSuggestionOpen() then
			if type(YapperTable.Spellcheck.HideSuggestions) == "function" then
				YapperTable.Spellcheck:HideSuggestions()
			end
			return
		end
		Multiline:Cancel()
	end)
	sf:SetScrollChild(edit)
	self.EditBox = edit

	-- Enter sends; Shift+Enter inserts a literal newline (multi-line default).
	edit:SetScript("OnEnterPressed", function(box)
		-- If a suggestion was just applied (HandleKeyDown fired ENTER, called
		-- ApplySuggestion, and HideSuggestions ran before we get here), the
		-- transient _justAppliedSuggestion flag tells us not to send.
		if YapperTable.Spellcheck and YapperTable.Spellcheck._justAppliedSuggestion then
			return
		end
		-- If a suggestion panel is still visible, Enter applies the selected
		-- entry instead of submitting the message.
		if YapperTable.Spellcheck and type(YapperTable.Spellcheck.IsSuggestionOpen) == "function" then
			local sc = YapperTable.Spellcheck
			if sc:IsSuggestionOpen() then
				if type(sc.ApplySuggestion) == "function" then
					sc:ApplySuggestion(sc.ActiveIndex or 1)
				end
				return
			end
		end
		if IsShiftKeyDown() then
			box:Insert("\n")
			return
		end
		Multiline:Submit()
	end)

	-- Route spellcheck key actions (Shift+Tab for suggestions, number keys,
	-- arrow navigation) through the spellcheck handler.
	edit:HookScript("OnKeyDown", function(box, key)
		if YapperTable.Spellcheck and type(YapperTable.Spellcheck.HandleKeyDown) == "function" then
			YapperTable.Spellcheck:HandleKeyDown(key)
		end
	end)

	-- Mirror the overlay's OnChar suppression: after a suggestion hotkey
	-- (1–6) is pressed, the digit must be stripped before it reaches the
	-- EditBox text.  HandleKeyDown sets _suppressNextChar/_suppressChar;
	-- this hook clears them and restores the post-correction text.
	edit:HookScript("OnChar", function(box, char)
		if YapperTable.Spellcheck and YapperTable.Spellcheck._suppressNextChar then
			local sc = YapperTable.Spellcheck
			if sc._suppressChar == char then
				local expected = sc._expectedText or (box:GetText() or "")
				local cursor   = sc._expectedCursor
				box:SetText(expected)
				if cursor then box:SetCursorPosition(cursor) end
				sc._suppressNextChar = nil
				sc._suppressChar     = nil
				sc._expectedText     = nil
				sc._expectedCursor   = nil
				return
			end
		end
	end)

	-- Keep the scroll-child width in sync with the scroll frame.
	-- Height is intentionally not auto-grown here: the EditBox lives inside
	-- a ScrollFrame so the scrollbar handles overflow.  Auto-growing via
	-- SetText/SetHeight would reset the cursor position on every keystroke.
	-- We intentionally do NOT call Spellcheck:OnTextChanged here either —
	-- spellcheck calls SetText() to apply corrections, which also resets
	-- the cursor and makes the caret disappear.
	edit:SetScript("OnTextChanged", function(box, isUserInput)
		if not isUserInput then return end

		-- Passive spellcheck: only reads the EditBox (never calls SetText),
		-- so this is safe without disturbing cursor or scroll state.
		if YapperTable.Spellcheck and type(YapperTable.Spellcheck.OnTextChanged) == "function" then
			YapperTable.Spellcheck:OnTextChanged(box, isUserInput)
		end

		local sfW = sf:GetWidth()
		if sfW and sfW > 10 and math_abs(box:GetWidth() - sfW) > 1 then
			box:SetWidth(sfW)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Quadrant-aware positioning
-- ---------------------------------------------------------------------------

--- Position the multiline frame using absolute UIParent-relative coordinates.
--- GetLeft() / GetTop() / GetBottom() always return values in UIParent's
--- coordinate space regardless of intermediate parent frames or scales,
--- so this is safe even when ChatFrame1 has a non-1 effective scale.
---@param frame    Frame  The multiline container.
---@param overlay  Frame  The single-line overlay (for horizontal reference).
local function AnchorAbsolute(frame, overlay)
	local screenH = UIParent:GetHeight() or 768
	local screenW = UIParent:GetWidth()  or 1024

	-- Horizontal: align left edge with the overlay's left edge.
	local leftX = overlay:GetLeft() or 10
	local mlW   = frame:GetWidth()
	if leftX + mlW > screenW - 4 then leftX = screenW - mlW - 4 end
	if leftX < 4 then leftX = 4 end

	-- Vertical: use ChatFrame1 bounds when available; fall back to overlay.
	local chatTop, chatBot
	local cf = _G["ChatFrame1"]  -- well-known global, always present
	if cf and cf.GetTop then
		chatTop = cf:GetTop()
		chatBot = cf:GetBottom()
	end
	chatTop = chatTop or overlay:GetTop()    or 200
	chatBot = chatBot or overlay:GetBottom() or 60

	-- Quadrant: chat centre in bottom half → frame grows upward.
	local chatMidY = (chatTop + chatBot) / 2
	local popUp    = (chatMidY < screenH / 2)

	frame:ClearAllPoints()
	if popUp then
		-- Bottom of multiline sits just above the top of the chat message area.
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", leftX, chatTop + 2)
	else
		-- Top of multiline sits just below the bottom of the chat message area.
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, chatBot - 2)
	end
end

-- ---------------------------------------------------------------------------
-- Enter / Exit
-- ---------------------------------------------------------------------------

--- Transition from the single-line overlay into the expanded editor.
---@param text      string   Current text from the single-line overlay.
---@param chatType  string   Chat type (SAY, YELL, PARTY, …).
---@param language  number?  Language index.
---@param target    string?  Whisper / channel target.
function Multiline:Enter(text, chatType, language, target)
	if self.Active then return end
	self:CreateFrame()
	self:ApplyTheme()   -- pick up current config every open (rounded corners, colours, shadow)

	-- Sync font from the overlay EditBox so the multiline editor respects
	-- the user's configured font size and any active theme font override.
	local syncEB = YapperTable.EditBox
	if syncEB and syncEB.OverlayEdit then
		local face, size, flags = syncEB.OverlayEdit:GetFont()
		if face and size then
			self.EditBox:SetFont(face, size, flags or "")
			if self.LabelFS then self.LabelFS:SetFont(face, size, flags or "") end
		end
	end

	self.ChatType = chatType or "SAY"
	self.Language = language
	self.Target   = target

	-- Populate the editor.  If a multiline draft was stashed when the user
	-- previously exited back to the overlay (Exit(true)), restore it in full
	-- so hard newlines are preserved — but ONLY when the overlay text still
	-- matches the collapsed fingerprint we stored.  If the user has cleared
	-- or edited the overlay in the meantime, treat that as an intentional
	-- discard and use whatever the overlay now contains.
	local incomingText = text or ""
	local editorText
	if self._mlDraft and self._mlDraft ~= ""
			and self._mlDraftCollapsed and incomingText == self._mlDraftCollapsed then
		editorText = self._mlDraft
	else
		editorText = incomingText
	end
	self._mlDraft          = nil
	self._mlDraftCollapsed = nil
	self.EditBox:SetText(editorText)
	self.EditBox:SetCursorPosition(#editorText)

	-- Refresh the channel label and edit-text colour.
	RefreshMLLabel(self)

	local eb = YapperTable.EditBox
	local overlay = eb and eb.Overlay

	-- Clear the overlay's text so it doesn't show as a draft on re-open.
	-- Also mark the close as clean and wipe any saved draft so History's
	-- OnHide handler doesn't MarkDirty(true) and surface a stale draft
	-- the next time the overlay is opened.
	if eb and eb.OverlayEdit then
		eb.OverlayEdit:SetText("")
	end
	if eb then
		eb._closedClean = true  -- prevents OnHide from saving a dirty draft
	end
	if YapperTable.History and eb and eb.OverlayEdit then
		YapperTable.History:ClearDraft(eb.OverlayEdit)
	end

	-- IMPORTANT: set Active = true BEFORE hiding the overlay.
	-- The EditBox:Show() hook fires when the overlay is hidden (the game
	-- tries to re-open it), and its guard checks ml.Active.  If we set
	-- Active after Hide, the guard fails and the overlay re-opens,
	-- stealing keyboard focus and making the caret invisible.
	self.Active = true

	-- Position the frame using absolute UIParent coordinates captured
	-- from the overlay and ChatFrame1 before the overlay is hidden.
	if overlay then
		AnchorAbsolute(self.Frame, overlay)
		-- Sync the inner EditBox width to the scroll frame's current width.
		local sfW = self.ScrollFrame and self.ScrollFrame:GetWidth()
		if sfW and sfW > 10 and self.EditBox then
			self.EditBox:SetWidth(sfW)
		end
		overlay:Hide()
	else
		self.Frame:ClearAllPoints()
		self.Frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
	end

	self.Frame:Show()
	self.EditBox:SetFocus()

	-- Bind spellcheck to the multiline EditBox so underlines draw inside
	-- the multiline frame instead of (the now-hidden) overlay.
	if YapperTable.Spellcheck and type(YapperTable.Spellcheck.BindMultiline) == "function" then
		YapperTable.Spellcheck:BindMultiline(self.EditBox, self.Frame, self.ScrollFrame)
	end
end

--- Close the expanded editor and return to the single-line overlay.
---@param restoreText boolean?  If true, push the current text back to the overlay.
function Multiline:Exit(restoreText)
	if not self.Active then return end

	-- Restore spellcheck to the single-line overlay before we re-show it.
	if YapperTable.Spellcheck and type(YapperTable.Spellcheck.UnbindMultiline) == "function" then
		YapperTable.Spellcheck:UnbindMultiline()
	end

	local text = self.EditBox and self.EditBox:GetText() or ""
	self.Active = false

	if self.Frame then
		self.Frame:Hide()
	end

	-- Restore text to the single-line overlay if requested.
	local eb = YapperTable.EditBox
	if eb then
		if restoreText and eb.OverlayEdit and text ~= "" then
			-- If the draft contains hard newlines, stash the original so it
			-- can be fully restored when the user re-opens multiline.  Push a
			-- collapsed (single-line) version to the overlay so it doesn't show
			-- raw control characters in the narrow input box.
			if text:find("\n", 1, true) then
				self._mlDraft = text
				text = text:gsub("\n+", " "):match("^%s*(.-)%s*$") or text
				-- Remember the exact collapsed string we put in the overlay.
				-- Enter() uses this as a fingerprint to detect whether the
				-- user has edited or cleared the overlay before re-entering
				-- multiline mode.  If the text has changed, the stash is
				-- discarded rather than silently overwriting what they typed.
				self._mlDraftCollapsed = text
			end
			eb.OverlayEdit:SetText(text)
			eb.OverlayEdit:SetCursorPosition(#text)
		end
		-- Re-show the overlay and return focus to it.
		if eb.Overlay then
			eb.Overlay:Show()
		end
		if eb.OverlayEdit then
			eb.OverlayEdit:SetFocus()
		end
	end

	-- TODO: Animate the transition (collapse).
end

--- Collapse raw multi-line text into an ordered list of chat posts.
--- Rules:
---   • A blank line (containing only whitespace) ends a paragraph.  One or
---     more consecutive blank lines count as a single paragraph separator.
---   • Single newlines within a paragraph are collapsed into a space.
---   • Leading/trailing whitespace on each post is stripped.
---   • Empty posts (all-whitespace paragraphs) are discarded.
---@param rawText string
---@return string[]  Ordered list of non-empty post strings.
local function CollapseText(rawText)
	rawText = rawText:gsub("\r\n", "\n"):gsub("\r", "\n")
	local posts   = {}
	local current = {}
	for line in (rawText .. "\n"):gmatch("([^\n]*)\n") do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed == "" then
			-- Blank line: flush whatever has accumulated as one post.
			if #current > 0 then
				posts[#posts + 1] = table.concat(current, " ")
				current = {}
			end
			-- Additional consecutive blank lines are silently ignored.
		else
			current[#current + 1] = trimmed
		end
	end
	if #current > 0 then
		posts[#posts + 1] = table.concat(current, " ")
	end
	return posts
end

--- Submit the current editor contents through the chat pipeline.
--- Blank lines create hard chunk boundaries; single newlines within a
--- paragraph collapse to a space.  PRE_SEND filters (RPPrefix, etc.) run
--- once on the first post so the prefix appears on the first chunk only.
--- All posts are chunked and delivered as one queued sequence.
--- After sending, the overlay is closed entirely.
function Multiline:Submit()
	if not self.Active then return end

	local rawText = self.EditBox and self.EditBox:GetText() or ""
	local posts   = CollapseText(rawText)
	self._mlDraft          = nil   -- discard any stashed draft; we're sending now
	self._mlDraftCollapsed = nil

	-- Empty editor: close entirely (do not return to the overlay).
	if #posts == 0 then
		local eb = YapperTable.EditBox
		self.Active = false
		if self.Frame then self.Frame:Hide() end
		if YapperTable.Spellcheck and type(YapperTable.Spellcheck.UnbindMultiline) == "function" then
			YapperTable.Spellcheck:UnbindMultiline()
		end
		if eb and eb.OverlayEdit then eb.OverlayEdit:SetText("") end
		if eb then eb:Hide() end
		return
	end

	-- Close the multiline frame before handing off to the pipeline.
	self.Active = false
	if self.Frame then self.Frame:Hide() end

	-- Restore spellcheck to the single-line overlay.
	if YapperTable.Spellcheck and type(YapperTable.Spellcheck.UnbindMultiline) == "function" then
		YapperTable.Spellcheck:UnbindMultiline()
	end

	local eb = YapperTable.EditBox
	if eb and eb.OverlayEdit then
		eb.OverlayEdit:SetText("")
	end

	-- Run PRE_SEND filters once on the first post.
	-- This is where RPPrefix prepends its prefix (first chunk only), and
	-- where external filters can cancel or modify the send.
	-- chatType/language/target may be updated by the filter payload.
	local chatType = self.ChatType
	local language = self.Language
	local target   = self.Target

	local API = YapperTable.API
	if API then
		local payload = API:RunFilter("PRE_SEND", {
			text     = posts[1],
			chatType = chatType,
			language = language,
			target   = target,
		})
		if payload == false then
			-- Filter cancelled the send.
			if eb then eb:Hide() end
			return
		end
		posts[1] = payload.text
		chatType = payload.chatType
		language = payload.language
		target   = payload.target
	end

	-- Record every post in history so the user can recall paragraphs with
	-- the Up-arrow navigation in the single-line overlay.  posts[1] already
	-- carries any PRE_SEND prefix (e.g. RPPrefix); subsequent posts don't.
	if YapperTable.History then
		for _, post in ipairs(posts) do
			YapperTable.History:AddChatHistory(post, chatType, target)
		end
	end

	-- Chunk every post and accumulate into one flat delivery list.
	-- Chunking:Split handles delineators for posts that exceed the limit.
	local Chunking = YapperTable.Chunking
	local cfg      = YapperTable.Config and YapperTable.Config.Chat or {}
	local limit    = cfg.CHARACTER_LIMIT or 255

	local allChunks = {}
	for _, post in ipairs(posts) do
		if Chunking and #post > limit then
			local chunks = Chunking:Split(post, limit)
			for _, chunk in ipairs(chunks) do
				allChunks[#allChunks + 1] = chunk
			end
		else
			allChunks[#allChunks + 1] = post
		end
	end

	-- Deliver the flat chunk list as a single queued sequence.
	local Chat = YapperTable.Chat
	local Q    = YapperTable.Queue
	if #allChunks == 1 then
		if Chat then Chat:DirectSend(allChunks[1], chatType, language, target) end
	elseif Q then
		Q:Enqueue(allChunks, chatType, language, target)
		Q:Flush(true)
	elseif Chat then
		for _, chunk in ipairs(allChunks) do
			Chat:DirectSend(chunk, chatType, language, target)
		end
	end

	-- Hide the overlay entirely — submit means done, not back to overlay.
	if eb then eb:Hide() end
end

--- Cancel editing — return to the single-line overlay with the draft intact.
function Multiline:Cancel()
	self:Exit(true)
end

-- ---------------------------------------------------------------------------
-- Auto-expand detection
-- ---------------------------------------------------------------------------

--- Called by EditBox when the text approaches or exceeds the visible width.
--- Returns true if auto-expand is enabled and the transition should occur.
---@param textWidth  number  Pixel width of the current text.
---@param boxWidth   number  Pixel width of the single-line overlay.
---@return boolean
function Multiline:ShouldAutoExpand(textWidth, boxWidth)
	local cfg = GetConfig()
	if not cfg.autoExpand then return false end
	if self.Active then return false end

	-- Trigger when text fills ≥95 % of the available width.
	return textWidth >= (boxWidth * 0.95)
end

-- ---------------------------------------------------------------------------
-- Theme / appearance
-- ---------------------------------------------------------------------------

--- Apply the current theme's colours and font to the multi-line frame.
--- Mirrors the same font-resolution logic as the single-line overlay:
---   cfg.FontFace / cfg.FontSize override; otherwise inherit from OrigEditBox.
--- Called from Enter() and whenever ApplyConfigToLiveOverlay fires.
function Multiline:ApplyTheme()
	if not self.Frame or not self.EditBox then return end

	local cfg     = (YapperTable.Config and YapperTable.Config.EditBox) or {}
	local cfgFace  = cfg.FontFace
	local cfgSize  = cfg.FontSize or 0
	local cfgFlags = cfg.FontFlags or ""

	local eb      = YapperTable.EditBox
	local origEB  = eb and eb.OrigEditBox

	if cfgFace or cfgSize > 0 then
		local baseFace, baseSize, baseFlags
		if origEB and origEB.GetFont then
			baseFace, baseSize, baseFlags = origEB:GetFont()
		end
		local face  = cfgFace  or baseFace  or "Fonts\\FRIZQT__.TTF"
		local size  = cfgSize > 0 and cfgSize or baseSize or 14
		local flags = (cfgFlags ~= "") and cfgFlags or baseFlags or ""
		self.EditBox:SetFont(face, size, flags)
		if self.LabelFS then self.LabelFS:SetFont(face, size, flags) end
	elseif origEB and origEB.GetFontObject then
		local fontObj = origEB:GetFontObject()
		if fontObj then
			self.EditBox:SetFontObject(fontObj)
			if self.LabelFS then self.LabelFS:SetFontObject(fontObj) end
		end
	else
		-- Fallback: inherit from the overlay edit box if available.
		local overlayEdit = eb and eb.OverlayEdit
		if overlayEdit and overlayEdit.GetFontObject then
			local fontObj = overlayEdit:GetFontObject()
			if fontObj then
				self.EditBox:SetFontObject(fontObj)
				if self.LabelFS then self.LabelFS:SetFontObject(fontObj) end
			end
		else
			self.EditBox:SetFontObject(ChatFontNormal)
		end
	end

	-- Visual appearance: read the fill colour the overlay is actually rendering.
	-- SetFrameFillColour now caches the last colour set on any overlay frame as
	-- _yapperFillColor, so we don't need GetVertexColor / GetBackdropColor (both
	-- have API quirks).  Fall back to config if the overlay hasn't been drawn yet.
	local eb      = YapperTable.EditBox
	local overlay = eb and eb.Overlay

	local fillR, fillG, fillB, fillA = 0.05, 0.05, 0.05, 0.95
	local rounded = false

	if overlay and overlay._yapperFillColor then
		local c = overlay._yapperFillColor
		fillR, fillG, fillB, fillA = c.r, c.g, c.b, c.a
		rounded = overlay._yapperFillRounded == true
	else
		-- Fallback: read from config (same path the overlay uses).
		local activeTheme = YapperTable.Theme and YapperTable.Theme:GetTheme()
		local inputBg = cfg.InputBg or {}
		fillR = inputBg.r or 0.05
		fillG = inputBg.g or 0.05
		fillB = inputBg.b or 0.05
		fillA = inputBg.a or 0.95
		if activeTheme and activeTheme.inputBg then
			local tbg = activeTheme.inputBg
			fillR = tbg.r or fillR
			fillG = tbg.g or fillG
			fillB = tbg.b or fillB
			fillA = tbg.a or fillA
		end
		rounded = (cfg.RoundedCorners == true)
		if activeTheme and activeTheme.allowRoundedCorners == false then rounded = false end
	end

	local borderCfg = cfg.BorderColor or {}
	local bR = borderCfg.r or 0.3
	local bG = borderCfg.g or 0.3
	local bB = borderCfg.b or 0.3
	local bA = borderCfg.a or 0.8
	if rounded then bR, bG, bB, bA = fillR, fillG, fillB, fillA end

	-- Switch the backdrop edgeFile to match the rounded setting, so the border
	-- shape matches the horizontal overlay exactly.
	local f = self.Frame
	f:SetBackdrop({
		bgFile   = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = rounded and "Interface/Tooltips/UI-Tooltip-Border"
		                    or "Interface/Buttons/WHITE8X8",
		edgeSize = rounded and 10 or 1,
		insets   = rounded and { left = 3, right = 3, top = 3, bottom = 3 }
		                    or { left = 1, right = 1, top = 1, bottom = 1 },
	})
	f:SetBackdropColor(fillR, fillG, fillB, fillA)
	f:SetBackdropBorderColor(bR, bG, bB, bA)

	-- Shadow: read settings from config (same source the overlay uses).
	local shadow    = cfg.Shadow == true
	local activeThemeForShadow = YapperTable.Theme and YapperTable.Theme:GetTheme()
	if activeThemeForShadow and activeThemeForShadow.allowDropShadow == false then shadow = false end
	local shadCol = cfg.ShadowColor or { r = 0, g = 0, b = 0, a = 0.5 }
	local shadSz  = cfg.ShadowSize or 4
	-- f is already set above (the multiline Frame)
	if shadow then
		if not f._yapperShadowLayer then
			f._yapperShadowLayer = CreateFrame("Frame", nil, f)
			f._yapperShadowLayer:SetFrameLevel(math_max(0, f:GetFrameLevel() - 1))
			f._yapperShadowLayer:SetAllPoints(f)
			f._yapperShadows = {}
			for i = 1, 3 do
				local stex = f._yapperShadowLayer:CreateTexture(nil, "BACKGROUND")
				table_insert(f._yapperShadows, stex)
			end
		end
		f._yapperShadowLayer:Show()
		for i, stex in ipairs(f._yapperShadows) do
			local offset  = (i / 3) * shadSz
			local falloff = { 0.5, 0.3, 0.15 }
			stex:ClearAllPoints()
			stex:SetPoint("TOPLEFT",     f, "TOPLEFT",     -offset,  offset)
			stex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  offset, -offset)
			stex:SetColorTexture(
				shadCol.r or 0, shadCol.g or 0, shadCol.b or 0,
				(shadCol.a or 0.5) * (falloff[i] or 0.1))
		end
	else
		if f._yapperShadowLayer then f._yapperShadowLayer:Hide() end
	end
end

-- ---------------------------------------------------------------------------
-- Resize handle
-- ---------------------------------------------------------------------------

--- Create a draggable resize grip at the bottom-right corner.
function Multiline:CreateResizeGrip()
	if not self.Frame or self._resizeGrip then return end

	local grip = CreateFrame("Button", nil, self.Frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

	grip:SetScript("OnMouseDown", function()
		self.Frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		self.Frame:StopMovingOrSizing()
		-- TODO: persist new dimensions to config.
	end)

	self._resizeGrip = grip
end
