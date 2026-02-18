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

GopherBridge.active           = false -- true after a successful Init
GopherBridge._gopher          = nil

-- A chunk size large enough that Gopher will never re-split our text.
local PASSTHROUGH_CHUNK_SIZE  = 6000

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Find and return the LibGopher public table, or nil.
local function FindGopher()
    if _G.LibGopher and type(_G.LibGopher) == "table" then
        return _G.LibGopher
    end
    if _G.LibStub then
        local ok, lib = pcall(_G.LibStub, _G.LibStub, "Gopher", true)
        if ok and lib then return lib end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Call once during startup (from Chat:Init / Router:Init).
--- Returns true if LibGopher was found and the bridge is now active.
function GopherBridge:Init()
    if self.active then return true end

    -- Respect user config
    if YapperTable.Config.System.EnableGopherBridge == false then
        return false
    end

    local gopher = FindGopher()
    if not gopher then return false end

    -- Make sure the API we need actually exists.
    if type(gopher.SetTempChunkSize) ~= "function" then return false end

    self._gopher = gopher
    self.active  = true

    YapperTable.Utils:VerbosePrint("GopherBridge: LibGopher detected — sending through Gopher's pipeline.")
    return true
end

--- Called by Interface when the toggle is changed.
function GopherBridge:UpdateState()
    local enabled = (YapperTable.Config.System.EnableGopherBridge == true)

    if not enabled and self.active then
        self.active = false
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
        local clubId   = tonumber(language)
        local streamId = tonumber(target)
        if clubId and streamId and _G.C_Club then
            _G.C_Club.SendMessage(clubId, streamId, msg)
            return true
        end
        return false
    end

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
