--[[
    Small utility belt: printing, string helpers.
]]

local YapperName, YapperTable = ...

local Utils = {}
YapperTable.Utils = Utils

local SENDER_PRESETS = {
    info    = "FFFFAA00",
    warn    = "FFFF4444",
    success = "FF00FF00",
    white   = "FFFFFFFF",
}

function Utils:Print(...)
    local args = { ... }

    -- Optional preset as first arg: Utils:Print("info", "message...")
    local prefix = YapperName .. ": "
    if type(args[1]) == "string" and SENDER_PRESETS[args[1]] then
        local preset = table.remove(args, 1)
        prefix = ("|c%s%s:|r "):format(SENDER_PRESETS[preset], YapperName)
    end

    for i = 1, #args do args[i] = self:SafeToString(args[i]) end
    print(prefix .. table.concat(args, " "))
end

--- Convert a value for diagnostics without attempting to stringify a secret.
--- @param value any
--- @return string
function Utils:SafeToString(value)
    if value == nil then return "nil" end
    if self:IsSecret(value) then return "<secret>" end
    local ok, result = pcall(tostring, value)
    return ok and result or "<unavailable>"
end

function Utils:VerbosePrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.VERBOSE then
        self:Print(...)
    end
end

function Utils:DebugPrint(...)
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Print("DEBUG:", ...)
    end
end

--- Return the correct parent frame for chat-related UI.
--- During housing-editor (or any fullscreen panel) this is the panel
--- frame; otherwise plain UIParent.
function Utils:GetChatParent()
    if FCF_GetCurrentFullScreenFrame then
        return FCF_GetCurrentFullScreenFrame() or UIParent
    end
    return UIParent
end

--- Ensure frame stays parented to the active fullscreen panel
--- (housing editor, fullscreen dialogs, etc.).
--- Hooks FCF_SetFullScreenFrame/ClearFullScreenFrame and updates on
--- OnShow so the frame is repointed whenever the panel switches.
--- Frames that already set their parent can use this merely as a fallback.
function Utils:MakeFullscreenAware(frame)
    if not frame then return end
    local function update()
        if not frame or not frame:IsShown() then return end
        local target = self:GetChatParent()
        if frame:GetParent() == target then return end
        if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
            FrameUtil.SetParentMaintainRenderLayering(frame, target)
        else
            frame:SetParent(target)
        end
        -- If the frame carries a reposition callback, let it recompute
        -- its absolute coordinates for the new parent.
        if frame._yapperReposition then
            pcall(frame._yapperReposition)
        end
    end
    if FCF_SetFullScreenFrame then
        hooksecurefunc("FCF_SetFullScreenFrame", update)
    end
    if FCF_ClearFullScreenFrame then
        hooksecurefunc("FCF_ClearFullScreenFrame", update)
    end
    frame:HookScript("OnShow", update)
    return update
end


-- Return true if chat is currently under a real lockdown condition.
function Utils:IsChatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsChatLockdown) == "function" then
        return policy:IsChatLockdown() == true
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        return C_ChatInfo.InChatMessagingLockdown() == true
    end
    return false
end

-- Return true when protected-frame combat restrictions are active.
function Utils:IsCombatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsCombatLockdown) == "function" then
        return policy:IsCombatLockdown() == true
    end
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    return false
end

--- Return true while any addon restriction type (combat, encounter, M+,
--- PvP match, restricted map, chat) is being enforced. Distinct from
--- IsChatLockdown: non-chat restrictions leave chat messaging usable but
--- make Blizzard-produced data (unit names, etc.) secret to tainted code,
--- so calls forwarded into Blizzard handlers can hit illegal secret
--- comparisons. Always false on clients without C_RestrictedActions.
--- @return boolean
function Utils:IsAnyAddOnRestriction()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsAnyAddOnRestrictionActive) == "function" then
        return policy:IsAnyAddOnRestrictionActive() == true
    end
    return false
end

-- Return true when either chat-messaging or combat lockdown is active.
-- Useful for paths that manipulate secure/protected attributes.
function Utils:IsChatOrCombatLockdown()
    local policy = YapperTable and YapperTable.LockdownPolicy
    if policy and type(policy.IsChatOrCombatLockdown) == "function" then
        return policy:IsChatOrCombatLockdown() == true
    end
    return self:IsChatLockdown() or self:IsCombatLockdown()
end

-- Expose globally: other addons and compat patches may use this.
_G.YAPPER_UTILS = Utils

-- ---------------------------------------------------------------------------
-- Boilerplate helpers
-- ---------------------------------------------------------------------------

--- @param t any
--- @return table
function Utils:EnsureTable(t)
    return type(t) == "table" and t or {}
end

--- Ensure a table path exists, creating intermediate tables as needed.
--- @param root table  The root table to traverse
--- @param ... string  Path segments (e.g., "EditBox", "ChannelTextColors")
--- @return table  The deepest table in the path
function Utils:EnsureTablePath(root, ...)
    local current = self:EnsureTable(root)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if type(key) ~= "string" and type(key) ~= "number" then return current end
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    return current
end

--- @param expectedType string  e.g. "string", "table"
--- @param default any  Returned when the type doesn't match
--- @return any
function Utils:AssertType(value, expectedType, default)
    return type(value) == expectedType and value or default
end

-- Return true if the supplied value is secret (obfuscated) and should be
-- treated with caution. Prefer the built-in WoW API when available.
function Utils:IsSecret(value)
    if value == nil then return true end
    if type(value) == "boolean" and value == false then return true end

    if type(value) == "table" then
        if type(canaccesstable) == "function" then
            local ok, accessible = pcall(canaccesstable, value)
            if ok and accessible == false then
                return true
            end
        end

        if type(issecrettable) == "function" then
            local ok, secretTable = pcall(issecrettable, value)
            if ok and secretTable == true then
                return true
            end
        end
    end

    if type(issecretvalue) == "function" then
        local ok, res = pcall(issecretvalue, value)
        if ok and res == true then
            if type(canaccessvalue) == "function" then
                local ok2, access = pcall(canaccessvalue, value)
                if ok2 and access == true then
                    return false
                end
            end
            return true
        end
    end
    -- Fallback heuristic: battle.net obfuscated tokens include "|K".
    if type(value) == "string" then
        local okMask, hasMask = pcall(function()
            return value:find("|K", 1, true) ~= nil
        end)
        if okMask and hasMask then return true end

        local okEmpty, isEmpty = pcall(function()
            return value:match("^%s*$") ~= nil
        end)
        if okEmpty and isEmpty then return true end
    end
    return false
end

--- Return a chat target only when it is usable from tainted code.
--- Secret values (and empty/blank strings, via IsSecret's heuristics) are
--- returned as nil so callers can treat them as "no target" instead of
--- performing comparisons or string operations that error on secrets.
function Utils:SanitizeTarget(value)
    if value == nil then return nil end
    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" then
        return nil
    end
    if self:IsSecret(value) then return nil end
    return value
end

--- Return a number only when it is usable from tainted code.
--- Secret numbers (which pass through `or 0` and then fail inside Blizzard
--- arithmetic) are returned as nil so callers can fall back to a safe
--- default. Non-numbers and nil also return nil.
--- @param value any
--- @return number|nil
function Utils:SanitizeNumber(value)
    if value == nil then return nil end
    if type(value) ~= "number" then return nil end
    if self:IsSecret(value) then return nil end
    return value
end

--- SanitizeNumber with a fallback for nil/secret/non-numeric input.
--- @param value any
--- @param fallback number
--- @return number
function Utils:SafeNumber(value, fallback)
    return self:SanitizeNumber(value) or fallback
end

-- ---------------------------------------------------------------------------
-- Client flavour / feature detection
-- ---------------------------------------------------------------------------

-- Strings identifying the WoW: Forever client. The internal flavour label
-- may still change (currently "Camelot"), so the API probes in
-- IsForeverClient are the primary signal; these cover runtime strings.
local FOREVER_LABEL_PATTERNS = {
    "camelot",
    "forever",
    "classicplus",
    "classic_plus",
    "classic plus",
    "classic%+",
}

local function MatchesForeverLabel(value)
    if type(value) ~= "string" then return false end
    local s = value:lower()
    for _, pattern in ipairs(FOREVER_LABEL_PATTERNS) do
        if s:find(pattern) then return true end
    end
    return false
end

--- True when running on the World of Warcraft: Forever client. Detection is
--- rename-proof: Forever-only API surfaces are probed first, then runtime
--- flavour/product labels (camelot/forever/classicplus variants), then a weak
--- build-version heuristic (Forever reports 1.6x while retail is on 12.x+).
--- @return boolean
function Utils:IsForeverClient()
    if self._isForeverClient ~= nil then return self._isForeverClient end

    local detected = false

    -- Forever-only API surfaces.
    if type(C_GameRules) == "table" then
        if type(C_GameRules.GetForeverExperiencePreset) == "function"
            or type(C_GameRules.SetForeverExperiencePreset) == "function" then
            detected = true
        elseif type(C_GameRules.GetGameModeGlueScreenName) == "function" then
            local ok, screenName = pcall(C_GameRules.GetGameModeGlueScreenName)
            if ok and MatchesForeverLabel(screenName) then detected = true end
        end
    end
    if not detected and type(Enum) == "table"
        and type(Enum.ForeverExperiencePreset) == "table" then
        detected = true
    end
    if not detected and type(C_NameUtil) == "table"
        and type(C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator) == "function" then
        detected = true
    end
    if not detected and type(C_CharacterCreation) == "table"
        and type(C_CharacterCreation.AreRegionalUniqueNamesEnabled) == "function" then
        detected = true
    end
    if not detected and type(C_PlayerInfo) == "table"
        and type(C_PlayerInfo.ShouldDisplaySurname) == "function" then
        detected = true
    end

    -- Weak build heuristic: Forever reports interface 1.6x while retail is
    -- 12.x+. Callers should still gate on the specific APIs above.
    if not detected and type(GetBuildInfo) == "function" then
        local ok, version = pcall(GetBuildInfo)
        if ok and type(version) == "string" and version:match("^1%.6%d") then
            detected = true
        end
    end

    self._isForeverClient = detected
    return detected
end

--- True when the ruleset has regional-unique (surname-bearing) player names
--- enabled; Blizzard's own gate inside its chat editbox.
--- Deliberately independent of IsForeverClient(): if the naming scheme ever
--- ships on mainline, Yapper's behaviour follows automatically.
--- @return boolean
function Utils:HasRegionalUniqueNames()
    if type(RegionalUniqueNamesEnabled) ~= "function" then return false end
    local ok, enabled = pcall(RegionalUniqueNamesEnabled)
    return ok and enabled == true
end

-- ---------------------------------------------------------------------------
-- Name normalisation helpers
-- ---------------------------------------------------------------------------

--- Strip the realm suffix from a character name and lowercase it.
--- e.g. "Arthas-Frostmourne" -> "arthas"
--- On clients where RegionalUniqueNamesEnabled() is true (WoW: Forever) the
--- "-" is a *surname* separator, not a realm suffix, and the same player also
--- appears as "Charname Surname" -- first names are not unique there, so
--- nothing is stripped; both spellings are canonicalised to lowercase with a
--- single space between parts.
--- @param name any
--- @return string|nil
function Utils:NormaliseCharName(name)
    if name == nil or self:IsSecret(name) then return nil end
    local ok, s = pcall(tostring, name)
    if not ok or s == "" then return nil end
    if self.HasRegionalUniqueNames and self:HasRegionalUniqueNames() then
        s = s:gsub("%-", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
        return s:lower()
    end
    return s:gsub("%-.*$", ""):lower()
end

-- ---------------------------------------------------------------------------
-- Escape-sequence helpers
-- ---------------------------------------------------------------------------

--- Strip display-only WoW escape sequences from text: colour opens/resets,
--- texture escapes, and atlas markers. Hyperlinks (|H...|h...|h) are preserved,
--- including the quality-colour wrapper required by item and custom links.
--- Used to canonicalise editbox text (spellcheck recolouring injects colour
--- escapes into the widget) and to sanitise outgoing chat text.
--- @param text any
--- @return string
function Utils:StripDisplayEscapes(text)
    if type(text) ~= "string" then return "" end
    if text == "" or not text:find("|", 1, true) then return text end

    -- Item and custom hyperlinks require their quality-colour wrapper to be
    -- sent together with the |H...|h...|h payload.  Removing that wrapper
    -- produces an invalid chat escape, even though the hyperlink body looks
    -- intact.  Keep complete links (including a directly preceding colour
    -- open and following reset) while removing display-only escapes elsewhere.
    local lower = text:lower()
    local out = {}
    local pos = 1
    local length = #text

    local function hyperlinkEnd(startPos)
        local first = lower:find("|h", startPos + 2, true)
        if not first then return nil end
        local second = lower:find("|h", first + 2, true)
        return second and second + 1 or first + 1
    end

    local function appendHyperlink(startPos, endPos, withColour)
        local after = endPos + 1
        if withColour and lower:sub(after, after + 1) == "|r" then
            endPos = after + 1
        end
        out[#out + 1] = text:sub(startPos, endPos)
        return endPos + 1
    end

    while pos <= length do
        local isPipe = lower:sub(pos, pos) == "|"
        local char2 = lower:sub(pos + 1, pos + 1)
        local consumed = false

        -- Preserve the standard |cAARRGGBB|H...|h...|h|r form.  Named
        -- colours are handled as well for modern/custom link producers.
        if isPipe and char2 == "c" then
            local colourEnd
            if lower:sub(pos + 2, pos + 2) == "n" then
                local colon = text:find(":", pos + 3, true)
                colourEnd = colon
            elseif text:sub(pos + 2, pos + 9):match("^%x%x%x%x%x%x%x%x$") then
                colourEnd = pos + 9
            end

            if colourEnd and lower:sub(colourEnd + 1, colourEnd + 2) == "|h" then
                local linkEnd = hyperlinkEnd(colourEnd + 1)
                if linkEnd then
                    pos = appendHyperlink(pos, linkEnd, true)
                    consumed = true
                end
            end

            -- This is a display-only colour open, not a hyperlink wrapper.
            if not consumed and colourEnd then
                pos = colourEnd + 1
                consumed = true
            end
        end

        if not consumed and isPipe and char2 == "h" then
            -- Preserve an already-unwrapped/custom hyperlink body.  The
            -- following |r, if any, is still display-only and is stripped by
            -- the normal reset branch below.
            local linkEnd = hyperlinkEnd(pos)
            if linkEnd then
                pos = appendHyperlink(pos, linkEnd, false)
                consumed = true
            end
        end

        if not consumed and isPipe and char2 == "r" then
            pos = pos + 2
            consumed = true
        end

        if not consumed and isPipe and char2 == "t" then
            local close = lower:find("|t", pos + 2, true)
            if close then
                pos = close + 2
                consumed = true
            end
        end

        if not consumed and isPipe and char2 == "a" then
            local close = lower:find("|a", pos + 2, true)
            if close then
                pos = close + 2
                consumed = true
            end
        end

        if not consumed then
            out[#out + 1] = text:sub(pos, pos)
            pos = pos + 1
        end
    end

    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------

--- SetFont only when the target font differs from the current one.
--- SetFont invalidates the FontString/EditBox layout even when the values are
--- identical, so guarding it keeps hot paths (overlay open) cheap.
--- @param widget table  Any widget with GetFont/SetFont (FontString, EditBox)
--- @param face string
--- @param size number
--- @param flags string|nil
--- @return boolean changed  True if SetFont was actually called.
function Utils:SetFontIfChanged(widget, face, size, flags)
    if not (widget and widget.GetFont and widget.SetFont) then return false end
    if not (face and size) then return false end
    flags = flags or ""

    if self:IsSecret(face) or self:IsSecret(size)
        or (flags ~= "" and self:IsSecret(flags)) then
        return false
    end

    local ok, curFace, curSize, curFlags = pcall(widget.GetFont, widget)
    if not ok then return false end

    if curFace and self:IsSecret(curFace) then
        widget:SetFont(face, size, flags)
        return true
    end
    if curSize and self:IsSecret(curSize) then
        widget:SetFont(face, size, flags)
        return true
    end
    if curFlags and curFlags ~= "" and self:IsSecret(curFlags) then
        widget:SetFont(face, size, flags)
        return true
    end

    if curFace == face and curSize == size and (curFlags or "") == flags then
        return false
    end
    widget:SetFont(face, size, flags)
    return true
end

-- ---------------------------------------------------------------------------
-- BNet helpers
-- ---------------------------------------------------------------------------

--- Returns true when target is unambiguously a Battle.net identifier
--- (numeric presence/account ID or contains a BattleTag '#').
--- @param target any
--- @return boolean
function Utils:IsUnambiguousBnetTarget(target)
    if not target or self:IsSecret(target) then return false end
    local ok, text = pcall(tostring, target)
    if not ok or text == "" then return false end
    return tonumber(text) ~= nil or text:find("#", 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- String helpers
-- ---------------------------------------------------------------------------

--- Convert leetspeak characters back to their base alphabet equivalents.
--- Used to ensure blocked words can't be bypassed with common substitutions.
--- @param word string
--- @return string
function Utils.Deleet(word)
    -- a=4, e=3, i=1/!, o=0, s=5/$, t=7/+
    word = word:gsub("0", "o")
    word = word:gsub("1", "i")
    word = word:gsub("3", "e")
    word = word:gsub("4", "a")
    word = word:gsub("5", "s")
    word = word:gsub("7", "t")
    word = word:gsub("%$", "s")
    word = word:gsub("!", "i")
    word = word:gsub("%+", "t")
    return word
end
