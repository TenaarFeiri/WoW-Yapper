local _, YapperTable = ...
local EditBox = YapperTable.EditBox
function EditBox:_IMPushActive(eb)
    if not eb then return end
    local history = self._imWindowHistory
    if history[#history] ~= eb then
        -- Remove any existing entry for this editbox further down the stack
        -- to keep it clean (same window shouldn't appear twice).
        for i = #history, 1, -1 do
            if history[i] == eb then
                table.remove(history, i)
                break
            end
        end
        history[#history + 1] = eb
    end
    self._lastActiveIMEditBox = eb
end

--- Restore the remembered channel state for a chat frame from _tabChannelMemory.
--- If Yapper is open the switch is applied immediately; otherwise it is stashed
--- in _pendingTabSwitch to be consumed on the next open.
function EditBox:_IMApplyWindowMemory(chatFrame)
    if not chatFrame then return end
    -- Whisper frames: use the tab's live routing.  ResolveWhisperFrameTarget
    -- additionally recovers BN_WHISPER |K-token/secret chatTargets as a
    -- numeric BNet account ID (plain SanitizeTarget must reject those).
    local wtType, wtTarget = self:ResolveWhisperFrameTarget(chatFrame)
    if wtType and wtTarget then
        self._pendingTabSwitch = {
            chatType  = wtType,
            target    = wtTarget,
            chatFrame = chatFrame,
            editBox   = chatFrame.editBox,
        }
        return
    end
    -- Non-whisper: restore from session memory.
    local key = chatFrame.GetName and chatFrame:GetName()
    local mem = key and self._tabChannelMemory and self._tabChannelMemory[key]
    if mem and mem.chatType then
        self._pendingTabSwitch = {
            chatType    = mem.chatType,
            target      = mem.target,
            channelName = mem.channelName,
            language    = mem.language,
            chatFrame   = chatFrame,
            editBox     = chatFrame.editBox,
        }
    end
end

--- Pop the given editbox off the IM active window history stack and restore
--- the previous entry as the active window.
function EditBox:_IMPopActive(eb)
    if not eb then return end
    local history = self._imWindowHistory
    -- Remove this editbox from the stack (wherever it is).
    for i = #history, 1, -1 do
        if history[i] == eb then
            table.remove(history, i)
            break
        end
    end
    -- Restore the new top as active (fall back to ChatFrame1EditBox if empty).
    local top = history[#history]
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
        or _G["ChatFrame1EditBox"]
    self._lastActiveIMEditBox = top
end
