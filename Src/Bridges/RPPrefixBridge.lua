--[[
    Compatibility bridge for RPPrefix (by Zee / Songzee – Argent Dawn EU).

    Without this bridge, RPPrefix's C_ChatInfo.SendChatMessage hook fires on
    every individual chunk that Yapper queues, prepending the user's RP prefix
    to *every* continuation post.  This bridge fixes that by:

        1.  Detecting whether RPPrefix is present at Chat:Init time
            (called during PLAYER_ENTERING_WORLD, after all addons have loaded).

        2.  Caching the raw C_ChatInfo.SendChatMessage API and replacing
            Router.SendChatMessage with it, so per-chunk sends bypass
            RPPrefix's hook entirely.

        3.  Exposing ApplyPrefix(text, chatType), called by Chat:OnSend before
            the message reaches the chunker.  If RPPrefix is enabled and the
            conditions match, the prefix is prepended to the full message text
            so only the first post carries it.

    RPPrefix's own toggle button continues to control whether the prefix is
    active; Yapper merely shifts *where* in the pipeline it is applied.
]]

local _, YapperTable = ...

local RPPrefixBridge          = {}
YapperTable.RPPrefixBridge    = RPPrefixBridge

-- Localise Lua globals for performance
local type     = type
local tostring = tostring

-- The placeholder text RPPrefix shows when no real prefix is set.
local PLACEHOLDER = "|cFF707070Type prefix here"

-- Cached reference to the unwrapped C_ChatInfo.SendChatMessage.
-- Assigned during Init and used to patch Router.SendChatMessage.
local _rawSendChatMessage = nil

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

--- Return the Zee.RPPrefix table if the addon is loaded and registered, else nil.
local function FindRPPrefix()
    -- Primary: check global table set by RPPrefix.lua at file scope.
    local Zee = _G.Zee
    if not Zee then return nil end
    local rp = Zee.RPPrefix
    if type(rp) ~= "table" then return nil end
    return rp
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Called once from Chat:Init, after Router:Init has already cached
--- Router.SendChatMessage.  At PLAYER_ENTERING_WORLD all addons are loaded.
---
--- @return boolean  true if RPPrefix was found and the bridge is now active.
function RPPrefixBridge:Init()
    if self.active then return true end

    local rp = FindRPPrefix()
    if not rp then
        YapperTable.Utils:VerbosePrint("RPPrefixBridge: RPPrefix not found — bridge inactive.")
        return false
    end

    -- RPPrefix installs its C_ChatInfo.SendChatMessage hook only when the
    -- user first clicks the toggle (RP.Hooked flips to true then).
    -- On every fresh login the toggle starts off, so the hook is not yet
    -- installed at PLAYER_ENTERING_WORLD.  Either way, the correct raw API
    -- to cache is:
    --   • If already hooked: rp.SavedSendChatMessage (RPPrefix stored it).
    --   • If not yet hooked: the current global IS the raw API.
    if rp.Hooked and type(rp.SavedSendChatMessage) == "function" then
        _rawSendChatMessage = rp.SavedSendChatMessage
    else
        _rawSendChatMessage = C_ChatInfo.SendChatMessage
    end

    -- Replace Router.SendChatMessage with the raw API so the Queue's per-
    -- chunk calls go directly to Blizzard and bypass RPPrefix's hook.
    local Router = YapperTable.Router
    if Router and _rawSendChatMessage then
        Router.SendChatMessage = _rawSendChatMessage
    end

    self.active = true
    YapperTable.Utils:VerbosePrint("RPPrefixBridge: RPPrefix detected — prefix will be prepended to the first chunk only.")
    return true
end

--- Returns true if the bridge found RPPrefix and is active.
function RPPrefixBridge:IsActive()
    return self.active == true
end

-- ---------------------------------------------------------------------------
-- Prefix injection
-- ---------------------------------------------------------------------------

--- Return `text` with the user's RP prefix prepended when all of RPPrefix's
--- own conditions are satisfied.  Called by Chat:OnSend before chunking so
--- the prefix appears on the first post and nowhere else.
---
--- Mirrors the conditions in RPPrefix's Hook_SendChatMessage:
---   • Zee.RPPrefix.Enabled is true
---   • chatType is "SAY" or "YELL"
---   • text does not start with "/" (slash commands are passed through)
---   • the saved prefix is not the placeholder default
---
--- @param text     string  Full message text before splitting.
--- @param chatType string  WoW chat type ("SAY", "YELL", …).
--- @return string          Prefix-prepended text, or the original text.
function RPPrefixBridge:ApplyPrefix(text, chatType)
    if not self.active then return text end
    if not text or text == "" then return text end

    -- Consult RPPrefix's live state.
    local rp = _G.Zee and _G.Zee.RPPrefix
    if not rp or not rp.Enabled then return text end

    -- Channel guard — RPPrefix only touches SAY and YELL.
    if chatType ~= "SAY" and chatType ~= "YELL" then return text end

    -- Slash-command guard.
    if text:sub(1, 1) == "/" then return text end

    -- Retrieve the stored prefix.
    local settings = _G.RPPrefix_Settings_New
    if not settings then return text end
    local prefix = settings.PreviousPrefix
    if not prefix or prefix == "" or prefix == PLACEHOLDER then return text end

    return prefix .. " " .. text
end
