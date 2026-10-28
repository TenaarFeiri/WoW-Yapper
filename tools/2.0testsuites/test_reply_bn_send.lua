#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_reply_bn_send.lua — BN whisper reply send-path regression tests
-- Run from the repo root:  lua tools/2.0testsuites/test_reply_bn_send.lua
--
-- Regression: a bnet whisper typed in the overlay after opening a reply
-- tell with the reply keybind did nothing on Enter. Blizzard's remembered
-- BN tell target is a "|K" presence token (or a secret value under addon
-- restrictions); ResolveWhisperTarget preferred it over the usable
-- ReplyQueue-sourced target, so the token either failed Router's
-- friend-list scan (didSend=false -> silent no-op, box stays open) or
-- errored the handler outright on a secret boolean test. The send path
-- now resolves the remembered BN target through BNet_GetBNetIDAccount —
-- the same C call Blizzard's own SendText uses — and never boolean-tests
-- the remembered value before checking its plain-string type tag.
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock (same shape as test_whisper_tab_target.lua)
-- ===========================================================================

_G.date = os.date
_G.GetTime = function() return 100 end
_G.UnitGUID = function() return "Player-1-AABBCCDD" end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.IsInGuild = function() return false end
_G.IsInInstance = function() return false end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.LE_PARTY_CATEGORY_INSTANCE = 2

_G.InCombatLockdown = function() return false end
_G.IsShiftKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.C_ChatInfo = { InChatMessagingLockdown = function() return false end }

-- A sentinel standing in for a genuine secret value: IsSecret's issecretvalue
-- path flags it, and nothing may compare/boolean-test it safely.
local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end
_G.canaccessvalue = function(value) return value ~= SECRET end
_G.issecrettable = function(value) return value == SECRET end
_G.canaccesstable = function(value) return value ~= SECRET end

-- Mutable Blizzard remembered-tell stores.
local tell = { target = nil, ctype = nil, err = nil }
local told = { target = nil, ctype = nil, err = nil }
local setLastToldCalls = 0

_G.ChatFrameUtil = {
    GetLastTellTarget = function()
        if tell.err then error(tell.err) end
        return tell.target, tell.ctype
    end,
    GetLastToldTarget = function()
        if told.err then error(told.err) end
        return told.target, told.ctype
    end,
    SetLastToldTarget = function() setLastToldCalls = setLastToldCalls + 1 end,
    SetChatFocusOverride = function() end,
    ClearChatFocusOverride = function() end,
    DeactivateChat = function() end,
    OpenChat = function() end,
}

-- The C API consumes |K tokens/secrets Lua can't read and returns the ID.
_G.BNet_GetBNetIDAccount = function(token)
    if token == "|Kf42|k" then return 42 end
    if token == "|Kf99|k" then return 99 end
    return nil
end

local sentWhispers = {}
_G.C_BattleNet = {
    GetAccountInfoByID = function(id)
        if id == 42 then return { accountName = "Carol" } end
        return nil
    end,
    SendWhisper = function(id, msg)
        sentWhispers[#sentWhispers + 1] = { id = id, msg = msg }
        return true
    end,
}

_G.C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}

-- ===========================================================================
-- Build YapperTable and load the real modules
-- ===========================================================================

local YapperTable = {}

YapperTable.Config = { System = { DEBUG = false }, EditBox = {} }
YapperTable.Core = { GetCharacterLanguage = function(_, v) return v end }
YapperTable.Error = {
    Throw = function(_, key) error(key) end,
    PrintError = function() end,
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end
YapperTable.Utils.DebugPrint = function() end
YapperTable.Utils.VerbosePrint = function() end

loadModule("Src/EditBox.lua")
loadModule("Src/Router.lua")

-- Handlers.lua captures EditBox._ResolveChannelName (normally provided by
-- Overlay.lua) as an upvalue at load time; stub it before loading.
YapperTable.EditBox._ResolveChannelName = function(n)
    return "Channel" .. tostring(n)
end
loadModule("Src/EditBox/Handlers.lua")

local EditBox = YapperTable.EditBox
local Router = YapperTable.Router

-- ===========================================================================
-- 1. ResolveWhisperTarget — BN_WHISPER remembered targets
-- ===========================================================================
print("\nTest 1: ResolveWhisperTarget — BN_WHISPER")

tell.target, tell.ctype = "|Kf42|k", "BN_WHISPER"
local target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("|K remembered target resolves to account ID",
    target == 42 and secure == true)

tell.ctype = "WHISPER"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("remembered type mismatch keeps the fallback",
    target == "Carol" and secure == false)

tell.ctype = "BN_WHISPER"
tell.err = "attempt to compare secret value"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("erroring remembered list keeps the fallback",
    target == "Carol" and secure == false)
tell.err = nil
tell.target = "|Kf42|k"

local realResolve = _G.BNet_GetBNetIDAccount
_G.BNet_GetBNetIDAccount = function() return nil end
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("unresolvable token falls back to Yapper target",
    target == "Carol" and secure == false)
_G.BNet_GetBNetIDAccount = realResolve

told.target, told.ctype = "|Kf99|k", "BN_WHISPER"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "told", 99)
check("told source resolves remembered token",
    target == 99 and secure == true)

-- ===========================================================================
-- 2. ResolveWhisperTarget — WHISPER remembered targets
-- ===========================================================================
print("\nTest 2: ResolveWhisperTarget — WHISPER")

tell.target, tell.ctype = "Alice", "WHISPER"
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("newer remembered sender does not reroute the compose target",
target == "Bob" and secure == false)

target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Alice")
check("matching remembered sender stays Blizzard-sourced",
    target == "Alice" and secure == true)

target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", nil)
check("nil compose target still takes the remembered sender",
    target == "Alice" and secure == true)

tell.target, tell.ctype = "Alice-RealmA", "WHISPER"
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Alice-RealmB")
check("differently qualified realm names are never collapsed",
    target == "Alice-RealmB" and secure == false)

target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Alice-RealmA")
check("same qualified name stays Blizzard-sourced",
    target == "Alice-RealmA" and secure == true)

tell.target, tell.ctype = "Alice", "WHISPER"

tell.target = SECRET
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("secret remembered target falls back without erroring",
    target == "Bob" and secure == false)

tell.target, tell.ctype = nil, nil
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("empty remembered list keeps the fallback",
    target == "Bob" and secure == false)

-- ===========================================================================
-- 3. Reply-target readers — BN |K/secret recovery
-- ===========================================================================
print("\nTest 3: reply-target readers recover BN |K entries")

EditBox.ReplyQueue = {}
tell.target, tell.ctype = "|Kf42|k", "BN_WHISPER"
local ctype, tgt = EditBox.GetLastTellTargetInfo()
check("|K tell entry recovers the account name",
    ctype == "BN_WHISPER" and tgt == "Carol")

tell.target = "|Kf99|k"
ctype, tgt = EditBox.GetLastTellTargetInfo()
check("|K tell entry without a name falls back to the ID",
    ctype == "BN_WHISPER" and tgt == 99)

ctype, tgt = EditBox.GetLastToldTargetInfo()
check("|K told entry recovers the account ID",
    ctype == "BN_WHISPER" and tgt == 99)

tell.target, tell.ctype = SECRET, "WHISPER"
ctype, tgt = EditBox.GetLastTellTargetInfo()
check("secret WHISPER entry still yields no target",
    ctype == nil and tgt == nil)

-- ===========================================================================
-- 4. Router:Send — BN_WHISPER token and numeric targets
-- ===========================================================================
print("\nTest 4: Router:Send — BN_WHISPER targets")

sentWhispers = {}
local okSend = Router:Send("hello", "BN_WHISPER", nil, "|Kf42|k")
check("|K token sends via C_BattleNet.SendWhisper",
    okSend == true and sentWhispers[1] and sentWhispers[1].id == 42)

sentWhispers = {}
okSend = Router:Send("hello", "BN_WHISPER", nil, 42)
check("numeric account ID still sends",
    okSend == true and sentWhispers[1] and sentWhispers[1].id == 42)

sentWhispers = {}
okSend = Router:Send("hello", "BN_WHISPER", nil, "|Kfunresolvable|k")
check("unresolvable target still fails closed",
    okSend == false and #sentWhispers == 0)

-- ===========================================================================
-- 5. Overlay handlers — stale _secureReplySource must not survive typed
--    target/channel selection (exercises the REAL OnTextChanged and
--    OnEnterPressed closures installed by EditBox:SetupOverlayScripts;
--    only the WoW widget surface is stubbed, no dispatch reimplemented)
-- ===========================================================================
print("\nTest 5: overlay handlers clear stale _secureReplySource")

-- Minimal widget mock: SetScript/GetScript/HookScript/RegisterEvent plus
-- text/cursor accessors. Programmatic SetText fires OnTextChanged with
-- isUserInput=false, matching WoW.
local function NewWidget()
    local w = { _scripts = {}, _hooks = {}, _events = {}, _text = "" }
    function w:SetScript(name, fn) self._scripts[name] = fn end
    function w:GetScript(name) return self._scripts[name] end
    function w:HookScript(name, fn)
        self._hooks[name] = self._hooks[name] or {}
        self._hooks[name][#self._hooks[name] + 1] = fn
    end
    function w:RegisterEvent(ev) self._events[#self._events + 1] = ev end
    function w:IsShown() return true end
    function w:SetText(v)
        self._text = v or ""
        local h = self._scripts.OnTextChanged
        if h then h(self, false) end
    end
    function w:SetTextRaw(v) self._text = v or "" end
    function w:GetText() return self._text end
    function w:SetCursorPosition() end
    function w:SetFocus() end
    function w:HasFocus() return false end
    function w:GetName() return "MockWidget" end
    function w:AddHistoryLine() end
    return w
end

local overlayEdit = NewWidget()
local overlay = NewWidget()
_G.UIParent = NewWidget()
local origEditBox = NewWidget()
_G.DEFAULT_CHAT_FRAME = { editBox = origEditBox }
_G.ChatFrame1EditBox = origEditBox

YapperTable.Recolour = {
    CanonicalText = function(box) return box:GetText() end,
}

EditBox.RegisterFocusHandler = function() end
EditBox.Hide = function() end
EditBox.PersistLastUsed = function() end
local lastLabel = nil
EditBox.RefreshLabel = function(self)
    lastLabel = { chatType = self.ChatType, target = self.Target }
end

local sends = {}
EditBox:SetOnSend(function(text, chatType, lang, target)
    sends[#sends + 1] = { text = text, chatType = chatType, target = target }
    return true
end)

EditBox.OverlayEdit = overlayEdit
EditBox.Overlay = overlay
EditBox.OrigEditBox = origEditBox
EditBox:SetupOverlayScripts()

local onTextChanged = overlayEdit._scripts.OnTextChanged
local onEnterPressed = overlayEdit._scripts.OnEnterPressed
check("SetupOverlayScripts installs OnTextChanged",
    type(onTextChanged) == "function")
check("SetupOverlayScripts installs OnEnterPressed",
    type(onEnterPressed) == "function")

local function resetCompose(init)
    sends = {}
    setLastToldCalls = 0
    EditBox.ReplyQueue = {}
    EditBox.ChatType = init.chatType
    EditBox.Target = init.target
    EditBox.ChannelName = nil
    EditBox.Language = nil
    EditBox._secureReplySource = init.source
    overlayEdit:SetTextRaw("")
    lastLabel = nil
end

-- Simulate user typing: raw text update followed by the user-input edge.
local function typeText(t)
    overlayEdit:SetTextRaw(t)
    onTextChanged(overlayEdit, true)
end

-- Blizzard stores: last incoming tell Alice, last outgoing told Carol.
tell.target, tell.ctype = "Alice", "WHISPER"
told.target, told.ctype = "Carol", "WHISPER"

-- Reply-opened overlay (source='tell'), then user types '/w Bob hello':
-- the typed target is authoritative; the stale marker is cleared.
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
typeText("/w Bob hello")
check("typed /w label shows the typed target", lastLabel.target == "Bob")
check("typed /w clears _secureReplySource", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("typed /w after tell-reply-open sends typed target",
    sends[1] and sends[1].target == "Bob")
check("typed /w after tell-reply-open never calls remembered-told writer",
    setLastToldCalls == 0)

-- Same with source='told'.
resetCompose({ chatType = "WHISPER", target = "Alice", source = "told" })
typeText("/w Bob hello")
check("typed /w clears stale told marker", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("typed /w after told-reply-open sends typed target",
    sends[1] and sends[1].target == "Bob")
check("typed /w after told-reply-open never calls remembered-told writer",
    setLastToldCalls == 0)

-- Stale 'told' then typed '/r hello': OnTextChanged expands to the
-- remembered tell target (Alice) and clears the marker.
resetCompose({ chatType = "WHISPER", target = "Alice", source = "told" })
typeText("/r hello")
check("typed /r label shows remembered tell target", lastLabel.target == "Alice")
check("typed /r clears stale told marker", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("typed /r sends the remembered tell target",
    sends[1] and sends[1].target == "Alice")
check("typed /r never calls remembered-told writer", setLastToldCalls == 0)

-- Stale 'tell' then typed '/r2 hello': expands to lastTold (Carol).
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
typeText("/r2 hello")
check("typed /r2 label shows remembered told target", lastLabel.target == "Carol")
check("typed /r2 clears stale tell marker", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("typed /r2 sends the remembered told target",
    sends[1] and sends[1].target == "Carol")
check("typed /r2 never calls remembered-told writer", setLastToldCalls == 0)

-- Explicit channel selections clear the marker too.
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
typeText("/2 hello")
check("bare numeric channel clears _secureReplySource",
    EditBox._secureReplySource == nil)
check("bare numeric channel commits CHANNEL target",
    lastLabel.chatType == "CHANNEL" and lastLabel.target == "2")
onEnterPressed(overlayEdit)
check("numeric channel send proceeds",
    sends[1] and sends[1].chatType == "CHANNEL" and sends[1].target == "2")
check("numeric channel never calls writer", setLastToldCalls == 0)

resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
typeText("/c 2 hello")
check("typed /c clears _secureReplySource", EditBox._secureReplySource == nil)
check("typed /c commits CHANNEL target",
    lastLabel.chatType == "CHANNEL" and lastLabel.target == "2")
onEnterPressed(overlayEdit)
check("typed /c send proceeds",
    sends[1] and sends[1].chatType == "CHANNEL" and sends[1].target == "2")
check("typed /c never calls writer", setLastToldCalls == 0)

-- Prefilled '/r hello' (no OnTextChanged dispatch): first Enter resolves
-- and returns without sending; second Enter sends the expanded target.
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
overlayEdit:SetText("/r hello")
onEnterPressed(overlayEdit)
check("Enter on prefilled /r resolves without sending",
    #sends == 0 and EditBox.Target == "Alice")
check("Enter /r leaves marker cleared", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("second Enter sends the resolved tell target",
    sends[1] and sends[1].target == "Alice")
check("Enter-only /r never calls writer", setLastToldCalls == 0)

resetCompose({ chatType = "WHISPER", target = "Alice", source = "told" })
overlayEdit:SetText("/r2 hello")
onEnterPressed(overlayEdit)
check("Enter on prefilled /r2 resolves without sending",
    #sends == 0 and EditBox.Target == "Carol")
check("Enter /r2 leaves marker cleared", EditBox._secureReplySource == nil)
onEnterPressed(overlayEdit)
check("second Enter sends the resolved told target",
    sends[1] and sends[1].target == "Carol")
check("Enter-only /r2 never calls writer", setLastToldCalls == 0)

-- Reply-open compose: user aimed at Alice but a newer whisper from Bob
-- arrived; the newer remembered sender must not reroute the send.
tell.target, tell.ctype = "Bob", "WHISPER"
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
overlayEdit:SetTextRaw("hello")
onEnterPressed(overlayEdit)
check("newer remembered sender does not reroute the send",
    sends[1] and sends[1].target == "Alice")
check("reroute refusal never calls writer", setLastToldCalls == 0)

-- When the remembered sender still matches the compose target the
-- Blizzard-sourced value may take the existing writer path.
tell.target, tell.ctype = "Alice", "WHISPER"
resetCompose({ chatType = "WHISPER", target = "Alice", source = "tell" })
overlayEdit:SetTextRaw("hello")
onEnterPressed(overlayEdit)
check("matching remembered sender still sends the compose target",
    sends[1] and sends[1].target == "Alice")
check("matching remembered sender still uses the native writer once",
    setLastToldCalls == 1)

-- Stable baseline: clean source, typed '/w Bob hello'.
tell.target, tell.ctype = "Alice", "WHISPER"
resetCompose({ chatType = "WHISPER", target = "Alice", source = nil })
typeText("/w Bob hello")
onEnterPressed(overlayEdit)
check("clean-source /w sends typed target",
    sends[1] and sends[1].target == "Bob")
check("clean-source /w never calls writer", setLastToldCalls == 0)

-- ===========================================================================
-- Summary
-- ===========================================================================
print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
