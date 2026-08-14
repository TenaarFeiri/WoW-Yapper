-- Contract-test runtime for Yapper's real chat pipeline.
-- Lua 5.1-compatible and deliberately deterministic: no wall-clock sleeps,
-- network access, or server behaviour is implied by the fake server.

local Harness = {}

local function load_module(path, name, tableValue)
    local loader, err = loadfile(path)
    assert(loader, err)
    loader(name, tableValue)
end

local function frame_factory()
    local frame = {
        shown = false,
        scripts = {},
        parent = nil,
        text = "",
    }

    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetParent() return self.parent or _G.UIParent end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:GetNumPoints() return 0 end
    function frame:SetSize() end
    function frame:SetWidth() end
    function frame:SetHeight() end
    function frame:GetWidth() return 400 end
    function frame:GetHeight() return 36 end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetAlpha() end
    function frame:SetText(text) self.text = text or "" end
    function frame:GetText() return self.text end
    function frame:SetTextColor() end
    function frame:SetJustifyH() end
    function frame:SetWordWrap() end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:HookScript(event, callback)
        local previous = self.scripts[event]
        if previous then
            self.scripts[event] = function(...)
                previous(...)
                callback(...)
            end
        else
            self.scripts[event] = callback
        end
    end
    function frame:CreateFontString()
        return frame_factory()
    end
    function frame:SetPropagateKeyboardInput() end
    function frame:EnableKeyboard() end
    function frame:SetClampedToScreen() end
    function frame:SetMultiLine() end
    function frame:SetAutoFocus() end
    function frame:SetFontObject() end
    function frame:SetTextInsets() end
    function frame:SetScrollChild() end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:HasFocus() return self.focused == true end
    function frame:SetCursorPosition(position) self.cursor = position end
    function frame:GetCursorPosition() return self.cursor or 0 end
    function frame:Insert(value)
        local cursor = self.cursor or #self.text
        self.text = self.text:sub(1, cursor) .. value .. self.text:sub(cursor + 1)
        self.cursor = cursor + #value
    end
    function frame:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "" end
    function frame:SetFont() end
    function frame:GetStringHeight() return 14 end
    function frame:GetVerticalScroll() return 0 end
    function frame:GetVerticalScrollRange() return 0 end
    function frame:SetVerticalScroll() end
    function frame:RegisterEvent() end

    return frame
end

local function install_globals(harness)
    _G.GetTime = function() return harness.now end
    _G.date = os.date
    _G.UnitGUID = function() return harness.playerGUID end
    _G.IsInInstance = function() return harness.inInstance, harness.instanceType end
    _G.IsInGroup = function() return harness.inGroup end
    _G.IsInRaid = function() return harness.inRaid end
    _G.IsInGuild = function() return harness.inGuild end
    _G.wipe = function(tableValue)
        for key in pairs(tableValue) do tableValue[key] = nil end
        return tableValue
    end
    _G.LE_PARTY_CATEGORY_HOME = 1
    _G.LE_PARTY_CATEGORY_INSTANCE = 2
    _G.UIParent = frame_factory()
    _G.UIParent:Show()
    _G.ChatFrame1EditBox = frame_factory()
    _G.DEFAULT_CHAT_FRAME = { editBox = _G.ChatFrame1EditBox, AddMessage = function() end }
    _G.NUM_CHAT_WINDOWS = 1
    _G.ChatTypeInfo = {}
    _G.ChatFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end }
    _G.SlashCmdList = {}
    _G.C_AddOns = nil
    _G.IsAddOnLoaded = function() return false end
    _G.InCombatLockdown = function() return harness.combatLockdown end

    _G.CreateFrame = function()
        return frame_factory()
    end

    _G.hooksecurefunc = function(target, method, callback)
        if type(target) == "table" then
            local original = target[method]
            target[method] = function(...)
                local result
                if original then result = original(...) end
                callback(...)
                return result
            end
        end
    end

    _G.ChatFrameUtil = {
        OpenChat = function() end,
        GetActiveWindow = function() return _G.ACTIVE_CHAT_EDIT_BOX end,
    }

    local function send_chat(message, chatType, language, target)
        return harness.server:send(message, chatType, language, target)
    end

    _G.C_ChatInfo = {
        SendChatMessage = send_chat,
        InChatMessagingLockdown = function() return harness.chatLockdown end,
    }

    _G.C_BattleNet = {
        SendWhisper = function(accountID, message)
            return harness.server:send(message, "BN_WHISPER", nil, accountID)
        end,
        GetFriendAccountInfo = function() return nil end,
    }
    _G.BNSendWhisper = function(presenceID, message)
        return harness.server:send(message, "BN_WHISPER", nil, presenceID)
    end
    _G.C_Club = {
        SendMessage = function(clubID, streamID, message)
            return harness.server:send(message, "CLUB", clubID, streamID)
        end,
    }
    _G.GetChannelName = function(target)
        return tonumber(target) or 1, "General"
    end
end

local function install_timer(harness)
    _G.C_Timer = {
        NewTimer = function(duration, callback)
            local timer = {
                duration = duration,
                callback = callback,
                cancelled = false,
            }
            function timer:Cancel() self.cancelled = true end
            harness.timers[#harness.timers + 1] = timer
            return timer
        end,
        After = function(duration, callback)
            local timer = {
                duration = duration,
                callback = callback,
                cancelled = false,
            }
            function timer:Cancel() self.cancelled = true end
            harness.timers[#harness.timers + 1] = timer
            return timer
        end,
        NewTicker = function(duration, callback)
            return _G.C_Timer.NewTimer(duration, callback)
        end,
    }
end

local function make_server(harness)
    local server = {
        harness = harness,
        behavior = "echo",
        echoDelay = 0,
        sent = {},
    }

    local expectedEvents = {
        SAY = "CHAT_MSG_SAY",
        YELL = "CHAT_MSG_YELL",
        EMOTE = "CHAT_MSG_EMOTE",
        WHISPER = "CHAT_MSG_WHISPER_INFORM",
        BN_WHISPER = "CHAT_MSG_BN_WHISPER_INFORM",
        PARTY = "CHAT_MSG_PARTY",
        PARTY_LEADER = "CHAT_MSG_PARTY_LEADER",
        RAID = "CHAT_MSG_RAID",
        RAID_LEADER = "CHAT_MSG_RAID_LEADER",
        RAID_WARNING = "CHAT_MSG_RAID_WARNING",
        INSTANCE_CHAT = "CHAT_MSG_INSTANCE_CHAT",
        INSTANCE_CHAT_LEADER = "CHAT_MSG_INSTANCE_CHAT_LEADER",
        GUILD = "CHAT_MSG_GUILD",
        OFFICER = "CHAT_MSG_OFFICER",
        GUILD_DISCORD = "CHAT_MSG_GUILD_DISCORD",
        CHANNEL = "CHAT_MSG_CHANNEL",
        CLUB = "CHAT_MSG_COMMUNITIES_CHANNEL",
    }

    function server:set_behavior(behavior, delay)
        self.behavior = behavior
        self.echoDelay = delay or 0
    end

    function server:reset()
        self.behavior = "echo"
        self.echoDelay = 0
        self.sent = {}
    end

    function server:emit_for(entry, event)
        local args = { entry.message }
        if entry.chatType == "WHISPER" then
            args[2] = entry.target
        end
        for i = #args + 1, 11 do args[i] = nil end
        args[12] = self.harness.playerGUID
        if entry.chatType == "BN_WHISPER" then
            args[13] = entry.target
        end
        self.harness:emit(event, unpack(args, 1, 13))
    end

    function server:send(message, chatType, language, target)
        local entry = {
            message = message,
            chatType = chatType,
            language = language,
            target = target,
            behavior = self.behavior,
        }
        self.sent[#self.sent + 1] = entry

        if self.behavior == "error" then
            error("fake server rejected message")
        end
        if self.behavior == "drop" then
            return true
        end
        if self.behavior == "wrong-text" then
            entry.message = message .. " (server rewrite)"
        end

        local event = expectedEvents[chatType]
        if self.behavior == "wrong-event" then
            event = "CHAT_MSG_GUILD"
        end
        if not event then return true end

        local function echo()
            self:emit_for(entry, event)
        end
        -- Chat echoes arrive after the send API returns. Even the immediate
        -- case is scheduled for the next deterministic timer turn so Queue
        -- has installed its pending-ack/stall state first.
        C_Timer.After(self.echoDelay, echo)
        return true
    end

    return server
end

function Harness.new()
    local harness = {
        now = 100,
        playerGUID = "Player-1-CONTRACT",
        inInstance = true,
        instanceType = "party",
        inGroup = true,
        inRaid = false,
        inGuild = true,
        combatLockdown = false,
        chatLockdown = false,
        timers = {},
        events = {},
        YapperTable = {},
    }

    harness.server = make_server(harness)
    install_timer(harness)
    install_globals(harness)

    local Y = harness.YapperTable
    Y.Config = {
        Chat = { CHARACTER_LIMIT = 255, STALL_TIMEOUT = 1.5, USE_DELINEATORS = false },
        System = { DEBUG = false, VERBOSE = false },
    }
    Y.Core = {
        GetCharacterLanguage = function(_, language) return language end,
    }
    Y.Utils = nil
    Y.Error = {
        PrintError = function(_, kind, ...) harness.lastError = { kind, ... } end,
    }
    Y.Events = {
        Register = function(_, _, event, callback)
            harness.events[event] = callback
        end,
    }
    Y.History = {
        AddChatHistory = function(_, text, chatType, target)
            harness.history[#harness.history + 1] = { text = text, chatType = chatType, target = target }
        end,
    }
    harness.history = {}

    load_module("Src/Utils.lua", "Yapper", Y)
    Y.Utils.Print = function() end
    Y.Utils.DebugPrint = function() end
    Y.Utils.VerbosePrint = function() end
    Y.Utils.GetChatParent = function() return _G.UIParent end
    Y.Utils.MakeFullscreenAware = function() end

    load_module("Src/State.lua", "Yapper", Y)
    load_module("Src/API.lua", "Yapper", Y)
    load_module("Src/Router.lua", "Yapper", Y)
    load_module("Src/Chunking.lua", "Yapper", Y)

    Y.EditBox = {
        Overlay = frame_factory(),
        OverlayEdit = frame_factory(),
        SetOnSend = function() end,
        SetPreShowCheck = function() end,
    }

    load_module("Src/Queue.lua", "Yapper", Y)
    load_module("Src/Chat.lua", "Yapper", Y)

    harness.Queue = Y.Queue
    harness.Router = Y.Router
    harness.Chunking = Y.Chunking
    harness.Chat = Y.Chat
    harness.State = Y.State
    harness.API = Y.API
    harness.YapperAPI = _G.YapperAPI

    harness.Router:Init()
    harness.Chat:Init()
    return setmetatable(harness, { __index = Harness })
end

function Harness:emit(event, ...)
    local callback = self.events[event]
    if callback then callback(...) end
end

function Harness:fire_timers()
    local timers = self.timers
    self.timers = {}
    for _, timer in ipairs(timers) do
        if not timer.cancelled then timer.callback() end
    end
end

function Harness:fire_next_timer()
    local timer = table.remove(self.timers, 1)
    if timer and not timer.cancelled then timer.callback() end
end

function Harness:reset()
    self.timers = {}
    self.events = {}
    self.history = {}
    self.server:reset()
    self.Queue:Reset()
    self.Queue:Init()
    self.inInstance = true
    self.chatLockdown = false
    self.combatLockdown = false
end

function Harness:enqueue(chunks, chatType, language, target)
    self.Queue:Enqueue(chunks, chatType, language or "Common", target)
end

function Harness:queue_state()
    return self.YapperAPI:GetQueueState()
end

function Harness:sent_count()
    return #self.server.sent
end

function Harness:last_sent()
    return self.server.sent[#self.server.sent]
end

return Harness
