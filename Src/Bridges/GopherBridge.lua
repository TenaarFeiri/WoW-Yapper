--[[
    Compatibility bridge for LibGopher.

    When LibGopher is present (e.g. bundled with CrossRP), Yapper delegates
    actual sending to Gopher's hooked globals so that:
        • Gopher's queue, throttler, and confirmation system remain active.
        • Other addons that Listen() on Gopher events (CrossRP) still work.
        • Yapper controls its own splitting — we set a huge TempChunkSize so
          Gopher passes our pre-split chunks through untouched.

    When LibGopher is absent, this module sleeps and Router uses the
    normal Yapper pipeline.
]]

local YapperName, YapperTable = ...

local GopherBridge            = {}
YapperTable.GopherBridge      = GopherBridge

-- Localise Lua globals for performance
local type     = type
local tonumber = tonumber
local pcall    = pcall

GopherBridge.active           = false -- true after a successful Init
GopherBridge._gopher          = nil
GopherBridge._filterHandle    = nil -- PRE_EDITBOX_SHOW filter handle
GopherBridge._initAttempted    = false -- true once we've tried to init

-- A chunk size large enough that Gopher will never re-split our text.
local PASSTHROUGH_CHUNK_SIZE  = 6000

-- Event frame for self-contained discovery
local eventFrame = CreateFrame("Frame")
eventFrame:Hide()

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Find and return the LibGopher public table, or nil.
local function FindGopher()
    ---@diagnostic disable-next-line: undefined-field
    if _G.LibGopher and type(_G.LibGopher) == "table" then
        return _G.LibGopher
    end
    if _G.LibStub then
        local ok, lib = pcall(function(...) return _G.LibStub(...) end, "Gopher", true)
        if ok and lib then return lib end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Internal init attempt. Called on load and on ADDON_LOADED events.
--- Self-contained: no external caller needed.
local function TryInit()
    local self = GopherBridge
    if self.active or self._initAttempted then return end
    
    -- Respect user config
    if YapperTable.Config.System.EnableGopherBridge == false then
        self._initAttempted = true
        return
    end
    
    local gopher = FindGopher()
    if not gopher then return end -- Will retry on next ADDON_LOADED
    
    self:_DoInit(gopher)
end

--- Actually perform init once Gopher is found.
--- gopher parameter is already validated by TryInit.
function GopherBridge:_DoInit(gopher)
    if self.active or self._initAttempted then return end
    self._initAttempted = true

    -- Make sure the API we need actually exists.
    if type(gopher.SetTempChunkSize) ~= "function" then return end

    self._gopher = gopher
    self.active  = true
    
    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("GopherBridge: LibGopher detected — sending through Gopher's pipeline.")
    end
    
    -- Stop watching for addon loads - we're done
    eventFrame:UnregisterEvent("ADDON_LOADED")
    eventFrame:Hide()

    if not _G.YapperAPI then return end

    -- Register PRE_EDITBOX_SHOW filter to coordinate with Gopher's hardware event needs.
    -- We only block when Gopher specifically needs a hardware event, not for general
    -- busy states. This allows Yapper to open for normal sending while still
    -- coordinating for hardware-event-required states.
    self._filterHandle = _G.YapperAPI:RegisterFilter("PRE_EDITBOX_SHOW", function(payload)
            local gopher = self._gopher
            -- Check if Gopher specifically needs a hardware event to continue.
            if self:NeedsHardwareEvent() then
                -- Nudge Gopher to try to consume this keystroke internally.
                -- TryContinuePrompt checks ThrottlerHealth() and will advance if possible.
                if type(gopher.Internal.TryContinuePrompt) == "function" then
                    gopher.Internal.TryContinuePrompt()
                -- Fallback to direct keystroke injection
                elseif type(gopher.Internal.PipeThrottlerKeystroke) == "function" then
                    gopher.Internal.PipeThrottlerKeystroke()
                end
                -- Check again after nudge - if Gopher consumed the event, allow Yapper to open.
                -- Otherwise we must block because Gopher needs this hardware event.
                if not self:NeedsHardwareEvent() then
                    return payload
                end
                return false
            end
            -- Hide Blizzard editboxes which Gopher may have shown during normal processing.
            for i = 1, 10 do
                local editBox = _G["ChatFrame" .. i .. "EditBox"]
                if editBox then
                    editBox:Hide()
                end
            end
            return payload
        end)

    -- Register PRE_DELIVER filter to claim send authority.
    -- Return false to trigger delegation; Chat.lua creates the claim and
    -- fires POST_CLAIMED. We handle the actual send in the callback.
    self._deliverFilterHandle = _G.YapperAPI:RegisterFilter("PRE_DELIVER", function(payload)
        -- Claim this send for Gopher's pipeline. The actual work happens
        -- in POST_CLAIMED callback (proper delegation pipeline).
        return false
    end)

    -- Handle claimed sends: send via Gopher and immediately resolve.
    -- Gopher manages its own confirmation/timeout; we just bridge it.
    self._claimedCallback = _G.YapperAPI:RegisterCallback("POST_CLAIMED", function(handle, msg, chatType, language, target)
        self:Send(msg, chatType, language, target)
        _G.YapperAPI:ResolvePost(handle)
    end)

    return
end

--- Called by Interface when the toggle is changed.
function GopherBridge:UpdateState()
    local enabled = (YapperTable.Config.System.EnableGopherBridge == true)

    if not enabled and self.active then
        self.active = false
        if _G.YapperAPI then
            if self._filterHandle then
                _G.YapperAPI:UnregisterFilter(self._filterHandle)
                self._filterHandle = nil
            end
            if self._deliverFilterHandle then
                _G.YapperAPI:UnregisterFilter(self._deliverFilterHandle)
                self._deliverFilterHandle = nil
            end
            if self._claimedCallback then
                _G.YapperAPI:UnregisterCallback(self._claimedCallback)
                self._claimedCallback = nil
            end
        end
        YapperTable.Utils:VerbosePrint("GopherBridge: Disabled by user setting.")
    elseif enabled and not self.active then
        -- Attempt to re-init if available
        self:Init()
    end
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

--- Send a single pre-split chunk through Gopher's hooked globals.
--- Gopher will queue/throttle/confirm it, and fire its own events so that
--- CrossRP and other listeners still work.
---
--- We set TempChunkSize to a huge value so Gopher's splitter is effectively
--- a no-op for our already-split text.
---
--- @param msg      string   The message text (already split by Yapper).
--- @param chatType string   "SAY", "EMOTE", "WHISPER", "BN_WHISPER", etc.
--- @param language any      Language ID, club ID, or nil.
--- @param target   any      Channel name, whisper target, streamId, etc.
--- @return boolean          true if the send was handed to Gopher.
function GopherBridge:Send(msg, chatType, language, target)
    if not self.active or not self._gopher then return false end
    if not msg or msg == "" then return false end

    chatType = chatType or "SAY"

    -- Tell Gopher not to re-split this chunk.
    self._gopher.SetTempChunkSize(PASSTHROUGH_CHUNK_SIZE)

    -- Battle.net whisper
    if chatType == "BN_WHISPER" or chatType == "BNET" then
        local presenceID = tonumber(target)
        if not presenceID then
            YapperTable.Utils:DebugPrint(
                "GopherBridge: BNet whisper with no valid presenceID.")
            return false
        end
        -- Call the *hooked* global so Gopher intercepts it.
        _G.BNSendWhisper(presenceID, msg)
        return true
    end

    -- Community / Club
    if chatType == "CLUB" then
        -- In WoW, Club and Stream IDs are 64-bit integers passed as strings.
        -- Converting them to numbers causes precision loss.
        local clubId   = language
        local streamId = target
        if clubId and streamId and _G.C_Club then
            _G.C_Club.SendMessage(clubId, streamId, msg)
            return true
        end
        return false
    end

    -- Normalise language parameter to match Router's behaviour
    -- This ensures racial languages and other custom languages are properly resolved
    language = YapperTable.Core:GetCharacterLanguage(language)

    -- Everything else (SAY, EMOTE, YELL, PARTY, RAID, WHISPER, CHANNEL…)
    C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    return true
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

function GopherBridge:IsActive()
    return self.active == true
end

--- Return true if Gopher is processing.
--- Uses Gopher's own SendingActive() API.
--- Keeps Yapper from trying to engage until Gopher is done posting.
function GopherBridge:IsBusy()
    if not self.active or not self._gopher then return false end
    if type(self._gopher.SendingActive) == "function" then
        return self._gopher.SendingActive() == true
    end
    return false
end

--- Return true if Gopher specifically needs a hardware event to continue.
--- This is more granular than IsBusy() - it only returns true when Gopher
--- is blocked waiting for user input (say/yell/channel require hardware events).
--- Normal sending/throttling states return false, allowing Yapper to open.
function GopherBridge:NeedsHardwareEvent()
    if not self.active or not self._gopher then return false end
    -- Use internal state directly - prompt_continue is true when Gopher's
    -- throttler returned "PROMPT" status and is showing the continue frame.
    local internal = self._gopher.Internal
    if internal and internal.prompt_continue == true then
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Self-contained discovery
-- ---------------------------------------------------------------------------
-- Watch for ADDON_LOADED to catch when Gopher loads (it may load after Yapper).
-- Stop at PLAYER_ENTERING_WORLD (all addons should be loaded by then).

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        TryInit()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Last chance - try once more, then give up
        TryInit()
        eventFrame:UnregisterEvent("ADDON_LOADED")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:Hide()
    end
end)

-- Start watching immediately
if IsLoggedIn() then
    -- Already in world, try now
    TryInit()
else
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:Show()
    -- Also try immediately in case Gopher is already loaded
    TryInit()
end

-- ---------------------------------------------------------------------------
-- API self-registration
-- ---------------------------------------------------------------------------
-- React to the toggle via the public event system as well.

if _G.YapperAPI then
    _G.YapperAPI:RegisterCallback("CONFIG_CHANGED", function(path, value)
        if path == "System.EnableGopherBridge" then
            GopherBridge:UpdateState()
        end
    end)
end
