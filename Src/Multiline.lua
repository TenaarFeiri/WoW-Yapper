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
local math_max   = math.max
local math_min   = math.min
local math_abs   = math.abs

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
	f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:SetResizable(true)
	f:SetResizeBounds(200, 100, 800, 600)
	f:Hide()
	self.Frame = f

	-- TODO: Apply backdrop / theme colours consistent with the single-line overlay.

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
	edit:SetWidth(sf:GetWidth() or cfg.defaultWidth - 36)
	edit:SetScript("OnEscapePressed", function() Multiline:Cancel() end)
	sf:SetScrollChild(edit)
	self.EditBox = edit

	-- TODO: Hook OnEnterPressed for submit (Shift+Enter or plain Enter,
	--       depending on user preference).
	-- TODO: Hook OnTextChanged for auto-sizing the scroll child height.
	-- TODO: Character counter overlay.
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

	self.ChatType = chatType or "SAY"
	self.Language = language
	self.Target   = target

	-- Populate the editor with the current single-line text.
	self.EditBox:SetText(text or "")
	self.EditBox:SetCursorPosition(#(text or ""))

	-- Update channel label.
	if self.LabelFS then
		self.LabelFS:SetText("[" .. tostring(self.ChatType) .. "]")
	end

	-- Hide the single-line overlay.
	if YapperTable.EditBox and YapperTable.EditBox.Hide then
		YapperTable.EditBox:Hide()
	end

	-- TODO: Animate the transition (slide / expand).

	self.Frame:Show()
	self.EditBox:SetFocus()
	self.Active = true
end

--- Close the expanded editor and return to the single-line overlay.
---@param restoreText boolean?  If true, push the current text back to the overlay.
function Multiline:Exit(restoreText)
	if not self.Active then return end

	local text = self.EditBox and self.EditBox:GetText() or ""
	self.Active = false

	if self.Frame then
		self.Frame:Hide()
	end

	-- Restore text to the single-line overlay if requested.
	if restoreText and YapperTable.EditBox then
		-- TODO: implement a SetText / Restore path on EditBox.
	end

	-- TODO: Animate the transition (collapse).
end

--- Submit the current editor contents through the chat pipeline.
function Multiline:Submit()
	if not self.Active then return end

	local text = self.EditBox and self.EditBox:GetText() or ""
	if text == "" then
		self:Exit(false)
		return
	end

	-- Hand off to Chat:OnSend exactly as the single-line overlay would.
	if YapperTable.Chat and YapperTable.Chat.OnSend then
		YapperTable.Chat:OnSend(text, self.ChatType, self.Language, self.Target)
	end

	self:Exit(false)
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
--- Called when the user changes theme or when the frame is first created.
function Multiline:ApplyTheme()
	if not self.Frame then return end
	-- TODO: read colours from YapperTable.Config.EditBox and apply backdrop,
	--       font face, font size, shadow, etc.
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
