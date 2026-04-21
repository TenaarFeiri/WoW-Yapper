--[[
    WIMBridge.lua
    Compatibility bridge for WoW Instant Messenger (WIM).

    WIM creates its own whisper editboxes and handles whisper focus
    independently.  When WIM has an active whisper window with focus,
    Yapper should step back and let WIM drive the keyboard.

    This bridge centralises WIM detection and registers a PRE_EDITBOX_SHOW
    filter via the public API so external addons can also participate in
    overlay-suppression decisions.
]]

local _, YapperTable = ...

local Bridge = {}
YapperTable.WIMBridge = Bridge

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Check whether a WIM editbox currently owns user focus.
--- @return boolean
function Bridge:IsFocusActive()
	---@diagnostic disable-next-line: undefined-field
	local wim = _G.WIM
	if not wim then return false end

	local focus = wim.EditBoxInFocus
	if not focus then return false end

	local isShown   = focus.IsShown   and focus:IsShown()
	local isVisible = focus.IsVisible and focus:IsVisible()
	local hasFocus  = focus.HasFocus  and focus:HasFocus()

	return (isShown == true) or (isVisible == true) or (hasFocus == true)
end

--- Check whether the WIM addon is loaded in the environment.
--- @return boolean
function Bridge:IsLoaded()
	return _G.WIM ~= nil
end

-- ---------------------------------------------------------------------------
-- Initialisation (called from Chat:Init)
-- ---------------------------------------------------------------------------

function Bridge:Init()
	if not _G.YapperAPI then return end

	-- Suppress Yapper overlay when WIM owns whisper focus.
	-- Priority 5 (runs early) so addons registering at default 10 can
	-- override the decision if needed.
	_G.YapperAPI:RegisterFilter("PRE_EDITBOX_SHOW", function(payload)
		if not Bridge:IsFocusActive() then return payload end

		local ct = payload and payload.chatType
		local isWhisper = (ct == "BN_WHISPER" or ct == "WHISPER")

		-- chatType may be unset in some open paths; if WIM has focus,
		-- prefer suppressing to avoid fighting over whisper ownership.
		if isWhisper or ct == nil or ct == "" then
			if YapperTable.Utils and YapperTable.Utils.DebugPrint then
				YapperTable.Utils:DebugPrint("WIMBridge: suppressing overlay (chatType=" .. tostring(ct) .. ")")
			end
			return false
		end

		return payload
	end, 5)
end
