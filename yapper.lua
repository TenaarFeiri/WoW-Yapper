--[[
    Yapper by Sara Schulze Øverby, aka Tenaar Feiri, Arru/Arruh and a whole bunch of other names in WoW...
    Licence (https://creativecommons.org/licenses/by-nc/4.0/) is simple: Use, modify and distribute non-commercially
    however much you like, but give attribution. Thanks <3
    
    Yapper is meant to be a simple, no-interface no-options works-out-of-the-box stand-in/replacement for 
    addons like EmoteSplitter. It's my first addon and my first foray into Lua and I'm still learning
    how best to accomplish things.
    Yapper is designed to be fully independent; it relies on no dependencies and attempts to follow the principles
    of "maximum results for minimum work". I'll probably optimise things down the line, as I get better at this.

    Yapper should be resistant to future patches, given its contained nature, but who knows what Midnight will bring.
    
]]


local AddonName, Me = ...

local debug = false

-- CONSTANTS
local MaxStringLength = 255
local OriginalScriptHandlers = {} 
local IsQuoteOpen = false

local PendingMessages = {}
local LastActionTime = 0
local MinInterval = 1
local PendingPrompt = "(Press Enter to continue posting. %d posts remaining...)"

-- FUNCTIONS --

local function GetMetadata()
    return {C_AddOns.GetAddOnInfo(AddonName)} -- Return a table.
end

local function GetMetaAddonName()
    return GetMetadata()[2]
end

-- Break the message into parseable chunks.
-- ... the hard way, otherwise target markers don't render correctly.
local function ChunkMessage(text, limit)
    local chunks = {}
    local currentChunk = ""
    local len = string.len(text)
    local i = 1

    while i <= len do
        -- Look for the beginning of a formatting tag.
        local char = string.sub(text, i, i)
        local sequence = nil

        -- Look for texture or colour escapes. Note: starts with | (pipe)
        if char == "|" then
            -- Look for colour!
            if string.sub(text, i+1, i+1) == "c" then
                -- colour was found. 10 chars: |cFFFFFFFF
                -- put it in our sequence.
                sequence = string.sub(text, i, i+9)
            elseif string.sub(text, i+1, i+1) == "r" then
                -- Are we resetting? Two chars: |r
                sequence = string.sub(text, i, i+1)
            elseif string.sub(text, i+1, i+1) == "T" then
                -- Look for texture tags
                local tStart, tEnd = string.find(text, "|t", i)
                if tEnd then
                    sequence = string.sub(text, i, tEnd)
                end
            end
            -- Now we want to find target markers.
        elseif char == "{" then
            local closing = string.find(text, "}", i) -- find the closing tag
            -- Local tags are short. use a buffer of 10, any more is probably normal post text.
            if closing and (closing - i) < 10 then
                sequence = string.sub(text, i, closing)
            end
        end
        -- are we adding whole sequences or just chars?
        local toAdd = sequence or char
        local contentLength = string.len(toAdd)

        -- do we exceed limit?
        if string.len(currentChunk) + contentLength > limit then
            -- if current chunk is empty but sequence is huge
            -- split to avoid infinite loop
            if string.len(currentChunk) == 0 then
                table.insert(chunks, string.sub(toAdd, 1, limit))
                i = i + limit
            else
                -- now we have to do word wrapping.
                -- find the start of the last word in the current chunk
                -- regex: "one or more non-space characters"
                local startOfLastWord = string.find(currentChunk, "[^%s]+$") -- side note I hate regex

                -- wrap if we found a word and it's not the entire string, split if it is the whole str
                if startOfLastWord and startOfLastWord > 1 then
                    local savedChunk = string.sub(currentChunk, 1, startOfLastWord - 1)
                    local carriedChunk = string.sub(currentChunk, startOfLastWord)

                    table.insert(chunks, savedChunk)

                    -- Just in case carrying the word over and a new tag makes the next chunk too big...
                    if string.len(carriedChunk) + string.len(toAdd) > limit then
                        -- flush
                        table.insert(chunks, carriedChunk)
                        currentChunk = toAdd
                    else
                        -- Otherwise concatenate.
                        currentChunk = carriedChunk .. toAdd
                    end
                else
                    -- No space found (giant word?) or only spaces. hard split
                    table.insert(chunks, currentChunk)
                    if debug then
                        print("|cff00ff00" .. GetMetaAddonName() .. "|r:")
                    end
                    currentChunk = toAdd
                end

                i = i + contentLength -- move on ahead
            end
        else
            -- It fits? Add it.
            currentChunk = currentChunk .. toAdd
            i = i + contentLength
        end
    end
        
        -- Final remaining chunk...
    if string.len(currentChunk) > 0 then
        table.insert(chunks, currentChunk)
    end

    return chunks -- ready to post
end

local function UnlockLimits(self)
    -- Unlock the chat.
    self:SetMaxBytes(0)
    self:SetMaxLetters(0)
    -- Edit box won't become infinite if we don't do this.
    -- I think it's a compatibility thing?
    if self.SetVisibleTextByteLimit then
        self:SetVisibleTextByteLimit(0)
    end
end

local function ProcessQueue()
    -- If nothing left, stop.
    if #MessageQueue == 0 then
        IsSending = false
        return
    end
    
    IsSending = true
    
    -- Get the next message data
    local msgData = table.remove(MessageQueue, 1)
    
    -- Send it
    SendChatMessage(msgData.text, msgData.chatType, msgData.lang, msgData.target)
    
    -- Wait, then fire the next one
    C_Timer.After(ThrottleDelay, ProcessQueue)
end

local function YapperOnEnter(self)
    -- Get current time for throttle.
    local now = GetTime()
    -- If less than MinInterval time has passed, do nothing.
    if (now - LastActionTime) < MinInterval then
        return 
    end
    
    -- valid press updates timer
    LastActionTime = now

    -- continue pending
    if PendingMessages[self] then
        local data = PendingMessages[self]
        
        -- Send the next 2 chunks
        local sentCount = 0
        while #data.chunks > 0 and sentCount < 2 do
            local chunk = table.remove(data.chunks, 1)
            SendChatMessage(chunk, data.chatType, data.lang, data.target)
            sentCount = sentCount + 1
        end

        -- Check if we are done
        if #data.chunks == 0 then
            PendingMessages[self] = nil
            self:SetText("") 
            self:ClearFocus()
        else
            -- Update prompt
            self:SetText(string.format(PendingPrompt, #data.chunks))
            self:SetFocus()
        end
        return
    end

    -- new msg
    local text = self:GetText()
    local len = string.len(text)

    -- short messages go straight to blizz
    if len <= MaxStringLength then
        local original = OriginalScriptHandlers[self]
        if original then original(self) end
        return
    end
    
    local chatType = self:GetAttribute("chatType")
    local valid = (chatType == "SAY") or (chatType == "YELL") or (chatType == "PARTY") or 
                  (chatType == "RAID") or (chatType == "EMOTE") or (chatType == "GUILD")

    if not valid then
        print("|cFFFF0000".. GetMetaAddonName() .. ":|r Text too long for "..(chatType or "?")..". Truncating.")
        self:SetText(string.sub(text, 1, MaxStringLength))
        local original = OriginalScriptHandlers[self]
        if original then original(self) end
        return
    end

    -- Valid Long Message: Split it
    local lines = ChunkMessage(text, MaxStringLength)
    local lang = self:GetAttribute("language")
    local target = self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget")

    if #lines <= 3 then
        -- send all immediately if 3 posts or fewer
        for _, line in ipairs(lines) do
            SendChatMessage(line, chatType, lang, target)
        end
        self:SetText("")
        self:ClearFocus()
    else
        -- otherwise send first 3 immediately, before queue...
        for i = 1, 3 do
            SendChatMessage(lines[i], chatType, lang, target)
        end

        -- queue up
        local remaining = {}
        for i = 4, #lines do
            table.insert(remaining, lines[i])
        end

        PendingMessages[self] = {
            chunks = remaining,
            chatType = chatType,
            lang = lang,
            target = target
        }

        self:AddHistoryLine(text)
        self:SetText(string.format(PendingPrompt, #remaining))
        self:SetFocus()
    end
end

-- SETUP

local function ClearQueue(self)
    -- if focus is lost, kill the queue to prevent sending old buffered msg
    PendingMessages[self] = nil
end

local function SetupEditBox(editBox)
    if OriginalScriptHandlers[editBox] then return end
    UnlockLimits(editBox)
    
    editBox:HookScript("OnShow", UnlockLimits)
    editBox:HookScript("OnEditFocusGained", UnlockLimits)
    editBox:HookScript("OnEditFocusLost", ClearQueue) 

    OriginalScriptHandlers[editBox] = editBox:GetScript("OnEnterPressed")
    editBox:SetScript("OnEnterPressed", YapperOnEnter)
end

local function Execute(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        
        for i = 1, NUM_CHAT_WINDOWS do
            local editBox = _G["ChatFrame"..i.."EditBox"]
            if editBox then
                SetupEditBox(editBox)
            end
        end

        self:UnregisterEvent("PLAYER_ENTERING_WORLD");
        print("|cff00ff00" .. GetMetaAddonName() .. "|r: Ready to roll. Happy RP-ing!")
    end
end

local EventFrame = CreateFrame("Frame", "YapperEventFrame");
local ChatRecolourFrame = CreateFrame("Frame", "YapperRecolourFrame")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
EventFrame:SetScript("OnEvent", Execute)
ChatRecolourFrame:RegisterEvent("CHAT_MSG_EMOTE")
