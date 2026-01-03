-- Chat functions. This is where the heavy lifting happens.
local YapperName, YapperTable = ...
if not YapperTable.Utils then
    -- Utils is critical here, kill everything.
    YapperTable.Error:Throw("MISSING_UTILS")
    return
end
local Chat = {}
YapperTable.Chat = Chat

local OriginalScriptHandlers = {} 
local PendingMessages = {}
local LastActionTime = 0
local PendingPrompt = "(Press Enter to continue posting. %d posts remaining...)"

local Delineator = YapperTable.Config.Chat.DELINEATOR or " >> "
local Prefix = YapperTable.Config.Chat.PREFIX or ">> "
local MinInterval = YapperTable.Config.Chat.MIN_POST_INTERVAL or 0.5

-------------------------------------------------------------------------------------
-- FUNCTIONS --

--- Yapper API: Returns the current delineators in Chat as a tuple.
--- @return string The delineator string.
--- @return string The prefix string.
function Chat:GetDelineators()
    return Delineator, Prefix
end

--- Yapper API: Change the delineator and prefix to whatever you want!
--- Defaults to " >>" and ">> ".
--- @param NewDelineator any
--- @param NewPrefix any
function Chat:SetDelineators(NewDelineator, NewPrefix)
    Delineator = tostring(NewDelineator) or " >> "
    Prefix = tostring(NewPrefix) or ">> "
    YapperTable.Config.Chat.DELINEATOR = Delineator
    YapperTable.Config.Chat.PREFIX = Prefix
end

-------------------------------------------------------------------------------------
-- HELPER FUNCTIONS --

--- Flushes accumulated chunk parts into the chunks table.
--- @param chunks table The chunks table to insert into
--- @param chunkParts table The parts array to flush
--- @return table Empty parts array
--- @return number Reset size (0)
local function FlushChunk(chunks, chunkParts)
    if #chunkParts > 0 then
        table.insert(chunks, table.concat(chunkParts))
    end
    return {}, 0  -- Return new empty parts and reset size
end

--- Starts a new chunk with prefix and active colour.
--- @param chunkParts table The parts array to add to
--- @param currentSize number Current chunk size
--- @param activePrefix string The prefix to add
--- @param activeColour string|nil The active colour tag
--- @return number Updated chunk size
local function StartNewChunk(chunkParts, currentSize, activePrefix, activeColour)
    if activePrefix ~= "" then
        table.insert(chunkParts, activePrefix)
        currentSize = currentSize + #activePrefix
    end
    if activeColour then
        table.insert(chunkParts, activeColour)
        currentSize = currentSize + #activeColour
    end
    return currentSize
end

-------------------------------------------------------------------------------------

--- Drops pending messages from the table and clears the EditBox.
--- Useful for cases where Yapper is being disabled while it is possible that it 
--- has messages pending.
function Chat:DropPendingMessages()
    for EditBox, _ in pairs(PendingMessages) do
        if EditBox and EditBox:IsShown() then
            EditBox:SetText("")  -- Clear the prompt
        end
    end
    table.wipe(PendingMessages)  -- Clear without losing the table reference
    YapperTable.Utils:VerbosePrint("Pending message queue cleared.")
end
--- Refactored version of ProcessPost using table accumulation
--- instead of string concatenation. It is slightly slower, but
--- easier to maintain and possibly scales better with humongous
--- messages. If Blizz ever increase the upper limits...
--- @param Text string The text to process and split into chunks.
--- @param Limit number The character limit for each chunk.
--- @return table An array of message chunks ready to send.
function Chat:ProcessPost(Text, Limit)
    if YapperTable.YAPPER_DISABLED then 
        YapperTable.Error:Throw("UNKNOWN", "ProcessPost called while Yapper is overridden. This should've been prevented by OnEnterPressed.")
    end
    
    if type(Text) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "ProcessPost", "string", type(Text))
        return {""}
    end
    
    Limit = Limit or YapperTable.Config.Chat.CHARACTER_LIMIT
    Text = Text:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Tokenization (unchanged, this part is already efficient)
    local Tokens = {} 
    local Pos = 1
    
    while Pos <= #Text do
        local Start, Stop = Text:find("[|{]", Pos)
        if not Start then
            table.insert(Tokens, Text:sub(Pos))
            break
        end

        if Start > Pos then
            table.insert(Tokens, Text:sub(Pos, Start - 1))
        end

        local NextChar = Text:sub(Start + 1, Start + 1)
        local TagEnd = Start
        
        if NextChar == "c" then 
            TagEnd = Start + 9
        elseif NextChar == "r" then 
            TagEnd = Start + 1
        elseif NextChar == "t" then 
            _, TagEnd = Text:find("|t", Start + 2)
        elseif Text:sub(Start, Start) == "{" then 
            _, TagEnd = Text:find("}", Start + 1)
        end

        TagEnd = TagEnd or Start
        table.insert(Tokens, Text:sub(Start, TagEnd))
        Pos = TagEnd + 1
    end

    -- Setup
    local Chunks = {}
    local ChunkParts = {}  -- NEW: Accumulator for current chunk parts
    local CurrentChunkSize = 0  -- NEW: Track size without recalculating
    local ActiveColour = nil
    
    local ActiveDelineator = ""
    local ActivePrefix = ""
    if YapperTable.Config.Chat.USE_DELINEATORS then
        ActiveDelineator = Delineator
        ActivePrefix = Prefix
    end

    -- Calculate actual overhead: colour reset (2) + delineator length
    -- Only applied when we need to split chunks and add these tags
    local MaxOverhead = #ActiveDelineator + 2  -- +2 for potential |r
    local EffectiveLimit = Limit - MaxOverhead
    
    -- Process tokens
    for i, Token in ipairs(Tokens) do
        local IsTag = Token:sub(1, 1) == "|" or Token:sub(1, 1) == "{"
        local IsColour = Token:match("^|c")
        local IsReset = Token == "|r"
        
        local SuffixOverhead = (ActiveColour and 2 or 0) + #ActiveDelineator
        
        if CurrentChunkSize + #Token + SuffixOverhead > EffectiveLimit then
            -- Need to split
            if IsTag then
                -- Close current chunk with colour reset and delineator
                if ActiveColour then
                    table.insert(ChunkParts, "|r")
                end
                if ActiveDelineator ~= "" then
                    table.insert(ChunkParts, ActiveDelineator)
                end
                ChunkParts, CurrentChunkSize = FlushChunk(Chunks, ChunkParts)
                
                -- Start new chunk and add the tag
                CurrentChunkSize = StartNewChunk(ChunkParts, CurrentChunkSize, ActivePrefix, ActiveColour)
                table.insert(ChunkParts, Token)
                CurrentChunkSize = CurrentChunkSize + #Token
            else
                -- Split text token across chunks (word-aware)
                local RemainingText = Token
                
                while CurrentChunkSize + #RemainingText + SuffixOverhead > EffectiveLimit do
                    local SpaceLeft = EffectiveLimit - CurrentChunkSize - SuffixOverhead
                    local Bite = RemainingText:sub(1, SpaceLeft)
                    local LastWord = YapperTable.Utils:FindLastWord(Bite)
                    local SplitAt = (LastWord and LastWord > 1) and (LastWord - 1) or SpaceLeft
                    
                    -- Add the split portion
                    table.insert(ChunkParts, RemainingText:sub(1, SplitAt))
                    
                    -- Close chunk with colour reset and delineator
                    if ActiveColour then
                        table.insert(ChunkParts, "|r")
                    end
                    if ActiveDelineator ~= "" then
                        table.insert(ChunkParts, ActiveDelineator)
                    end
                    ChunkParts, CurrentChunkSize = FlushChunk(Chunks, ChunkParts)
                    
                    -- Update remaining text
                    RemainingText = RemainingText:sub(SplitAt + 1)
                    
                    -- Start new chunk
                    CurrentChunkSize = StartNewChunk(ChunkParts, CurrentChunkSize, ActivePrefix, ActiveColour)
                end
                
                -- Add the final piece of the split text
                if #RemainingText > 0 then
                    table.insert(ChunkParts, RemainingText)
                    CurrentChunkSize = CurrentChunkSize + #RemainingText
                end
            end
        else
            -- Token fits in current chunk
            table.insert(ChunkParts, Token)
            CurrentChunkSize = CurrentChunkSize + #Token
        end

        if IsColour then 
            ActiveColour = Token 
        end
        if IsReset then 
            ActiveColour = nil 
        end
    end
    
    -- Flush final chunk
    FlushChunk(Chunks, ChunkParts)
    
    return Chunks
end


local function UnlockLimits(self)
    -- If Yapper is overridden, don't touch anything.
    if YapperTable.YAPPER_DISABLED then return end
    -- Run compatibility patches.
    YapperTable.CompatLib:ApplyPatches("all")

    -- Unlock the chat so we can type more than 255 chars.
    self:SetMaxBytes(0)
    self:SetMaxLetters(0)
    -- Required for 7.x (Legion) compatibility. Without this, editbox unlocking fails. Why? Who knows!
    if self.SetVisibleTextByteLimit then
        self:SetVisibleTextByteLimit(0)
    end
end

local function ClearQueue(self)
    -- If Yapper is overridden, don't touch anything.
    if YapperTable.YAPPER_DISABLED then return end

    -- If focus is lost, kill the queue to prevent sending old buffered messages.
    PendingMessages[self] = nil
    -- Also clean up if Editbox is being destroyed
    if not self:IsShown() or not self:GetParent() then
        OriginalScriptHandlers[self] = nil
    end
end

local function PratRememberChannel(EditBox, ChannelType)
    if _G.ChatTypeInfo and _G.ChatTypeInfo[ChannelType] and _G.ChatTypeInfo[ChannelType].sticky == 1 then
        EditBox:SetAttribute("chatType", ChannelType)
    end
end

local function OnEnterPressed(self)
    if YapperTable.YAPPER_DISABLED then
        -- If Yapper is overridden, do nothing. Someone
        -- may have overridden it in the middle of a pending post
        -- action or something.
        return
    end
    local SendFunc = YapperTable.SendChatMessageOverride or C_ChatInfo.SendChatMessage
    
    -- Store current chat type for Prat compatibility.
    local CurrentChatType = self:GetAttribute("chatType")
    
    local Now = GetTime()
    local Text = self:GetText()
    local TrimmedText = YapperTable.Utils:Trim(Text)
    if string.len(TrimmedText) == 0 then
        self:ClearFocus()
        PratRememberChannel(self, CurrentChatType)
        return
    end
    local Limit = YapperTable.Config.Chat.CHARACTER_LIMIT

    -- Commands go to ChatEdit_SendText
    if string.sub(TrimmedText, 1, 1) == "/" then
        ChatEdit_SendText(self)
        -- Log it to history.
        self:AddHistoryLine(TrimmedText)
        PratRememberChannel(self, CurrentChatType)
        return
    end

    if CurrentChatType == "WHISPER" then
        if string.len(TrimmedText) > YapperTable.Config.Chat.CHARACTER_LIMIT then
            -- Add the full text to history so it can be recovered.
            self:AddHistoryLine(TrimmedText)
            TrimmedText = string.sub(TrimmedText, 1, YapperTable.Config.Chat.CHARACTER_LIMIT) -- Then trim to the limit.
            -- Then just print an error.
            YapperTable.Error:PrintError("CHAT_WHISPER_TRUNCATED", YapperTable.Config.Chat.CHARACTER_LIMIT)
        end
        -- Send as a normal whisper.
        SendFunc(TrimmedText, CurrentChatType, self:GetAttribute("language"), self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget"))
        self:SetText("")
        self:ClearFocus()
        PratRememberChannel(self, CurrentChatType)
        return
    end

    -- Handle existing queue (continue pending posts)
    if PendingMessages[self] then
        if (Now - LastActionTime) < MinInterval then
            return
        end
        LastActionTime = Now
        
        local Data = PendingMessages[self]
        local SentCount = 0
        while #Data.Chunks > 0 and SentCount < 2 do
            local Chunk = table.remove(Data.Chunks, 1)
            SendFunc(Chunk, Data.ChatType, Data.Lang, Data.Target)
            SentCount = SentCount + 1
        end

        if #Data.Chunks == 0 then
            PendingMessages[self] = nil
            self:SetText("")
            self:ClearFocus()
            PratRememberChannel(self, CurrentChatType)
        else
            self:SetText(string.format(PendingPrompt, #Data.Chunks))
            self:SetFocus()
        end
        return
    end

    LastActionTime = Now

    -- Short messages
    if string.len(TrimmedText) <= Limit then
        SendFunc(TrimmedText, CurrentChatType, self:GetAttribute("language"), self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget"))
        self:SetText("")
        self:ClearFocus()
        self:AddHistoryLine(TrimmedText)
        PratRememberChannel(self, CurrentChatType)
        return
    end
    
    -- Check if chat type is supported for splitting
    local Valid = (CurrentChatType == "SAY") or (CurrentChatType == "YELL") or (CurrentChatType == "PARTY") or 
                  (CurrentChatType == "RAID") or (CurrentChatType == "EMOTE") or (CurrentChatType == "GUILD")

    if not Valid then
        YapperTable.Error:PrintError("BAD_STRING", "Unsupported chat type: " .. (CurrentChatType or "unknown"))
        self:SetText(string.sub(Text, 1, Limit))
        local Original = OriginalScriptHandlers[self]
        if Original then Original(self) end
        return
    end

    -- Long message splitting
    local Chunks = Chat:ProcessPost(TrimmedText, Limit)
    local Lang = self:GetAttribute("language")
    local Target = self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget")
    local InstantLimit = YapperTable.Config.Chat.INSTANT_SEND_LIMIT

    if #Chunks <= InstantLimit then
        for _, Chunk in ipairs(Chunks) do
            SendFunc(Chunk, CurrentChatType, Lang, Target)
        end
        self:SetText("")
        self:ClearFocus()
        self:AddHistoryLine(TrimmedText)
        PratRememberChannel(self, CurrentChatType)
    else
        for i = 1, InstantLimit do
            SendFunc(Chunks[i], CurrentChatType, Lang, Target)
        end

        local Remaining = {}
        for i = InstantLimit + 1, #Chunks do
            table.insert(Remaining, Chunks[i])
        end 

        PendingMessages[self] = {
            Chunks = Remaining,
            ChatType = CurrentChatType,
            Lang = Lang,
            Target = Target
        }

        self:AddHistoryLine(TrimmedText)
        self:SetText(string.format(PendingPrompt, #Remaining))
        self:SetFocus()
    end
end

function Chat:Init()
    Chat:Cleanup()
    -- Also wipe pending messages and original handlers on init. Just in case.
    table.wipe(OriginalScriptHandlers)
    table.wipe(PendingMessages)
    -- Initialise all chat edit boxes.
    for i = 1, NUM_CHAT_WINDOWS do
        local EditBox = _G["ChatFrame"..i.."EditBox"]
        if EditBox then
            self:SetupEditBox(EditBox)
        end
    end
    YapperTable.Utils:VerbosePrint("Chat module initialised.")
end

--- Hooks a Blizzard EditBox to add Yapper's long-message handling.
--- @param EditBox table The EditBox frame object.
function Chat:SetupEditBox(EditBox)
    -- Hook Blizzard edit boxes and swap the OnEnter script.
    -- If we've already hooked this EditBox and our handler is still installed, skip.
    local currentScript = EditBox:GetScript("OnEnterPressed")
    if OriginalScriptHandlers[EditBox] and currentScript == OnEnterPressed then
        return
    end

    UnlockLimits(EditBox)
    
    -- Hook scripts for persistence
    EditBox:HookScript("OnShow", UnlockLimits)
    EditBox:SetHistoryLines(YapperTable.Config.Chat.MAX_HISTORY_LINES)
    EditBox:HookScript("OnEditFocusGained", UnlockLimits)
    EditBox:HookScript("OnEditFocusLost", ClearQueue)
    EditBox:HookScript("OnHide", function(self) 
        --OriginalScriptHandlers[self] = nil
        --PendingMessages[self] = nil
        Chat:Cleanup()
    end)

    -- Borrow the original script so we can still use it for short messages.
    OriginalScriptHandlers[EditBox] = currentScript
    -- If another addon replaced our handler, (re)install ours so we keep control.
    if currentScript ~= OnEnterPressed then
        EditBox:SetScript("OnEnterPressed", OnEnterPressed)
    end
    YapperTable.Utils:VerbosePrint("Chat EditBox hooked: " .. EditBox:GetName())
end

function Chat:Cleanup()
    local ToRemove = {}
    for EditBox in pairs(OriginalScriptHandlers) do
        if not EditBox:IsShown() or not EditBox:GetParent() then
            table.insert(ToRemove, EditBox)
        end
    end
    for _, EditBox in ipairs(ToRemove) do
        OriginalScriptHandlers[EditBox] = nil
        PendingMessages[EditBox] = nil
    end
end

--- Reverts all edit boxes to their original Blizzard settings.
function Chat:RestoreBlizzardDefaults()
    for EditBox, OriginalHandler in pairs(OriginalScriptHandlers) do
        if EditBox then
            -- Restore the original OnEnterPressed handler.
            EditBox:SetScript("OnEnterPressed", OriginalHandler)
            
            -- Restore default WoW limits.
            EditBox:SetMaxBytes(255)
            EditBox:SetMaxLetters(255)
            if EditBox.SetVisibleTextByteLimit then
                EditBox:SetVisibleTextByteLimit(255)
            end
        end
    end
    -- Clear our tracking tables.
    table.wipe(OriginalScriptHandlers)
    table.wipe(PendingMessages)
    YapperTable.Utils:VerbosePrint("Chat EditBoxes restored to Blizzard defaults.")
end

