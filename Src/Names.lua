--[[
    Names.lua
    Session-only registry of player names observed in-world. Feeds the
    spellcheck pipeline so character names count as known vocabulary:
    never flagged, never autocorrected, and offered to autocomplete.

    Safety model -- fail-closed everywhere:
      * Every ingress passes Utils:IsSecret; secret values are never
        stored, compared, concatenated, or persisted.
      * Nothing is collected while combat is active (InCombatLockdown) --
        combat halts all harvesting, including sources that would still
        return data.
      * Nothing is collected while ANY addon restriction type is
        enforced; restricted contexts can hand back secret strings even
        from APIs that are safe at other times.
      * Entering a restricted state purges the buffer; it rebuilds from
        fresh sweeps once clear.
      * Memory only: a fixed-size ring that is never written to
        SavedVariables.
]]

local _, YapperTable = ...

local Names = {}
YapperTable.Names = Names

local string_lower  = string.lower
local string_gmatch = string.gmatch
local ipairs        = ipairs
local pcall         = pcall
local type          = type

-- Ring capacity: comfortably covers a large guild, friends, raid, and
-- city traffic. Oldest entries evict first.
local CAPACITY = 512

Names._set            = {}     -- canonical lowercase key -> true
Names._order          = {}     -- FIFO eviction order
Names._pendingSweep   = false  -- a sweep was requested while unsafe
Names._retryScheduled = false  -- a deferred-sweep retry is queued

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

--- Harvest gate: false while combat is active or ANY addon restriction
--- type is enforced. Combat is an absolute stop -- never harvest during
--- combat, including "safe" combat where APIs still return data.
local function CanHarvest()
    local pol = YapperTable.LockdownPolicy
    if pol and type(pol.IsCombatLockdown) == "function" then
        if pol:IsCombatLockdown() then return false end
    elseif InCombatLockdown and InCombatLockdown() then
        return false
    end
    if pol and type(pol.IsAnyAddOnRestrictionActive) == "function"
        and pol:IsAnyAddOnRestrictionActive() then
        return false
    end
    return true
end
Names._CanHarvest = CanHarvest

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

local function AddKey(self, key)
    if self._set[key] then return end
    self._set[key] = true
    self._order[#self._order + 1] = key
    if #self._order > CAPACITY then
        local evict = table.remove(self._order, 1)
        self._set[evict] = nil
    end
end

--- Shared secret check -- also covers secret TABLES (canaccesstable /
--- issecrettable): restricted contexts can hand back a roster table that
--- throws on plain indexing.
local function IsSecret(v)
    local utils = YapperTable.Utils
    return utils and type(utils.IsSecret) == "function" and utils:IsSecret(v) == true
end

-- ---------------------------------------------------------------------------
-- Deferred sweeps
-- ---------------------------------------------------------------------------

-- A harvest attempted during combat or ANY restriction is deferred to
-- the first moment no safety gate is active at all. Restriction-end
-- dispatches can be swallowed by loading screens and non-chat
-- restrictions raise no regen event, so a slow retry chain is the
-- guarantee; event flushes below are only for promptness. The chain
-- exists only while a sweep is pending -- zero cost in normal play.
local SWEEP_RETRY_SECONDS = 2

local function ScheduleSweepRetry()
    if Names._retryScheduled then return end
    if not (C_Timer and type(C_Timer.After) == "function") then return end
    Names._retryScheduled = true
    C_Timer.After(SWEEP_RETRY_SECONDS, function()
        Names._retryScheduled = false
        if Names._pendingSweep then
            Names:SweepRoster()
        end
    end)
end

--- Store one raw name (character, battletag, or account display name).
--- Refuses silently on secrets, non-strings, and unsafe contexts --
--- Add() is the storage boundary, so the combat/restriction gate lives
--- here as well as at the harvest callers.
function Names:Add(raw)
    -- Gates run BEFORE any value operation: a secret string throws even
    -- on `== ""` comparisons in tainted execution, so the value is not
    -- touched until it has passed the safe predicates.
    if not CanHarvest() then
        -- Dropped this value, but queue a catch-up sweep so deferred
        -- harvesting resumes at the first fully-unrestricted moment.
        self._pendingSweep = true
        ScheduleSweepRetry()
        return
    end
    if IsSecret(raw) then return end
    if type(raw) ~= "string" or raw == "" then return end
    -- Size bound: real character names (< 32 bytes), Forever surnames,
    -- and BattleTags sit far under this; it caps stored-key size against
    -- garbage inputs.
    if #raw > 128 then return end
    -- Strip BattleTag discriminators ("Name#1234"); character names
    -- cannot contain '#'.
    if raw:find("#", 1, true) then
        raw = raw:gsub("#.*$", "")
        if raw == "" then return end
    end
    -- NormaliseCharName owns casing, "-Realm" suffixes, and Forever's
    -- Firstname-Lastname/Firstname Lastname forms -> "first last".
    local utils = YapperTable.Utils
    local norm = utils and utils.NormaliseCharName and utils:NormaliseCharName(raw)
    if type(norm) ~= "string" or norm == "" or #norm > 64 then return end
    -- Require at least one letter-ish byte (ASCII alpha or UTF-8
    -- lead/continuation byte >= 0x80, covering accented and non-Latin
    -- names): pure punctuation/digit junk can never be a name.
    if not norm:find("[%a\128-\255]") then return end
    AddKey(self, norm)
    -- Forever surnames normalise to "first last": index each part so
    -- either spelling is recognised as a known name.
    for part in string_gmatch(norm, "%S+") do
        AddKey(self, part)
    end
end

--- True when a token is a known player name (case-insensitive).
function Names:IsName(token)
    if IsSecret(token) then return false end
    if type(token) ~= "string" or token == "" then return false end
    return self._set[string_lower(token)] == true
end

--- First stored name extending `lowerPrefix` (FIFO order), or nil.
--- Used by autocomplete as a suggestion tier below learned vocabulary.
function Names:FindByPrefix(lowerPrefix)
    if IsSecret(lowerPrefix) then return nil end
    if type(lowerPrefix) ~= "string" or lowerPrefix == "" then return nil end
    local plen = #lowerPrefix
    for _, key in ipairs(self._order) do
        -- Plain-find prefix test: no per-candidate substring allocation
        -- on the per-keystroke autocomplete path.
        if #key > plen and key:find(lowerPrefix, 1, true) == 1 then
            return key
        end
    end
    return nil
end

function Names:Clear()
    self._set = {}
    self._order = {}
end

-- ---------------------------------------------------------------------------
-- Harvesting
-- ---------------------------------------------------------------------------

--- Enumerate roster-type sources: self, group members, WoW friends,
--- guild roster, and Battle.net friends. Deferred (not dropped) when a
--- sweep is requested during combat or restrictions.
function Names:SweepRoster()
    if not CanHarvest() then
        self._pendingSweep = true
        ScheduleSweepRetry()
        return
    end
    self._pendingSweep = false

    if type(UnitName) == "function" then
        self:Add(UnitName("player"))
        local n = (type(GetNumGroupMembers) == "function" and GetNumGroupMembers()) or 0
        local inRaid = type(IsInRaid) == "function" and IsInRaid()
        local prefix = inRaid and "raid" or "party"
        -- partyN covers members excluding the player; raidN includes them.
        for i = 1, (inRaid and n or n - 1) do
            self:Add(UnitName(prefix .. i))
        end
    end

    if C_FriendList and type(C_FriendList.GetNumFriends) == "function"
        and type(C_FriendList.GetFriendInfoByIndex) == "function" then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and type(info) == "table" and not IsSecret(info) then
                self:Add(info.name)
            end
        end
    end

    -- Guild roster. NOTE: C_GuildInfo.GuildRoster/GuildRoster is a
    -- REQUEST (returns nothing; server-side 10s throttle) -- the read API
    -- is the classic GetNumGuildMembers/GetGuildRosterInfo pair, whose
    -- name field is "Name-Realm" (handled by NormaliseCharName). Since
    -- 8.0 the guild is a club internally, so reads can hand back secret
    -- strings under restrictions: each result still passes through
    -- Add()'s IsSecret gate.
    if type(GetNumGuildMembers) == "function"
        and type(GetGuildRosterInfo) == "function" then
        local gn = GetNumGuildMembers() or 0
        for i = 1, gn do
            local ok, name = pcall(GetGuildRosterInfo, i)
            if ok then
                self:Add(name)
            end
        end
        if gn == 0 and type(IsInGuild) == "function" and IsInGuild() then
            -- Guilded but cache cold: request a refresh. The resulting
            -- GUILD_ROSTER_UPDATE re-sweeps once data lands; the 10s
            -- throttle keeps a still-empty cache from spamming requests.
            local requestRoster = (C_GuildInfo and C_GuildInfo.GuildRoster)
                or (type(GuildRoster) == "function" and GuildRoster)
            if type(requestRoster) == "function" then
                pcall(requestRoster)
            end
        end
    end

    if type(BNGetNumFriends) == "function" and C_BattleNet
        and type(C_BattleNet.GetFriendAccountInfo) == "function" then
        for i = 1, BNGetNumFriends() or 0 do
            local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if ok and type(info) == "table" and not IsSecret(info) then
                self:Add(info.accountName)
                self:Add(info.battleTag)
                local ga = info.gameAccountInfo
                if type(ga) == "table" and not IsSecret(ga) then
                    self:Add(ga.characterName)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

-- Chat events whose second payload arg is the sender's character name.
local SENDER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_CHANNEL",
}

--- Idempotent by construction: every registration is keyed handlerId
--- "Names", so re-calling Init after UnregisterAll() (disable/re-enable
--- via OverrideYapper) restores the handlers instead of duplicating
--- them. The trailing sweep is a cheap re-harvest.
function Names:Init()
    local events = YapperTable.Events
    if not (events and events.Register) then
        self:SweepRoster()
        return
    end

    -- Chat senders. Dropped (not deferred) while unsafe: the stream is
    -- constant, and roster sweeps pick up anyone missed.
    for _, ev in ipairs(SENDER_EVENTS) do
        events:Register("PARENT_FRAME", ev, function(_, sender)
            Names:Add(sender)
        end, "Names")
    end

    -- Roster-type refreshes trigger a guarded sweep. (No
    -- PLAYER_ENTERING_WORLD: the boot handler unregisters the whole event
    -- after first dispatch, which would kill this registration.)
    for _, ev in ipairs({
        "GROUP_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE",
        "BN_FRIEND_INFO_CHANGED",
    }) do
        events:Register("PARENT_FRAME", ev, function()
            Names:SweepRoster()
        end, "Names")
    end

    -- Leaving combat flushes a sweep deferred mid-fight.
    events:Register("PARENT_FRAME", "PLAYER_REGEN_ENABLED", function()
        if Names._pendingSweep then
            Names:SweepRoster()
        end
    end, "Names")

    -- Restriction transitions (12.x clients): purge on entry -- the
    -- buffer may hold data gathered from a context that has become
    -- untrusted -- and resweep once clear.
    if type(C_RestrictedActions) == "table"
        and type(C_RestrictedActions.IsAddOnRestrictionActive) == "function" then
        events:Register("PARENT_FRAME", "ADDON_RESTRICTION_STATE_CHANGED", function(_, state)
            local rstates = Enum and Enum.AddOnRestrictionState
            if rstates and state == rstates.Inactive then
                Names:SweepRoster()
            else
                -- Activating/Active (or an unrecognised state): purge.
                Names:Clear()
            end
        end, "Names")
    end

    self:SweepRoster()
end
