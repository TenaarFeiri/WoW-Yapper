-- Chat functions. This is where the heavy lifting happens.
local YapperName, YapperTable = ...
if not YapperTable.Utils then
    -- Utils is critical here, kill everything.
    YapperTable.Error:Throw("MISSING_UTILS")
    return
end
local Chat = {}
YapperTable.Chat = Chat

if not YapperTable.Defaults.Chat then
    YapperTable.Defaults.Chat = {}
end

if not YapperTable.Defaults.Chat.CharacterLimit then
    YapperTable.Defaults.Chat.CharacterLimit = 255
end

local OriginalScriptHandlers = {} 
local PendingMessages = {}
local LastActionTime = 0
local MinInterval = 0.5 -- Slightly faster than 1s for better feel
local PendingPrompt = "(Press Enter to continue posting. %d posts remaining...)"
local Margin = 20 -- safety margin for chat if we're doing complex ops

local Delineator = " >>"
local Prefix = ">> "

-------------------------------------------------------------------------------------
-- FUNCTIONS --

function Chat:GetDelineators()
    return Delineator, Prefix
end

function Chat:SetDelineators(NewDelineator, NewPrefix)
    Delineator, Prefix = NewDelineator or " >>", NewPrefix or ">> "
end

function Chat:ProcessPost(Text, Limit)
    if YapperTable:YapperOverridden() then 
        -- We're overridden. How'd we get here, idk? This should be unregistered.
        -- Do nothing.
        return 
    end
    Limit = Limit or YapperTable.Defaults.Chat.CharacterLimit
    Text = Text:gsub("^%s+", ""):gsub("%s+$", "") -- trim errant whitespace
    
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
        
        if NextChar == "c" then TagEnd = Start + 9
        elseif NextChar == "r" then TagEnd = Start + 1
        elseif NextChar == "t" then _, TagEnd = Text:find("|t", Start + 2)
        elseif Text:sub(Start, Start) == "{" then _, TagEnd = Text:find("}", Start + 1)
        end

        TagEnd = TagEnd or Start
        table.insert(Tokens, Text:sub(Start, TagEnd))
        Pos = TagEnd + 1
    end

    local Chunks = {}
    local CurrentChunk = ""
    local ActiveColour = nil -- Tracks the current |c... colour tag.

    local ActiveDelineator = ""
    local ActivePrefix = ""
    if YapperTable.Configs.Chat.USE_DELINEATORS then
        ActiveDelineator = Delineator
        ActivePrefix = Prefix
    end

    -- Account for Prefix (e.g. ">> ") and Delineator (e.g. " >>")
    -- and potential ActiveColour (10 chars) + Reset "|r" (2 chars)
    local EffectiveLimit = Limit - Margin

    for i, Token in ipairs(Tokens) do
        local IsTag = Token:sub(1, 1) == "|" or Token:sub(1, 1) == "{"
        local IsColour = Token:match("^|c")
        local IsReset = Token == "|r"

        -- How much overhead do we have if we split here?
        -- (|r) + ( >>)
        local SuffixOverhead = (ActiveColour and 2 or 0) + #ActiveDelineator

        if #CurrentChunk + #Token + SuffixOverhead > EffectiveLimit then
            if IsTag then
                -- Flush with reset if needed and delineator
                table.insert(Chunks, CurrentChunk .. (ActiveColour and "|r" or "") .. ActiveDelineator)
                -- Then begin the new chunk with prefix and active colour
                CurrentChunk = ActivePrefix .. (ActiveColour or "") .. Token
            else
                local RemainingText = Token
                while #CurrentChunk + #RemainingText + SuffixOverhead > EffectiveLimit do
                    local SpaceLeft = EffectiveLimit - #CurrentChunk - SuffixOverhead
                    local Bite = RemainingText:sub(1, SpaceLeft)
                    local LastWord = YapperTable.Utils:FindLastWord(Bite)
                    local SplitAt = (LastWord and LastWord > 1) and (LastWord - 1) or SpaceLeft
                    
                    table.insert(Chunks, CurrentChunk .. RemainingText:sub(1, SplitAt) .. (ActiveColour and "|r" or "") .. ActiveDelineator)
                    RemainingText = RemainingText:sub(SplitAt + 1)
                    CurrentChunk = ActivePrefix .. (ActiveColour or "")
                end
                CurrentChunk = CurrentChunk .. RemainingText
            end
        else
            CurrentChunk = CurrentChunk .. Token
        end
        
        -- Save the colour state after update for assembly
        -- so the *next* chunk knows which colour to use.
        if IsColour then ActiveColour = Token end
        if IsReset then ActiveColour = nil end
    end
    
    if #CurrentChunk > 0 then
        table.insert(Chunks, CurrentChunk)
    end
    
    return Chunks
end



local function UnlockLimits(self)
    -- If Yapper is overridden, don't touch anything.
    if YapperTable:YapperOverridden() then return end

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
    -- If Yapper is overridden, don't touch anything.
    if YapperTable:YapperOverridden() then return end

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
    if not _G.YAPPER_COMPATIBILITY then
        print("|cff00ff00" .. YapperName .. "|r: ", "WAITING for CompatLib to finish loading. Please press Enter again in a second or two.")
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
    local Limit = YapperTable.Defaults.Chat.CharacterLimit

    -- Commands go to ChatEdit_SendText
    if string.sub(TrimmedText, 1, 1) == "/" then
        ChatEdit_SendText(self)
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

    if #Chunks <= 3 then
        for _, Chunk in ipairs(Chunks) do
            SendFunc(Chunk, CurrentChatType, Lang, Target)
        end
        self:SetText("")
        self:ClearFocus()
        self:AddHistoryLine(TrimmedText)
        PratRememberChannel(self, CurrentChatType)
    else
        for i = 1, 3 do
            SendFunc(Chunks[i], CurrentChatType, Lang, Target)
        end

        local Remaining = {}
        for i = 4, #Chunks do
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
    -- Initialise all chat edit boxes.
    for i = 1, NUM_CHAT_WINDOWS do
        local EditBox = _G["ChatFrame"..i.."EditBox"]
        if EditBox then
            self:SetupEditBox(EditBox)
        end
    end
end

--- Hooks a Blizzard EditBox to add Yapper's long-message handling.
--- @param EditBox table The EditBox frame object.
function Chat:SetupEditBox(EditBox)
    -- Hook Blizzard edit boxes and swap the OnEnter script.
    if OriginalScriptHandlers[EditBox] then return end
    
    UnlockLimits(EditBox)
    
    -- Hook scripts for persistence
    EditBox:HookScript("OnShow", UnlockLimits)
    EditBox:SetHistoryLines(YapperTable.Defaults.Chat.MaxHistoryLines)
    EditBox:HookScript("OnEditFocusGained", UnlockLimits)
    EditBox:HookScript("OnEditFocusLost", ClearQueue)
    EditBox:HookScript("OnHide", function(self) 
        OriginalScriptHandlers[self] = nil
        PendingMessages[self] = nil
    end)

    -- Borrow the original script so we can still use it for short messages.
    OriginalScriptHandlers[EditBox] = EditBox:GetScript("OnEnterPressed")
    EditBox:SetScript("OnEnterPressed", OnEnterPressed)
end

function Chat:Cleanup()
    for EditBox, _ in pairs(OriginalScriptHandlers) do
        if not EditBox:IsShown() or not EditBox:GetParent() then
            OriginalScriptHandlers[EditBox] = nil
            PendingMessages[EditBox] = nil
        end
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
end

