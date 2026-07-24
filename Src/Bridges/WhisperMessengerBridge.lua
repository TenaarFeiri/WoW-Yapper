--[[
    WhisperMessengerBridge.lua
    Compatibility bridge for WhisperMessenger.

    When the WM window is open, Yapper should not steal focus — the user is
    working in WM's composer.  This bridge:

    1. PRE_EDITBOX_SHOW filter: suppresses Yapper's overlay while keyboard
       focus belongs to WM, so reply keybinds routed by WM don't pop Yapper.

    2. EditBox:Show guard: final safety net for any Yapper open path that does
       not run through PRE_EDITBOX_SHOW.

    3. REPLYTELL2 (Re-Whisper) wrapping: does nothing when WM's window is open
       (WM owns the reply), and falls through to Yapper's normal handler when
       WM is closed.

    Known issue: pressing the reply key while WM is open leaks the bound key
    character into WM's composer and WM clears the composer as part of its own
    reply flow.  This is WM-side behaviour (reproducible without Yapper) and is
    not handled here.

    We do not modify WhisperMessenger.  The bridge only observes its globally
    named main window frame: _G.WhisperMessengerWindow.

    Detection is deferred via ADDON_LOADED so the bridge works regardless of
    which addon loads first.
]]

local _, YapperTable = ...

local Bridge = {}
YapperTable.WhisperMessengerBridge = Bridge

Bridge._initialised = false

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Check whether WhisperMessenger is loaded.
--- @return boolean
function Bridge:IsLoaded()
    return type(_G.WhisperMessenger_Toggle) == "function"
        or _G.WhisperMessengerWindow ~= nil
end

--- Check whether the WM window is currently visible.
--- @return boolean
function Bridge:IsWindowVisible()
    local window = _G.WhisperMessengerWindow
    if not window or not window.IsShown then
        return false
    end
    return window:IsShown()
end

--- Check whether keyboard focus currently belongs to WM or one of its children.
--- @return boolean
function Bridge:IsFocusActive()
    if not self:IsWindowVisible() or type(_G.GetCurrentKeyBoardFocus) ~= "function" then
        return false
    end

    local window = _G.WhisperMessengerWindow
    local focus = _G.GetCurrentKeyBoardFocus()
    local depth = 0
    while focus and depth < 32 do
        if focus == window then
            return true
        end
        if not focus.GetParent then
            return false
        end
        focus = focus:GetParent()
        depth = depth + 1
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Reply keybind interception (REPLYTELL2)
-- ---------------------------------------------------------------------------

--- Wrap the REPLYTELL2 secure button's PostClick so the reply/re-whisper
--- keybind is ignored by Yapper when WM's window is open, falling back to
--- Yapper's original handler when WM is closed.
function Bridge:WrapReplyKeybind()
    local Keybinds = YapperTable.EditBox and YapperTable.EditBox.Keybinds
    if not Keybinds or not Keybinds._secureButtons then
        return
    end

    local button = Keybinds._secureButtons["REPLYTELL2"]
    if not button or button._wmBridgeWrapped then
        return
    end
    button._wmBridgeWrapped = true

    local originalPostClick = button:GetScript("PostClick")
    local Utils = YapperTable.Utils

    button:SetScript("PostClick", function()
        -- If the post queue is stalled and waiting for Enter to continue,
        -- progress the queue instead of routing to WhisperMessenger.
        local Queue = YapperTable.Queue
        if Queue and Queue.TryContinue and Queue:TryContinue() then
            Queue:SendNext(true)
            return
        end

        -- During chat/combat lockdown, fall through to Yapper's handler which
        -- delegates to Blizzard's own OpenChat flow.
        local inLockdown = Utils and Utils.IsChatLockdown and Utils:IsChatLockdown()
        local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
        if inLockdown or inCombat then
            if originalPostClick then
                originalPostClick()
            end
            return
        end

        -- WM owns the reply binding and composer.  Do not let Yapper's handler
        -- run while its window is open.
        if Bridge:IsWindowVisible() then
            if Utils and Utils.DebugPrint then
                Utils:DebugPrint("WhisperMessengerBridge: ignored REPLYTELL2 (WM window open)")
            end
            return
        end

        -- Fall through to Yapper's original handler when WM is closed.
        if originalPostClick then
            originalPostClick()
        end
    end)
end

--- Hook Keybinds.CreateSecureButtons so the bridge re-wraps whenever the
--- secure buttons are (re)created (e.g. after a keybind refresh).
function Bridge:HookSecureButtonCreation()
    local Keybinds = YapperTable.EditBox and YapperTable.EditBox.Keybinds
    if not Keybinds or Keybinds._wmCreateHooked then
        return
    end
    Keybinds._wmCreateHooked = true

    local originalCreate = Keybinds.CreateSecureButtons
    if not originalCreate then
        return
    end

    Keybinds.CreateSecureButtons = function(self, ...)
        originalCreate(self, ...)
        Bridge:WrapReplyKeybind()
    end
end

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

function Bridge:Init()
    if self._initialised then
        return
    end

    if not self:IsLoaded() then
        return
    end

    self._initialised = true

    -- Register PRE_EDITBOX_SHOW filter: suppress Yapper's overlay only while
    -- keyboard focus belongs to WM.  A visible but defocused WM window must not
    -- prevent Enter from opening Yapper.
    -- Priority 5 (runs early) so default-priority filters see the decision.
    if _G.YapperAPI and type(_G.YapperAPI.RegisterFilter) == "function" then
        _G.YapperAPI:RegisterFilter("PRE_EDITBOX_SHOW", function(payload)
            if Bridge:IsFocusActive() then
                if YapperTable.Utils and YapperTable.Utils.DebugPrint then
                    YapperTable.Utils:DebugPrint("WhisperMessengerBridge: suppressing overlay (WM focus active)")
                end
                return false
            end
            return payload
        end, 5)
    end

    -- Guard the final Show entry point as well.  PRE_EDITBOX_SHOW is advisory
    -- and not every internal path reaches it; this prevents Yapper from stealing
    -- focus back while WM owns keyboard focus.
    local EditBox = YapperTable.EditBox
    if EditBox and EditBox.Show and not EditBox._wmShowWrapped then
        EditBox._wmShowWrapped = true
        local originalShow = EditBox.Show
        EditBox.Show = function(editBox, ...)
            if Bridge:IsFocusActive() then
                return
            end
            return originalShow(editBox, ...)
        end
    end

    -- Hook button creation so we stay wrapped across keybind refreshes.
    self:HookSecureButtonCreation()

    -- Wrap the existing REPLYTELL2 button (buttons may already exist if
    -- Keybinds:Init() has run).
    self:WrapReplyKeybind()

    if YapperTable.Utils and YapperTable.Utils.DebugPrint then
        YapperTable.Utils:DebugPrint("WhisperMessengerBridge: initialised")
    end
end

-- ---------------------------------------------------------------------------
-- Deferred init
-- ---------------------------------------------------------------------------

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("ADDON_LOADED")

addonFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "PLAYER_LOGIN" or addonName == "WhisperMessenger" then
        Bridge:Init()
    end
end)
