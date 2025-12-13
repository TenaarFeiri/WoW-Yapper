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
local OriginalScriptHandlers = {} -- Store original Blizzard code here safely
local IsQuoteOpen = false

-- FUNCTIONS --

local function GetMetadata()
    return {C_AddOns.GetAddOnInfo(AddonName)} -- Return a table.
end

local function GetMetaAddonName()
    return GetMetadata()[2]
end

local function RecolourEmote(self, event, message, prefix, ...)
    -- Only colour emotes...
    -- This *shouldn't* interact with other addons attempting to recolour the chat. Theoretically...
    if prefix ~= "|Hplayer:" .. UnitName("player") .. "|h" then
        return
    end

    local WHITE_TAG = "|cffffffff"
    local RESET_TAG = "|r"
    local recoloredMessage = ""
    IsQuoteOpen = false 

    local args = {message, prefix, ...}

    for i = 1, #message do
        local char = string.sub(message, i, i)
        
        if char == '"' then
            if current_inQuote then
                recoloredMessage = recoloredMessage .. char .. RESET_TAG
                current_inQuote = false
            else
                recoloredMessage = recoloredMessage .. WHITE_TAG .. char
                current_inQuote = true
            end
        else
            recoloredMessage = recoloredMessage .. char
        end
    end
    
    -- Replace the original message text.
    args[1] = recoloredMessage 
    
    -- Finally, we kick it back to the game to enjoy.
    return false, unpack(args)
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

local function YapperOnEnter(self)
    local text = self:GetText()
    local len = string.len(text)
    
    -- Short message? Just let Blizzard's method do the thing.
    if len <= MaxStringLength then
        local original = OriginalScriptHandlers[self]
        if original then
            original(self)
        end
        return
    end
    
    -- If we're here, we are dealing with a longcat. Take over.
    local chatType = self:GetAttribute("chatType")
    local valid = (chatType == "SAY") or 
                  (chatType == "YELL") or 
                  (chatType == "PARTY") or 
                  (chatType == "RAID") or 
                  (chatType == "EMOTE") or
                  (chatType == "GUILD")

    -- If it's a channel we don't support, just truncate, post and complain.
    -- will preserve the whole original post in the history if truncated so it can be recovered with alt+up
    -- we will not split for public channels like General, Trade, etc., that's ridiculously spammy.
    if not valid then
        print("|cFFFF0000".. GetMetaAddonName() .. ":|r Text too long for "..(chatType or "?")..". Truncating.")
        self:SetText(string.sub(text, 1, MaxStringLength))
        -- Now that it is short, pass it to the original handler
        local original = OriginalScriptHandlers[self]
        if original then
            original(self)
        end
        return
    end

    -- It is Valid and Long: Split it!
    local lines = ChunkMessage(text, MaxStringLength)
    local lang = self:GetAttribute("language")
    local target = self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget")
    
    for i, line in ipairs(lines) do
        SendChatMessage(line, chatType, lang, target)
    end

    self:AddHistoryLine(text)
    self:SetText("")
    self:ClearFocus() -- Deselect the chat after a longtext.
end

-- SETUP
local function SetupEditBox(editBox)
    -- no double hooks
    if OriginalScriptHandlers[editBox] then return end
    UnlockLimits(editBox)
    
    -- Absolutely do not limit the un-limit.
    editBox:HookScript("OnShow", UnlockLimits)
    editBox:HookScript("OnEditFocusGained", UnlockLimits)

    -- Steal the Enter key and save to our table to avoid taint.
    OriginalScriptHandlers[editBox] = editBox:GetScript("OnEnterPressed")
    
    -- Then replace with our new script.
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
ChatRecolourFrame:SetScript("OnEvent", RecolourEmote)
