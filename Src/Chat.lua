-- chat functions. This is where the heavy lifting happens.
local YapperName, YapperTable = ...
local Chat = {}
YapperTable.Chat = Chat

local OriginalScriptHandlers = {} 
local PendingMessages = {}
local LastActionTime = 0
local MinInterval = 0.5 -- Slightly faster than 1s for better feel
local PendingPrompt = "(Press Enter to continue posting. %d posts remaining...)"

-------------------------------------------------------------------------------------
-- LOCAL FUNCTIONS --

-- Processes and splits long text into chunks of 255 characters or less.
-- the hard way, otherwise target markers don't render correctly.
local function ProcessPost(text, limit)
    local chunks = {}
    local currentChunk = ""
    local len = string.len(text)
    local i = 1
    limit = limit or YapperTable.Defaults.Chat.CharacterLimit

    while i <= len do
        -- Look for the beginning of a formatting tag.
        local char = string.sub(text, i, i)
        local sequence = nil

        -- Look for texture or colour escapes. Note: starts with | (pipe)
        if char == "|" then
            -- Look for colour!
            if string.sub(text, i+1, i+1) == "c" then
                -- colour was found. 10 chars: |cFFFFFFFF
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
                -- find the start of the last word in the current chunk
                local startOfLastWord = YapperTable.Utils:FindLastWord(currentChunk)

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
                    if YapperTable.Debug then
                        print("|cff00ff00" .. YapperName .. " DEBUG|r: ", currentChunk)
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
    -- Unlock the chat so we can type more than 255 chars.
    self:SetMaxBytes(0)
    self:SetMaxLetters(0)
    -- Edit box won't become infinite if we don't do this.
    -- I think it's a compatibility thing?
    if self.SetVisibleTextByteLimit then
        self:SetVisibleTextByteLimit(0)
    end
end

local function ClearQueue(self)
    -- if focus is lost, kill the queue to prevent sending old buffered msg
    PendingMessages[self] = nil
    -- Also clean up if editbox is being destroyed
    if not self:IsShown() or not self:GetParent() then
        OriginalScriptHandlers[self] = nil
    end
end

local function OnEnterPressed(self)
    -- Get current time for throttle.
    local now = GetTime()
    local text = self:GetText()
    -- string trim.
    local trimmedText = YapperTable.Utils:Trim(text)
    local limit = YapperTable.Defaults.Chat.CharacterLimit
    
    -- If trimmed string is empty, or it begins with a /, pass it to the OG blizzard handler
    if string.len(trimmedText) == 0 or string.sub(trimmedText, 1, 1) == "/" then
        local original = OriginalScriptHandlers[self]
        if original then original(self) end
        if YapperTable.Debug then
            -- In debug, print number of entries in YapperTable, and other tables in this file.
            local count = 0
            for _ in pairs(YapperTable) do count = count + 1 end
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", count, "entries in YapperTable")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #PendingMessages, "pending messages")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #OriginalScriptHandlers, "original script handlers")
        end
        return
    end

    -- Handle existing queue (continue pending posts)
    if PendingMessages[self] then
        -- If less than MinInterval time has passed, do nothing.
        if (now - LastActionTime) < MinInterval then
            return 
        end
        LastActionTime = now
        
        local data = PendingMessages[self]
        -- Send the next 2 chunks
        local sentCount = 0
        while #data.chunks > 0 and sentCount < 2 do
            local chunk = table.remove(data.chunks, 1)
            C_ChatInfo.SendChatMessage(chunk, data.chatType, data.lang, data.target)
            sentCount = sentCount + 1
        end
        if YapperTable.Debug then
            -- In debug, print number of entries in YapperTable, and other tables in this file.
            local count = 0
            for _ in pairs(YapperTable) do count = count + 1 end
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", count, "entries in YapperTable")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #PendingMessages, "pending messages")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #OriginalScriptHandlers, "original script handlers")
        end

        -- Check if we are finally done
        if #data.chunks == 0 then
            PendingMessages[self] = nil
            self:SetText("") 
            self:ClearFocus()
            text, data.chunks, data.lang, data.target, data.chatType = nil, nil, nil, nil, nil
        else
            -- Update prompt with remaining count
            self:SetText(string.format(PendingPrompt, #data.chunks))
            self:SetFocus()
        end
        return
    end

    -- Valid press updates timer
    LastActionTime = now

    -- New message processing    
    -- short messages go straight to blizzard
    if string.len(text) <= limit then
        local original = OriginalScriptHandlers[self]
        if original then original(self) end
        if YapperTable.Debug then
            -- In debug, print number of entries in YapperTable, and other tables in this file.
            local count = 0
            for _ in pairs(YapperTable) do count = count + 1 end
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", count, "entries in YapperTable")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #PendingMessages, "pending messages")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #OriginalScriptHandlers, "original script handlers")
        end
        return
    end
    
    -- Check if chat type is supported for splitting
    local chatType = self:GetAttribute("chatType")
    local valid = (chatType == "SAY") or (chatType == "YELL") or (chatType == "PARTY") or 
                  (chatType == "RAID") or (chatType == "EMOTE") or (chatType == "GUILD")

    if not valid then
        -- complain if we can't split for this chat type
        YapperTable.Error:PrintError("BAD_STRING", "Unsupported chat type: " .. (chatType or "unknown"))
        self:SetText(string.sub(text, 1, limit)) -- truncate so we don't break things
        local original = OriginalScriptHandlers[self]
        if original then original(self) end
        text, chatType = nil, nil
        return
    end

    -- Valid Long Message: Split it into chunks
    local chunks = ProcessPost(text, limit)
    local lang = self:GetAttribute("language")
    local target = self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget")

    -- Decide how to send
    if #chunks <= 3 then
        -- send all immediately if 3 posts or fewer
        for _, chunk in ipairs(chunks) do
            C_ChatInfo.SendChatMessage(chunk, chatType, lang, target)
        end
        self:SetText("")
        self:ClearFocus()
        text, chunks, lang, target, chatType = nil, nil, nil, nil, nil
        if YapperTable.Debug then
            -- In debug, print number of entries in YapperTable, and other tables in this file.
            local count = 0
            for _ in pairs(YapperTable) do count = count + 1 end
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", count, "entries in YapperTable")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #chunks, "chunks in message")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #PendingMessages, "pending messages")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #OriginalScriptHandlers, "original script handlers")
        end
    else
        -- otherwise send first 3 immediately, then queue the rest
        for i = 1, 3 do
            C_ChatInfo.SendChatMessage(chunks[i], chatType, lang, target)
        end

        local remaining = {}
        for i = 4, #chunks do
            table.insert(remaining, chunks[i])
        end

        PendingMessages[self] = {
            chunks = remaining,
            chatType = chatType,
            lang = lang,
            target = target
        }

        self:AddHistoryLine(text) -- Add the long message to history
        self:SetText(string.format(PendingPrompt, #remaining))
        self:SetFocus()
        if YapperTable.Debug then
            -- In debug, print number of entries in YapperTable, and other tables in this file.
            local count = 0
            for _ in pairs(YapperTable) do count = count + 1 end
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", count, "entries in YapperTable")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #chunks, "chunks in message")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #PendingMessages, "pending messages")
            print("|cff00ff00" .. YapperName .. " DEBUG|r: ", #OriginalScriptHandlers, "original script handlers")
        end
    end
end

-------------------------------------------------------------------------------------
-- GLOBAL FUNCTIONS --

function Chat:Init()
    -- Initialise all chat edit boxes.
    for i = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame"..i.."EditBox"]
        if editBox then
            self:SetupEditBox(editBox)
        end
    end
end

function Chat:SetupEditBox(editBox)
    -- Hook blizzard edit boxes and swap the OnEnter script.
    if OriginalScriptHandlers[editBox] then return end
    
    UnlockLimits(editBox)
    
    -- Hook scripts for persistence
    editBox:HookScript("OnShow", UnlockLimits)
    editBox:SetHistoryLines(YapperTable.Defaults.Chat.MaxHistoryLines)
    editBox:HookScript("OnEditFocusGained", UnlockLimits)
    editBox:HookScript("OnEditFocusLost", ClearQueue)
    editBox:HookScript("OnHide", function(self) 
        OriginalScriptHandlers[self] = nil
        PendingMessages[self] = nil
    end)

    -- Borrow the original script so we can still use it for short messages.
    OriginalScriptHandlers[editBox] = editBox:GetScript("OnEnterPressed")
    editBox:SetScript("OnEnterPressed", OnEnterPressed)
end

function Chat:Cleanup()
    for editBox, _ in pairs(OriginalScriptHandlers) do
        if not editBox:IsShown() or not editBox:GetParent() then
            OriginalScriptHandlers[editBox] = nil
            PendingMessages[editBox] = nil
        end
    end
end
