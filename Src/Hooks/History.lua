--[[
    Hooks/History.lua
    History navigation (up/down arrow keys).
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore
local ResolveChannelName = Core.ResolveChannelName

-- Re-localise Lua globals.
local type  = type
local ipairs = ipairs
local tonumber = tonumber
local math_max = math.max
local math_min = math.min

-- ---------------------------------------------------------------------------
-- History navigation
-- ---------------------------------------------------------------------------

function EditBox:NavigateHistory(direction)
    -- Build history snapshot on first press.
    if not self.HistoryCache then
        self.HistoryCache = {}
        if YapperTable.History and YapperTable.History.GetChatHistory then
            self.HistoryCache = YapperTable.History:GetChatHistory() or {}
        elseif _G.YapperLocalHistory and _G.YapperLocalHistory.chatHistory then
            local saved = _G.YapperLocalHistory.chatHistory
            if type(saved) == "table" then
                if saved.global then
                    for _, v in ipairs(saved.global) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                else
                    for _, v in ipairs(saved) do
                        self.HistoryCache[#self.HistoryCache + 1] = v
                    end
                end
            end
        end
        self.HistoryIndex = #self.HistoryCache + 1
    end

    local cache = self.HistoryCache
    if #cache == 0 then return end

    local newIdx = (self.HistoryIndex or (#cache + 1)) + direction
    newIdx = math_max(1, math_min(newIdx, #cache + 1))

    if newIdx == self.HistoryIndex then return end

    -- Leaving the bottom slot: stash the in-progress draft (text plus the
    -- channel context it was being written in) so navigating back down
    -- restores it instead of wiping it.
    if self.HistoryIndex == #cache + 1 then
        self.HistoryDraft = {
            text     = YapperTable.Recolour.CanonicalText(self.OverlayEdit),
            chatType = self.ChatType,
            target   = self.Target,
            channel  = self.ChannelName,
        }
    end
    self.HistoryIndex = newIdx

    if newIdx > #cache then
        local draft = self.HistoryDraft
        self.HistoryDraft = nil
        local text = (draft and draft.text) or ""
        self.OverlayEdit:SetText(text)
        self.OverlayEdit:SetCursorPosition(#text)
        if draft then
            self.ChatType = draft.chatType
            self.Target = draft.target
            self.ChannelName = draft.channel
            if self.RefreshLabel then self:RefreshLabel() end
        end
    else
        local item = cache[newIdx]
        local text = ""
        local chatType = nil
        local target = nil

        if type(item) == "table" then
            text = item.text or ""
            chatType = item.chatType
            target = item.target
        else
            text = item or ""
        end

        self.OverlayEdit:SetText(text)
        self.OverlayEdit:SetCursorPosition(#text)

        -- Context switching: restore channel if recorded.
        if chatType then
            self.ChatType = chatType
            self.Target = target

            if chatType == "CHANNEL" and target then
                local num = tonumber(target)
                if num then
                    self.ChannelName = ResolveChannelName(num)
                end
            else
                self.ChannelName = nil
            end
            self:RefreshLabel()
        end
        -- If no chatType (legacy or slash command), keep current channel.
    end
end
