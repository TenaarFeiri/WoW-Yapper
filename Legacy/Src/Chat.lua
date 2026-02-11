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

-------------------------------------------------------------------------------------
-- POST QUEUE STATE (Gopher-style one-at-a-time confirmation)
--
-- How this works:
-- 1. User presses Enter (hardware event) → all chunks are queued
-- 2. We send ONLY the first chunk during the hardware event
-- 3. When CHAT_MSG_* fires confirming our message → we send the next chunk
-- 4. CHAT_MSG_* event handlers ARE valid hardware contexts for SendChatMessage!
-- 5. This guarantees perfect ordering - chunk N+1 only sends after N is confirmed
--
-- This is Gopher's "sophisticated post order verification" approach.
-------------------------------------------------------------------------------------

Chat.OutboundQueue = {}      -- Array of {text, type, lang, target} waiting to be sent
Chat.CurrentChunk = nil      -- The chunk we're currently waiting for confirmation
Chat.IsProcessing = false    -- True while we have pending messages
Chat.LastSendTime = 0        -- Timestamp of last successful send
Chat.PlayerName = nil        -- Cached player name for filtering chat events
Chat.PlayerRPName = nil      -- Cached TRP3 RP name (first name only) for filtering
Chat.ChunksSent = 0          -- Count of chunks sent in current batch
Chat.ChunksTotal = 0         -- Total chunks in current batch

-------------------------------------------------------------------------------------
-- BATCHING FOR SAY/YELL (Protected function workaround)
-- SAY and YELL in open world require hardware events. We batch messages:
-- - Send up to BATCH_SIZE chunks per Enter press
-- - If a chunk contains an item link, pause after it (links need hardware events)
-- - EMOTE and other types don't need batching, they fire automatically
-------------------------------------------------------------------------------------
Chat.BATCH_SIZE = nil            -- Set from config in Init()
Chat.BatchRemaining = 0          -- How many more chunks we can send in current batch
Chat.CurrentChatType = nil       -- Chat type of current queue (SAY, YELL, EMOTE, etc.)

-------------------------------------------------------------------------------------
-- STALL DETECTION (throttle handling)
-- If we're waiting too long for a confirmation, show a prompt for user to press Enter.
-- This handles cases where the server throttles us or drops messages.
-------------------------------------------------------------------------------------
Chat.StallTimer = nil            -- Timer that fires when we've been waiting too long
Chat.ContinueFrame = nil         -- UI frame for "Press Enter to continue" prompt
Chat.STALL_TIMEOUT = nil         -- Set from config in Init()
Chat.NeedsUserContinue = false   -- True when waiting for user to press Enter
Chat.BATCH_THROTTLE = nil        -- Set from config in Init()
Chat.LastBatchTime = 0           -- Timestamp of last SAY/YELL batch send

local Delineator = YapperTable.Config.Chat.DELINEATOR or " >> "
local Prefix = YapperTable.Config.Chat.PREFIX or ">> "

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
-- TRP3 INTEGRATION --

--- Gets the TRP3 RP first name for the player, if TRP3 is loaded.
--- TRP3 may display this name in chat instead of the character name.
--- @return string|nil The TRP3 first name, or nil if not available
function Chat:GetTRP3FirstName()
    -- Check if TRP3 API is available
    if not _G.TRP3_API then return nil end
    
    local ok, result = pcall(function()
        local data = _G.TRP3_API.profile.getData("player/characteristics")
        if data and data.FN and data.FN ~= "" then
            return data.FN
        end
        return nil
    end)
    
    if ok then return result end
    return nil
end

--- Caches player names (both real name and TRP3 RP name if available).
--- Call this when starting to process a queue.
function Chat:CachePlayerNames()
    -- Get real character name
    self.PlayerName = UnitName("player")
    
    -- Try to get TRP3 RP name
    self.PlayerRPName = self:GetTRP3FirstName()
    
    if self.PlayerRPName then
        YapperTable.Utils:VerbosePrint(string.format("Player names cached: '%s' (char), '%s' (TRP3)", 
            self.PlayerName or "nil", self.PlayerRPName))
    end
end

--- Checks if a sender name matches the player (either real name or TRP3 name).
--- @param sender string The sender name from the chat event
--- @return boolean True if this is us
function Chat:IsSenderMe(sender)
    if not sender then return false end
    
    -- Strip realm name if present ("Name-Realm" -> "Name")
    local senderName = sender:match("^([^-]+)") or sender
    
    -- Check against real character name
    local playerName = self.PlayerName and self.PlayerName:match("^([^-]+)") or self.PlayerName
    if senderName == playerName then
        return true
    end
    
    -- Check against TRP3 RP name (first name only)
    if self.PlayerRPName and senderName == self.PlayerRPName then
        return true
    end
    
    -- TRP3 might show colored name, try stripping color codes
    local strippedSender = senderName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if self.PlayerRPName and strippedSender == self.PlayerRPName then
        return true
    end
    
    return false
end

--- Checks if a chat type requires manual Enter presses (no auto-send on confirmation).
--- SAY/YELL/PARTY/RAID/INSTANCE in open world can't auto-send from CHAT_MSG events.
--- EMOTE works fine with auto-send.
--- @param chatType string The chat type (SAY, YELL, EMOTE, etc.)
--- @return boolean True if this chat type needs manual Enter for each batch
function Chat:NeedsManualContinue(chatType)
    -- EMOTE and GUILD work fine with auto-send from CHAT_MSG events
    if chatType == "EMOTE" or chatType == "GUILD" or chatType == "OFFICER" then
        return false
    end
    
    -- SAY, YELL, PARTY, RAID, INSTANCE_CHAT need manual Enter
    -- These trigger protected function errors when auto-sending from CHAT_MSG
    if chatType == "SAY" or chatType == "YELL" or chatType == "PARTY" 
       or chatType == "RAID" or chatType == "INSTANCE_CHAT" then
        -- In instances, we might be okay, but let's be safe
        return true
    end
    
    -- Default: assume manual is needed (safer)
    return true
end

--- Checks if a text contains an item link.
--- Item links require hardware events, so we pause batching after sending one.
--- @param text string The message text to check
--- @return boolean True if the text contains an item link
function Chat:ContainsItemLink(text)
    -- Item links look like: |Hitem:12345:...|h[Item Name]|h
    -- May be wrapped in color codes: |cff1eff00|Hitem:...|h[...]|h|r
    return text:find("|Hitem:") ~= nil
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
-- QUEUE FUNCTIONS (Gopher-style one-at-a-time confirmation) --

--- Clears the outbound queue and resets state.
--- Call this when disabling Yapper or on logout.
function Chat:ClearOutboundQueue()
    table.wipe(self.OutboundQueue)
    self.CurrentChunk = nil
    self.IsProcessing = false
    self.LastSendTime = 0
    self.ChunksSent = 0
    self.ChunksTotal = 0
    self.NeedsUserContinue = false
    -- Clear batching state
    self.BatchRemaining = 0
    self.CurrentChatType = nil
    -- Clear cached player names (fresh lookup on next send)
    self.PlayerName = nil
    self.PlayerRPName = nil
    -- Cancel timers
    if self.StallTimer then
        self.StallTimer:Cancel()
        self.StallTimer = nil
    end
    -- Hide continue prompt and disable escape handler
    self:HideContinuePrompt()
    self:DisableEscapeCancel()
    YapperTable.Utils:VerbosePrint("Outbound queue cleared.")
end

-------------------------------------------------------------------------------------
-- CONTINUE PROMPT UI
-- Shows a visual prompt when stalled. We hook ChatFrameUtil.OpenChat to detect
-- when the user presses Enter (or any chat-opening key), which gives us a valid
-- hardware event context to continue sending.
-------------------------------------------------------------------------------------

--- Creates the continue prompt frame (lazy initialization).
--- Positioned above the chat edit box for easy visibility.
--- This is just a visual indicator - the editbox itself handles Enter presses.
function Chat:CreateContinueFrame()
    if self.ContinueFrame then return end
    
    local frame = CreateFrame("Frame", "YapperContinueFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(380, 36)
    frame:Hide()
    
    -- Position above the chat edit box
    frame:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        local editBox = ChatFrame1EditBox
        if editBox then
            -- Anchor to bottom of chat frame, above where editbox appears
            local chatFrame = ChatFrame1
            if chatFrame then
                self:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", 0, -5)
                self:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 0, -5)
            else
                self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
            end
        else
            self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
        end
    end)
    
    -- Background with backdrop (may not be available in test env)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        if frame.SetBackdropColor then
            frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        end
        if frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(1, 0.8, 0, 1)
        end
    end
    
    -- Text with proper anchoring to prevent overflow
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("LEFT", frame, "LEFT", 12, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetTextColor(1, 0.82, 0)
    frame.text:SetWordWrap(false)
    
    self.ContinueFrame = frame
end

--- Shows the continue prompt with the given message.
--- @param message string The message to display
function Chat:ShowContinuePrompt(message)
    self:CreateContinueFrame()
    self.ContinueFrame.text:SetText(message or "Press [Enter] to continue...")
    self.ContinueFrame:Show()
    self.NeedsUserContinue = true
    -- Enable Escape to cancel
    self:EnableEscapeCancel()
    YapperTable.Utils:VerbosePrint("Showing continue prompt - press Enter to continue, Escape to cancel.")
end

--- Hides the continue prompt.
function Chat:HideContinuePrompt()
    if self.ContinueFrame then
        self.ContinueFrame:Hide()
    end
    self.NeedsUserContinue = false
    -- Don't disable Escape here - we want it active during the whole posting process
end

--- Called when we've been waiting too long for confirmation.
--- Shows the continue prompt.
function Chat:OnStallTimeout()
    if not self.CurrentChunk then return end
    if not self.IsProcessing then return end
    
    local remaining = #self.OutboundQueue + 1  -- +1 for CurrentChunk
    self:ShowContinuePrompt(string.format("Press [Enter] to continue (%d remaining)", remaining))
end

--- Resets the stall timer. Call this after every successful send or confirmation.
function Chat:ResetStallTimer()
    -- Cancel existing timer
    if self.StallTimer then
        self.StallTimer:Cancel()
        self.StallTimer = nil
    end
    
    -- Only set new timer if we're still processing
    if self.IsProcessing and self.CurrentChunk then
        self.StallTimer = C_Timer.NewTimer(self.STALL_TIMEOUT, function()
            self:OnStallTimeout()
        end)
    end
end

--- Called from OpenChat hook when user presses Enter (or any chat key) while stalled.
--- This is ONLY for the EMOTE/GUILD queue system, not for SAY/YELL PendingMessages.
--- @return boolean True if we handled the event and should suppress the chatbox
function Chat:OnUserContinue()
    -- Only handle if we're using the queue system (EMOTE/GUILD) and need user continue
    if not self.NeedsUserContinue then return false end
    if not self.IsProcessing then return false end  -- Not using queue system
    
    self:HideContinuePrompt()
    
    local needsManual = self:NeedsManualContinue(self.CurrentChatType)
    local SendFunc = YapperTable.SendChatMessageOverride or C_ChatInfo.SendChatMessage
    
    if needsManual then
        -- SAY/YELL/PARTY/RAID: Send entire batch in a loop while we have hardware context
        self.BatchRemaining = self.BATCH_SIZE
        YapperTable.Utils:VerbosePrint(string.format("User continued (hardware event), sending batch of up to %d...", self.BATCH_SIZE))
        
        -- If we have a stalled current chunk, send it first
        if self.CurrentChunk then
            local msgData = self.CurrentChunk
            self.BatchRemaining = self.BatchRemaining - 1
            SendFunc(msgData.text, msgData.type, msgData.lang, msgData.target)
            self.LastSendTime = GetTime()
            YapperTable.Utils:VerbosePrint(string.format("Re-sent stalled chunk %d/%d", self.ChunksSent, self.ChunksTotal))
            -- Note: We don't clear CurrentChunk here - wait for confirmation
        end
        
        -- Send remaining batch from queue (they'll stack and confirm in order)
        local batchSent = self.CurrentChunk and 1 or 0
        while self.BatchRemaining > 0 and #self.OutboundQueue > 0 do
            -- Check if current chunk has item link - if so, stop batching
            local nextChunk = self.OutboundQueue[1]
            if self:ContainsItemLink(nextChunk.text) then
                YapperTable.Utils:VerbosePrint("Next chunk has item link, stopping batch early.")
                break
            end
            
            -- Don't send if we already have a current chunk waiting
            if self.CurrentChunk then
                -- Already sent one, rest will be triggered by confirmations
                break
            end
            
            -- Take from queue and send
            local msgData = table.remove(self.OutboundQueue, 1)
            self.CurrentChunk = msgData
            self.ChunksSent = self.ChunksSent + 1
            self.BatchRemaining = self.BatchRemaining - 1
            batchSent = batchSent + 1
            
            SendFunc(msgData.text, msgData.type, msgData.lang, msgData.target)
            self.LastSendTime = GetTime()
            YapperTable.Utils:VerbosePrint(string.format("Sent chunk %d/%d (batch)", self.ChunksSent, self.ChunksTotal))
        end
        
        self:ResetStallTimer()
    else
        -- EMOTE/GUILD: Just send one, confirmations will auto-send rest
        YapperTable.Utils:VerbosePrint("User continued (hardware event), resuming...")
        
        if self.CurrentChunk then
            local msgData = self.CurrentChunk
            SendFunc(msgData.text, msgData.type, msgData.lang, msgData.target)
            self.LastSendTime = GetTime()
            self:ResetStallTimer()
        else
            self:SendNextChunk()
        end
    end
    
    return true  -- We handled the event, suppress chatbox opening
end

--- Returns the current queue state for debugging.
--- @return table Status info: queueLength, isProcessing, chunksSent, chunksTotal
function Chat:GetQueueStatus()
    return {
        queueLength = #self.OutboundQueue,
        isProcessing = self.IsProcessing,
        chunksSent = self.ChunksSent,
        chunksTotal = self.ChunksTotal,
        currentChunk = self.CurrentChunk,
        lastSendTime = self.LastSendTime
    }
end

--- Adds a message to the outbound queue.
--- @param text string The message text
--- @param chatType string SAY, YELL, EMOTE, etc.
--- @param lang string|nil Language override (usually nil)
--- @param target string|nil Target for whispers/channels
function Chat:EnqueueMessage(text, chatType, lang, target)
    table.insert(self.OutboundQueue, {
        text = text,
        type = chatType,
        lang = lang,
        target = target
    })
end

--- Sends the next chunk in the queue. Can be called from:
--- 1. OnEnterPressed (hardware event) - to send the first chunk
--- 2. OnChatMessageReceived (CHAT_MSG_* event handler) - to send subsequent chunks
--- Both contexts are valid for SendChatMessage!
function Chat:SendNextChunk()
    -- Nothing left to send?
    if #self.OutboundQueue == 0 then
        if self.IsProcessing then
            -- We were processing and now we're done
            if self.StallTimer then
                self.StallTimer:Cancel()
                self.StallTimer = nil
            end
            self:HideContinuePrompt()
            self:DisableEscapeCancel()
            self.IsProcessing = false
            self.CurrentChunk = nil
            YapperTable.Utils:VerbosePrint(string.format("All %d chunks confirmed and sent!", self.ChunksTotal))
        end
        return
    end
    
    -- Already waiting for a confirmation? Don't send another.
    if self.CurrentChunk then
        return
    end
    
    -- Cache player names for event filtering (includes TRP3 RP name if available)
    if not self.PlayerName then
        self:CachePlayerNames()
    end
    
    -- Take the first chunk from queue
    local msgData = table.remove(self.OutboundQueue, 1)
    self.CurrentChunk = msgData
    self.ChunksSent = self.ChunksSent + 1
    
    -- Decrement batch counter for SAY/YELL batching
    if self.BatchRemaining > 0 then
        self.BatchRemaining = self.BatchRemaining - 1
    end
    
    -- Use SendChatMessageOverride if available (bypasses Gopher), otherwise C_ChatInfo.SendChatMessage
    local SendFunc = YapperTable.SendChatMessageOverride or C_ChatInfo.SendChatMessage
    
    -- Send it!
    local msgID = SendFunc(msgData.text, msgData.type, msgData.lang, msgData.target)
    self.LastSendTime = GetTime()
    
    if msgID then
        YapperTable.Utils:VerbosePrint(string.format("Sent chunk %d/%d (batch: %d left), awaiting confirmation...", 
            self.ChunksSent, self.ChunksTotal, self.BatchRemaining))
    else
        -- Throttled - message is still queued server-side, we still wait for confirmation
        YapperTable.Utils:VerbosePrint(string.format("Sent chunk %d/%d (throttled, batch: %d left), awaiting confirmation...", 
            self.ChunksSent, self.ChunksTotal, self.BatchRemaining))
    end
    
    -- Start/reset stall timer - if we don't get confirmation in time, prompt user
    self:ResetStallTimer()
end

--- Starts processing the queue. Call this from OnEnterPressed (hardware event).
--- For chat types that need manual continue (SAY/YELL/PARTY/RAID), we batch chunks.
--- For EMOTE/GUILD, we auto-send on confirmation.
function Chat:FlushQueue()
    if #self.OutboundQueue == 0 then
        YapperTable.Utils:VerbosePrint("Queue is empty, nothing to send.")
        return
    end
    
    self.IsProcessing = true
    self.ChunksSent = 0
    self.ChunksTotal = #self.OutboundQueue
    
    -- Get chat type from first queued message (all should be same type)
    self.CurrentChatType = self.OutboundQueue[1] and self.OutboundQueue[1].type
    
    -- Set up batching for chat types that need manual Enter presses
    if self:NeedsManualContinue(self.CurrentChatType) then
        self.BatchRemaining = self.BATCH_SIZE
        YapperTable.Utils:VerbosePrint(string.format("Starting to send %d chunks (%s: %d per Enter, then prompt)...", 
            self.ChunksTotal, self.CurrentChatType, self.BATCH_SIZE))
    else
        -- EMOTE/GUILD: auto-send on confirmation, no batch limit
        self.BatchRemaining = 9999
        YapperTable.Utils:VerbosePrint(string.format("Starting to send %d chunks (%s: auto-send on confirm)...", 
            self.ChunksTotal, self.CurrentChatType))
    end
    
    -- Send only the first chunk - the rest will be sent as confirmations come in
    self:SendNextChunk()
end

--- Called when we see our own message in a CHAT_MSG event.
--- If it matches what we sent, we confirm it and send the next chunk.
--- CRITICAL: CHAT_MSG_* events are NOT hardware events in open world for SAY/YELL!
--- For those chat types, we need to batch and prompt for Enter between batches.
--- @param text string The message text from the event
--- @param chatType string The chat type (SAY, EMOTE, etc.)
--- @param sender string The sender name
function Chat:OnChatMessageReceived(text, chatType, sender)
    -- Ignore if not from us (checks both real name and TRP3 RP name)
    if not self:IsSenderMe(sender) then 
        -- Only log when actively processing (reduces spam)
        if self.IsProcessing then
            YapperTable.Utils:VerbosePrint(string.format("Ignoring message from '%s' (not us: '%s' / '%s')", 
                sender or "nil", self.PlayerName or "nil", self.PlayerRPName or "nil"))
        end
        return 
    end
    
    -- Ignore if we're not waiting for a confirmation
    if not self.CurrentChunk then return end
    
    -- Debug: log what we're comparing
    YapperTable.Utils:VerbosePrint(string.format("Comparing received text (%d chars) vs sent (%d chars)", 
        #text, #self.CurrentChunk.text))
    
    -- Check if this matches the chunk we're waiting for
    if self.CurrentChunk.text == text then
        -- Check if this chunk had an item link (need to pause after it for EMOTE too)
        local hadItemLink = self:ContainsItemLink(text)
        
        -- Confirmed! Clear current
        YapperTable.Utils:VerbosePrint(string.format("Chunk %d/%d confirmed!%s", 
            self.ChunksSent, self.ChunksTotal,
            hadItemLink and " (contains item link)" or ""))
        self.CurrentChunk = nil
        
        -- Hide continue prompt if it was showing
        self:HideContinuePrompt()
        
        -- Check if there's more to send
        if #self.OutboundQueue == 0 then
            -- All done!
            self:SendNextChunk()  -- This will handle the "all done" cleanup
            return
        end
        
        -- Decide whether to auto-send or prompt based on chat type
        local needsManual = self:NeedsManualContinue(self.CurrentChatType)
        
        if needsManual then
            -- SAY/YELL/PARTY/RAID: Check batch remaining before prompting
            -- Item link forces a pause regardless of batch
            if hadItemLink then
                YapperTable.Utils:VerbosePrint("Pausing after item link in batch.")
                self.BatchRemaining = 0  -- Force prompt
                self:ShowBatchPrompt()
            elseif self.BatchRemaining > 0 then
                -- Still have room in this batch, send next chunk
                YapperTable.Utils:VerbosePrint(string.format("Batch has %d remaining, auto-sending next.", self.BatchRemaining))
                self:SendNextChunk()
            else
                -- Batch exhausted, need user to press Enter
                YapperTable.Utils:VerbosePrint("Batch exhausted - showing prompt.")
                self:ShowBatchPrompt()
            end
        else
            -- EMOTE/GUILD: Auto-send, unless item link
            if hadItemLink then
                YapperTable.Utils:VerbosePrint("Pausing after item link - requires hardware event.")
                self:ShowBatchPrompt()
            else
                -- Auto-send next chunk
                self:SendNextChunk()
            end
        end
        return
    end
    
    -- Debug: show first 50 chars of each for comparison
    YapperTable.Utils:VerbosePrint(string.format("NO MATCH - received: '%s...'", text:sub(1, 50)))
    YapperTable.Utils:VerbosePrint(string.format("NO MATCH - expected: '%s...'", self.CurrentChunk.text:sub(1, 50)))
end

--- Shows the batch prompt with remaining chunk count.
function Chat:ShowBatchPrompt()
    local remaining = #self.OutboundQueue
    if remaining > 0 then
        self:ShowContinuePrompt(string.format("Press [Enter] to continue (%d remaining) / [Esc] to cancel", remaining))
    end
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
    
    -- Tokenization: Split text into atomic tokens that shouldn't be broken
    -- This includes escape sequences AND full hyperlinks (item links, spell links, etc.)
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
        elseif NextChar == "H" then
            -- Hyperlink: |H<type>:<data>|h[display text]|h
            -- Find the closing |h after the display text
            -- Pattern: |H....|h[....]|h  (the display text is in brackets)
            local linkEnd = Text:find("|h", Start + 2)  -- Find first |h (end of link data)
            if linkEnd then
                -- Now find the closing |h after the display text
                local displayEnd = Text:find("|h", linkEnd + 2)
                if displayEnd then
                    TagEnd = displayEnd + 1  -- Include the closing |h
                else
                    TagEnd = linkEnd + 1  -- Malformed, just include up to first |h
                end
            end
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

    -- Clear any pending SAY/YELL messages for this editbox
    if Chat.PendingMessages and Chat.PendingMessages[self] then
        local remaining = #Chat.PendingMessages[self].chunks
        Chat.PendingMessages[self] = nil
        if remaining > 0 then
            YapperTable.Utils:VerbosePrint(string.format("Cleared %d pending chunks (focus lost).", remaining))
        end
    end

    -- Also clean up if Editbox is being destroyed.
    if not self:IsShown() or not self:GetParent() then
        OriginalScriptHandlers[self] = nil
    end
end

--- Called when user presses Escape in the editbox - cancels pending SAY/YELL
local function OnEscapePressed(self)
    -- Check if we have pending messages for this editbox
    if Chat.PendingMessages and Chat.PendingMessages[self] then
        local remaining = #Chat.PendingMessages[self].chunks
        Chat.PendingMessages[self] = nil
        self:SetText("")
        YapperTable.Utils:Print(string.format("Posting cancelled. %d chunks discarded.", remaining))
        YapperTable.Utils:VerbosePrint("SAY/YELL posting cancelled by Escape.")
        -- Don't clear focus - let normal Escape behavior handle that
    end
end

local function PratRememberChannel(EditBox, ChannelType)
    if not _G.ChatTypeInfo then return end
    if not IsInGroup() and (ChannelType == "PARTY" or ChannelType == "RAID" or ChannelType == "INSTANCE") then return end
    if type(ChannelType) == "string" and _G.ChatTypeInfo and _G.ChatTypeInfo[ChannelType] and _G.ChatTypeInfo[ChannelType].sticky == 1 then
        EditBox:SetAttribute("chatType", ChannelType)
    end
end

--- Helper to add text to both editbox history and persistent storage.
--- @param EditBox table The editbox frame
--- @param Text string The text to add to history
local function AddToHistory(EditBox, Text)
    EditBox:AddHistoryLine(Text)
    -- Also save to persistent history.
    if YapperTable.History then
        YapperTable.History:AddChatHistory(Text)
        -- Clear undo buffer since we successfully sent.
        YapperTable.History:ClearUndoBuffer(EditBox)
    end
end

local function OnEnterPressed(self)
    if YapperTable.YAPPER_DISABLED then
        -- If Yapper is overridden, do nothing. Someone
        -- may have overridden it in the middle of a post.
        return
    end
    
    local SendFunc = YapperTable.SendChatMessageOverride or C_ChatInfo.SendChatMessage
    
    -- Store current chat type for Prat compatibility.
    local CurrentChatType = self:GetAttribute("chatType")
    
    -----------------------------------------------------------------------------
    -- PENDING QUEUE CONTINUATION
    -- If we have pending messages for THIS editbox, continue sending them.
    -- This happens when user presses Enter to continue a long post.
    -----------------------------------------------------------------------------
    if Chat.PendingMessages and Chat.PendingMessages[self] then
        local data = Chat.PendingMessages[self]
        
        -- Throttle: ignore Enter if less than BATCH_THROTTLE seconds since last batch
        local now = GetTime()
        if (now - Chat.LastBatchTime) < Chat.BATCH_THROTTLE then
            YapperTable.Utils:VerbosePrint("Throttled - wait " .. Chat.BATCH_THROTTLE .. " second(s) between batches.")
            return
        end
        Chat.LastBatchTime = now
        
        -- Send up to BATCH_SIZE chunks in this hardware event
        local sentCount = 0
        while #data.chunks > 0 and sentCount < Chat.BATCH_SIZE do
            local chunk = table.remove(data.chunks, 1)
            SendFunc(chunk, data.chatType, data.lang, data.target)
            sentCount = sentCount + 1
            
            -- If this chunk has an item link, stop after it
            if Chat:ContainsItemLink(chunk) and #data.chunks > 0 then
                YapperTable.Utils:VerbosePrint("Paused after item link chunk.")
                break
            end
        end
        
        YapperTable.Utils:VerbosePrint(string.format("Sent %d chunks, %d remaining.", sentCount, #data.chunks))
        
        -- Check if done
        if #data.chunks == 0 then
            Chat.PendingMessages[self] = nil
            self:SetText("")
            self:ClearFocus()
            YapperTable.Utils:VerbosePrint("All SAY/YELL chunks sent!")
        else
            -- Update prompt with remaining count
            self:SetText(string.format("(%d remaining - Enter to continue, Esc to cancel)", #data.chunks))
            self:HighlightText()
            self:SetFocus()
        end
        return
    end
    
    -----------------------------------------------------------------------------
    -- NEW MESSAGE PROCESSING
    -----------------------------------------------------------------------------
    local Text = self:GetText()
    local TrimmedText = YapperTable.Utils:Trim(Text)
    if string.len(TrimmedText) == 0 then
        self:ClearFocus()
        PratRememberChannel(self, CurrentChatType)
        return
    end
    local Limit = YapperTable.Config.Chat.CHARACTER_LIMIT

    -- Commands go to ChatEdit_SendText (slash commands like /dance, /who, etc.)
    if string.sub(TrimmedText, 1, 1) == "/" then
        ChatEdit_SendText(self)
        AddToHistory(self, TrimmedText)
        PratRememberChannel(self, CurrentChatType)
        -- ChatEdit_SendText should handle focus, but ensure we're closed.
        if self:IsShown() then
            self:SetText("")
            self:ClearFocus()
        end
        return
    end

    -- Whispers don't support splitting. Just truncate if too long.
    if CurrentChatType == "WHISPER" then
        if string.len(TrimmedText) > Limit then
            AddToHistory(self, TrimmedText)
            TrimmedText = string.sub(TrimmedText, 1, Limit)
            YapperTable.Error:PrintError("CHAT_WHISPER_TRUNCATED", Limit)
        end
        SendFunc(TrimmedText, CurrentChatType, self:GetAttribute("language"), self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget"))
        self:SetText("")
        self:ClearFocus()
        PratRememberChannel(self, CurrentChatType)
        return
    end

    -- Short messages: just send directly, no queue needed.
    if string.len(TrimmedText) <= Limit then
        SendFunc(TrimmedText, CurrentChatType, self:GetAttribute("language"), self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget"))
        self:SetText("")
        self:ClearFocus()
        AddToHistory(self, TrimmedText)
        PratRememberChannel(self, CurrentChatType)
        return
    end
    
    -- Check if chat type is supported for splitting.
    -- We only split SAY, YELL, PARTY, RAID, EMOTE, GUILD.
    local Valid = (CurrentChatType == "SAY") or (CurrentChatType == "YELL") or (CurrentChatType == "PARTY") or 
                  (CurrentChatType == "RAID") or (CurrentChatType == "EMOTE") or (CurrentChatType == "GUILD") or
                  (CurrentChatType == "INSTANCE_CHAT") or (CurrentChatType == "RAID_WARNING")

    if not Valid then
        YapperTable.Error:PrintError("BAD_STRING", "Unsupported chat type: " .. (CurrentChatType or "unknown"))
        self:SetText(string.sub(Text, 1, Limit))
        local Original = OriginalScriptHandlers[self]
        if Original then Original(self) end
        return
    end

    -- Long message: split it into chunks.
    local Chunks = Chat:ProcessPost(TrimmedText, Limit)
    local Lang = self:GetAttribute("language")
    local Target = self:GetAttribute("tellTarget") or self:GetAttribute("channelTarget")
    
    YapperTable.Utils:VerbosePrint("Split into " .. #Chunks .. " chunks.")
    AddToHistory(self, TrimmedText)
    
    -- EMOTE/GUILD/OFFICER: Use confirmation-based queue for guaranteed ordering
    -- These don't need hardware events, so CHAT_MSG_* confirmation works perfectly
    if CurrentChatType == "EMOTE" or CurrentChatType == "GUILD" or CurrentChatType == "OFFICER" then
        -- Queue all chunks
        for _, chunk in ipairs(Chunks) do
            Chat:EnqueueMessage(chunk, CurrentChatType, Lang, Target)
        end
        
        -- Clear editbox and start the queue
        self:SetText("")
        self:ClearFocus()
        
        -- Use the confirmation-based queue system
        YapperTable.Utils:VerbosePrint("Queued " .. #Chunks .. " " .. CurrentChatType .. " chunks for confirmed sending.")
        Chat:FlushQueue()
        PratRememberChannel(self, CurrentChatType)
        return
    end
    
    -----------------------------------------------------------------------------
    -- SAY/YELL/PARTY/RAID: Need hardware events, send in batches
    -----------------------------------------------------------------------------
    -- Record batch time for throttling
    Chat.LastBatchTime = GetTime()
    
    -- Send first batch immediately (up to BATCH_SIZE chunks)
    local sentCount = 0
    local remaining = {}
    
    for i, chunk in ipairs(Chunks) do
        if sentCount < Chat.BATCH_SIZE then
            SendFunc(chunk, CurrentChatType, Lang, Target)
            sentCount = sentCount + 1
            
            -- If this chunk has an item link, stop sending more in this batch
            if Chat:ContainsItemLink(chunk) and i < #Chunks then
                YapperTable.Utils:VerbosePrint("Paused batch after item link.")
                -- Queue remaining chunks
                for j = i + 1, #Chunks do
                    table.insert(remaining, Chunks[j])
                end
                break
            end
        else
            -- Queue remaining chunks
            table.insert(remaining, chunk)
        end
    end
    
    YapperTable.Utils:VerbosePrint("Sent " .. sentCount .. " chunks in first batch.")
    
    -- If all chunks sent, we're done
    if #remaining == 0 then
        self:SetText("")
        self:ClearFocus()
        YapperTable.Utils:VerbosePrint("All chunks sent!")
        PratRememberChannel(self, CurrentChatType)
        return
    end
    
    -- Store remaining chunks for continuation
    if not Chat.PendingMessages then
        Chat.PendingMessages = {}
    end
    
    Chat.PendingMessages[self] = {
        chunks = remaining,
        chatType = CurrentChatType,
        lang = Lang,
        target = Target
    }
    
    -- Show prompt IN the editbox and keep focus - this IS our hardware event capture
    -- Don't use ContinueFrame for SAY/YELL since the editbox itself handles Enter
    self:SetText(string.format("(%d remaining - Enter to continue, Esc to cancel)", #remaining))
    self:HighlightText()
    self:SetFocus()
    
    -- Don't call original handler - we want to keep focus
end

-------------------------------------------------------------------------------------
-- OpenChat Hook - This is the key to getting a hardware event context!
-- When the user presses Enter (or any chat-opening key like /), this hook fires
-- BEFORE the chat edit box opens. If we're waiting for user continuation, we
-- intercept it here and resume sending.
-------------------------------------------------------------------------------------
local function OnOpenChatHook()
    -- If we're waiting for user to continue, handle it here
    if Chat:OnUserContinue() then
        -- We handled it - hide the chatbox that's about to open
        -- The chatbox opens after this hook, so we hide it on the next frame
        C_Timer.After(0, function()
            if ACTIVE_CHAT_EDIT_BOX then
                ACTIVE_CHAT_EDIT_BOX:Hide()
            end
        end)
    end
end

-------------------------------------------------------------------------------------
-- Escape Key Handler - Allows user to cancel an in-progress post
-------------------------------------------------------------------------------------
local EscapeFrame = nil

local function CreateEscapeHandler()
    if EscapeFrame then return end
    
    EscapeFrame = CreateFrame("Frame", "YapperEscapeHandler", UIParent)
    EscapeFrame:EnableKeyboard(true)
    EscapeFrame:SetPropagateKeyboardInput(true)
    EscapeFrame:Hide()
    
    EscapeFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- Cancel the post
            self:SetPropagateKeyboardInput(false)  -- Consume this Escape
            Chat:CancelPosting()
        else
            -- Let other keys through
            self:SetPropagateKeyboardInput(true)
        end
    end)
end

--- Shows the escape handler frame (enables Escape to cancel)
function Chat:EnableEscapeCancel()
    CreateEscapeHandler()
    EscapeFrame:Show()
end

--- Hides the escape handler frame
function Chat:DisableEscapeCancel()
    if EscapeFrame then
        EscapeFrame:Hide()
        EscapeFrame:SetPropagateKeyboardInput(true)
    end
end

--- Cancels the current posting operation and clears the queue.
function Chat:CancelPosting()
    -- Check if we have any pending messages
    local hasPending = false
    local discardedCount = 0
    
    if self.PendingMessages then
        for editBox, data in pairs(self.PendingMessages) do
            if data and data.chunks then
                discardedCount = discardedCount + #data.chunks
                hasPending = true
            end
            -- Clear the editbox
            if editBox and editBox.SetText then
                editBox:SetText("")
                editBox:ClearFocus()
            end
        end
        self.PendingMessages = {}
    end
    
    -- Also clear the old queue system if anything is there
    if self.IsProcessing then
        discardedCount = discardedCount + #self.OutboundQueue + (self.CurrentChunk and 1 or 0)
        hasPending = true
        self:ClearOutboundQueue()
    end
    
    if not hasPending then return end
    
    YapperTable.Utils:VerbosePrint(string.format("Posting cancelled by user. %d chunks discarded.", discardedCount))
    
    -- Print a user-visible message
    if YapperTable.Utils and YapperTable.Utils.Print then
        YapperTable.Utils:Print(string.format("Posting cancelled. %d chunks discarded.", discardedCount))
    end
    
    self:HideContinuePrompt()
    self:DisableEscapeCancel()
end

function Chat:Init()
    Chat:Cleanup()
    -- Clear any leftover queue state and handlers on init.
    table.wipe(OriginalScriptHandlers)
    Chat:ClearOutboundQueue()
    
    -- Load config values
    self.BATCH_SIZE = YapperTable.Config.Chat.BATCH_SIZE or 3
    self.BATCH_THROTTLE = YapperTable.Config.Chat.BATCH_THROTTLE or 1.0
    self.STALL_TIMEOUT = YapperTable.Config.Chat.STALL_TIMEOUT or 1.0
    
    -- Hook ChatFrameUtil.OpenChat to get hardware event context for continues
    -- This fires when user presses Enter or any chat-opening key
    if ChatFrameUtil and ChatFrameUtil.OpenChat and not self.OpenChatHooked then
        hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChatHook)
        self.OpenChatHooked = true
        YapperTable.Utils:VerbosePrint("Hooked ChatFrameUtil.OpenChat for continue prompts.")
    end
    
    -- Initialise all chat edit boxes.
    -- WoW has NUM_CHAT_WINDOWS (default 10) chat frames for different tabs/windows.
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
    EditBox:HookScript("OnEscapePressed", OnEscapePressed)
    EditBox:HookScript("OnHide", function(self) 
        Chat:Cleanup()
    end)
    
    -- Hook history system for undo/redo and persistent chat history.
    if YapperTable.History then
        YapperTable.History:HookEditbox(EditBox)
    end

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
    -- Clear our tracking tables and queue.
    table.wipe(OriginalScriptHandlers)
    Chat:ClearOutboundQueue()
    YapperTable.Utils:VerbosePrint("Chat EditBoxes restored to Blizzard defaults.")
end


