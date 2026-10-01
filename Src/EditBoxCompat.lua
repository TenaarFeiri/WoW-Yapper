--[[
    Compatibility helpers for the overlay editbox.
    Provides GetChatType/GetChannelTarget/etc. so Blizzard treats the
    overlay like a normal chat box and avoids nil-method crashes.
    Also hooks InsertLink and ensures it routes to the active Yapper editor.
]]

local _, YapperTable = ...

local EditBox = YapperTable.EditBox
if not EditBox then
    return
end

-- Let Blizzard code query chat state from the overlay widget the
-- same way it would from a native ChatFrameEditBox.

local function GetCompatAttribute(box, key)
    if key == "chatType" then
        return EditBox.ChatType
    elseif key == "channelTarget" then
        return EditBox.ChatType == "CHANNEL" and EditBox.Target or nil
    elseif key == "tellTarget" then
        local ct = EditBox.ChatType
        return (ct == "WHISPER" or ct == "BN_WHISPER") and EditBox.Target or nil
    elseif key == "language" then
        return EditBox.Language
    end
    return nil
end

function YapperTable.InstallCompatMethods(box)
    if not box or box._yapperCompatInstalled then
        return
    end
    box._yapperCompatInstalled = true

    function box:GetChatType() return GetCompatAttribute(self, "chatType") end

    function box:GetChannelTarget() return GetCompatAttribute(self, "channelTarget") end

    function box:GetTellTarget() return GetCompatAttribute(self, "tellTarget") end

    function box:GetLanguage() return GetCompatAttribute(self, "language") end

    function box:GetAttribute(key) return GetCompatAttribute(self, key) end
    
    -- Parity Fields: direct access fields used by some addons.
    box.chatType = box:GetChatType() or "SAY"
    box.chatLanguage = box:GetLanguage() or "Common"

    -- Addons like TRP3 expect the active editbox to expose .chatFrame and
    -- .header. The shim redirects .editBox back to our box so TRP3's
    -- shift-click name replacement (ChatFrame.lua:766) targets Yapper's
    -- editor instead of Blizzard's ChatFrame1EditBox.
    if not box._yapperChatFrameShim then
        box._yapperChatFrameShim = setmetatable({}, {
            __index = function(_, key)
                if key == "editBox" then
                    return box
                end
                return _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME[key]
            end
        })
    end
    box.chatFrame = box._yapperChatFrameShim
    if not box.header then
        box.header = CreateFrame("Frame", nil, box)
    end

    -- No-op stubs: prevent nil-method crashes when ChatFrameUtil or addons
    -- manage Yapper as an active chat box.
    box.Deactivate = box.Deactivate or function() end
    box.UpdateHeader = box.UpdateHeader or function() end
    box.SetFocusRegionsShown = box.SetFocusRegionsShown or function() end
    box.UpdateNewcomerEditBoxHint = box.UpdateNewcomerEditBoxHint or function() end
    -- Deprecated wrappers like ChatEdit_SendText(editBox) drive Blizzard's
    -- SendText path, which expects these mixin methods. ParseText must be
    -- real (below); the rest stay harmless no-ops.
    box.OnPreSendText = box.OnPreSendText or function() end
    box.AddHistory = box.AddHistory or function() end

    -- Functional ParseText (feature parity, not pipeline hijacking).
    -- Blizzard's SendText -- which addons like Paste/PasteNG invoke via
    -- ChatEdit_SendText on the "active window" -- calls ParseText(1) BEFORE
    -- dispatching. Since GetActiveWindow hands those addons our overlay, a
    -- no-op ParseText would drop slash commands or send them as chat text.
    -- So: run slash lines through Blizzard's registry and clear the box so
    -- SendText sends nothing; leave plain text for SendText to dispatch
    -- verbatim via GetChatType()/languageID.
    function box:ParseText(send)
        -- Only act on the send path; parse-only calls (send ~= 1) are no-ops.
        if send ~= 1 then return end
        -- Canonical read: harmless on foreign boxes, required on ours.
        local text = YapperTable.Recolour.CanonicalText(self)
        if not text or text == "" then return end
        local trimmed = text:match("^%s*(.-)%s*$") or ""
        if trimmed:sub(1, 1) ~= "/" then return end -- plain text: SendText handles it
        -- Slash line: run through Blizzard's registry and clear the box so
        -- SendText sends nothing.
        if EditBox.ForwardSlashCommand then
            EditBox:ForwardSlashCommand(trimmed)
        end
        self:SetText("")
    end

    -- supportsSlashCommands = false keeps Blizzard's CHAT_FOCUS_OVERRIDE
    -- path out of slash-typed text ("/" key, "/w name"). With true, Blizzard
    -- would SetText("/") AND the physical keypress would fire OnChar on the
    -- focused overlay, producing "//". With false, slash text takes the
    -- normal path our Show() hook intercepts; non-slash content (item links,
    -- empty open) still flows through CHAT_FOCUS_OVERRIDE.
    box.supportsSlashCommands = false
end

-- Install on overlay at creation time.
local originalCreateOverlay = EditBox.CreateOverlay
function EditBox:CreateOverlay(...)
    originalCreateOverlay(self, ...)
    YapperTable.InstallCompatMethods(self.OverlayEdit)
end

-- Also install on Multiline at creation time if it exists.
local Multiline = YapperTable.Multiline
if Multiline then
    local originalCreateMultiline = Multiline.CreateFrame
    function Multiline:CreateFrame(...)
        originalCreateMultiline(self, ...)
        YapperTable.InstallCompatMethods(self.EditBox)
    end
end

-- Install immediately if components already exist (e.g. reload).
if EditBox.OverlayEdit then
    YapperTable.InstallCompatMethods(EditBox.OverlayEdit)
end
if Multiline and Multiline.EditBox then
    YapperTable.InstallCompatMethods(Multiline.EditBox)
end

-- Return Yapper's editor from Blizzard's active-window queries while we own
-- an editor, so paste/link addons work on it. Wrappers fall back to native
-- during lockdown or bypass so the overlay never enters Blizzard's
-- lockdown path.
local ENABLE_WINDOW_REPLACEMENTS = true

local origGetActiveWindow = ChatFrameUtil and ChatFrameUtil.GetActiveWindow
local origFocusActiveWindow = ChatFrameUtil and ChatFrameUtil.FocusActiveWindow
local compatGetActiveWindow
local compatFocusActiveWindow

if ENABLE_WINDOW_REPLACEMENTS and origGetActiveWindow then
    compatGetActiveWindow = function()
        local eb = YapperTable.EditBox
        local activeEditor = eb and eb.GetActiveEditor and eb:GetActiveEditor()
        if activeEditor then
            local bypass = eb._UserBypassingYapper and eb._UserBypassingYapper()
            local preShow = eb._preShowSuppressed
            if not bypass and not preShow and not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                return activeEditor
            end
        end
        return origGetActiveWindow()
    end
    ChatFrameUtil.GetActiveWindow = compatGetActiveWindow
    -- Also redirect the deprecated global when Blizzard shipped it
    -- (loadDeprecationFallbacks) so legacy addons see the overlay; never
    -- create it ourselves if the fallback wasn't loaded.
    if _G.ChatEdit_GetActiveWindow then
        _G.ChatEdit_GetActiveWindow = compatGetActiveWindow
    end
end

if ENABLE_WINDOW_REPLACEMENTS and origFocusActiveWindow then
    compatFocusActiveWindow = function()
        local eb = YapperTable.EditBox
        -- Focus the visible Yapper editor directly: Blizzard's path calls
        -- ActivateChat() which clears CHAT_FOCUS_OVERRIDE, undoing the
        -- active-editor migration.
        local activeEditor = eb and eb.GetActiveEditor and eb:GetActiveEditor()
        if activeEditor then
            local bypass = eb._UserBypassingYapper and eb._UserBypassingYapper()
            local preShow = eb._preShowSuppressed
            if not bypass and not preShow and not (YapperTable.Utils and YapperTable.Utils:IsChatLockdown()) then
                activeEditor:SetFocus()
                return -- Preserve the override for the active Yapper editor.
            end
        end
        return origFocusActiveWindow()
    end
    ChatFrameUtil.FocusActiveWindow = compatFocusActiveWindow
end

-- Enable/disable the wrappers. Native reply/deactivation must not run
-- through our tainted wrappers while secrets are active during lockdown, so
-- lifecycle callers disable before handoff and re-enable after recovery.
function EditBox:SetChatCompatibilityEnabled(enabled)
    if not ENABLE_WINDOW_REPLACEMENTS then return end
    if not ChatFrameUtil then return end
    if enabled then
        if compatGetActiveWindow then
            ChatFrameUtil.GetActiveWindow = compatGetActiveWindow
            if _G.ChatEdit_GetActiveWindow then
                _G.ChatEdit_GetActiveWindow = compatGetActiveWindow
            end
        end
        if compatFocusActiveWindow then
            ChatFrameUtil.FocusActiveWindow = compatFocusActiveWindow
        end
    else
        if origGetActiveWindow then
            ChatFrameUtil.GetActiveWindow = origGetActiveWindow
            if _G.ChatEdit_GetActiveWindow then
                _G.ChatEdit_GetActiveWindow = origGetActiveWindow
            end
        end
        if origFocusActiveWindow then
            ChatFrameUtil.FocusActiveWindow = origFocusActiveWindow
        end
    end
end




