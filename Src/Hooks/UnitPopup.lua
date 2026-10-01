--[[
    Hooks/UnitPopup.lua
    Menu-based whisper interception via the modern Menu API (Menu.ModifyMenu).

    Replaces the old UnitPopupWhisperButtonMixin.OnClick override, which tainted
    the entire unit-popup menu: Blizzard's secure menu generator reads OnClick
    off the mixin table (GenerateClosure in CreateMenuDescription), so an
    addon-written OnClick tainted every element built after the Whisper entry
    -- including protected actions like Copy Character Name (CopyToClipboard)
    and Set Focus, which then got blocked and attributed to Yapper.

    Menu.ModifyMenu is Blizzard's sanctioned addon customization surface. Our
    callback runs behind a securecallfunction boundary AFTER the secure
    generator pass has finished, and element descriptions are per-element
    proxies: replacing one element's responder taints only that element's
    click execution. Whispering is not a protected action, so a tainted
    whisper click is harmless and every other item keeps its pristine
    responder.

    See Documentation/UnitPopupWhisper.md for the full write-up.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local Utils   = YapperTable.Utils

-- Re-localise Lua globals.
local type     = type
local ipairs   = ipairs
local tostring = tostring

-- Root-menu tags (format "MENU_UNIT_<which>") whose menus can host a Whisper
-- button. Registering a tag whose menu has none is a harmless no-op, so the
-- list favours coverage over precision. BNet menus (BN_FRIEND*) go through
-- the same responder swap (see OpenWhisperFromUnitMenu); non-menu BNet
-- whispers (hyperlink handlers, social UI) still hit the SendBNetTell
-- hooksecurefunc in 30_ChatFrameHooks.lua.
local WHISPER_MENU_TAGS = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_GUILD",
    "MENU_UNIT_GUILD_OFFLINE",
    "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_TARGET",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_RAF_RECRUIT",
    "MENU_UNIT_RECENT_ALLY",
    "MENU_UNIT_NEIGHBORHOOD_ROSTER",
    "MENU_UNIT_BN_FRIEND",
    "MENU_UNIT_BN_FRIEND_OFFLINE",
}

--- Resolve "Name-Realm" the same way Blizzard's native whisper button does.
local function ResolveFullPlayerName(contextData)
    if UnitPopupSharedUtil and type(UnitPopupSharedUtil.GetFullPlayerName) == "function" then
        local fullName = UnitPopupSharedUtil.GetFullPlayerName(contextData)
        fullName = Utils and Utils:SanitizeTarget(fullName) or fullName
        if type(fullName) == "string" and fullName ~= "" then
            return fullName
        end
    end
    -- Fallback: assemble from the context fields OpenMenu populated,
    -- mirroring Blizzard's GetFullPlayerName. `surname` is the modern field
    -- (realm name when regional-unique names are off (retail), surname when
    -- on (Forever)); `server` is the legacy field for older contexts.
    local name = Utils and Utils:SanitizeTarget(contextData.name) or contextData.name
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local surname = contextData.surname or contextData.server
    if type(surname) == "string" and surname ~= "" then
        if contextData.unit
            and Utils and Utils.HasRegionalUniqueNames and Utils:HasRegionalUniqueNames() then
            local sepConsts = Constants and Constants.CharacterNameSeparatorConsts
            local sep = (sepConsts and sepConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
            return name .. sep .. surname
        end
        -- "-" is a valid whisper-target form on both clients (realm suffix on
        -- retail, surname link-separator on Forever).
        return name .. "-" .. surname
    end
    return name
end

--- Click-time handler for the overridden Whisper element. Ported from the
--- old UnitPopupWhisperButtonMixin.OnClick body; shares
--- RetargetOpenWhisper with the SendTell hook so the two entry points can't
--- drift. Handles WHISPER and BN_WHISPER contexts: BNet uses the safe
--- `contextData.bnetIDAccount` target and routes through `SendBNetTell` in
--- lockdown, bypassing its `OpenChat("")` -> `CHAT_FOCUS_OVERRIDE`
--- interaction that used to set then immediately revert the target while
--- the overlay was shown.
function EditBox:OpenWhisperFromUnitMenu(contextData)
    -- A menu opened before a restriction engaged can still fire this
    -- responder inside it: contextData fields are secret now and even a
    -- `~= nil` comparison errors under our taint. Best effort: hand the raw
    -- name to Blizzard's resolver (secret-safe; no-ops under a Chat
    -- restriction).
    if Utils and type(Utils.IsAnyAddOnRestriction) == "function"
        and Utils:IsAnyAddOnRestriction() then
        if ChatFrameUtil and ChatFrameUtil.SendTell then
            pcall(ChatFrameUtil.SendTell, contextData.name, contextData.chatFrame)
        end
        return
    end

    local isBNet = contextData.bnetIDAccount ~= nil

    -- Mirror the native guard: no whispering non-player units. BNet
    -- friend contexts carry no `unit` field, so the guard skips them.
    if not isBNet then
        local unit = contextData.unit
        if unit and not UnitIsHumanPlayer(unit) then
            return
        end
    end

    local fullName, chatType
    if isBNet then
        -- Friends-list BNet names can be protected/tokenized; the context
        -- already carries the safe account ID Blizzard uses, so prefer it
        -- over contextData.name.
        fullName = Utils and Utils:SanitizeTarget(contextData.bnetIDAccount)
            or contextData.bnetIDAccount
        if not fullName then
            fullName = Utils and Utils:SanitizeTarget(contextData.name)
                or contextData.name
        end
        chatType = "BN_WHISPER"
    else
        fullName = ResolveFullPlayerName(contextData)
        chatType = "WHISPER"
    end
    if (type(fullName) ~= "string" and type(fullName) ~= "number")
        or fullName == "" then
        return
    end

    -- Lockdown (or overlay unavailable): replicate the native button via
    -- Blizzard's own tell function -- not protected, so safe from this
    -- tainted path. Yapper's hooksecurefunc early-returns during lockdown,
    -- so Blizzard's editbox takes over cleanly with no reentrancy.
    local utils = YapperTable.Utils
    local locked = utils and utils.IsChatLockdown and utils:IsChatLockdown()
    if locked or type(self.Show) ~= "function" then
        if isBNet then
            if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
                -- SendBNetTell resolves the native tokenized name securely.
                ChatFrameUtil.SendBNetTell(contextData.name or fullName)
            end
        else
            if ChatFrameUtil and ChatFrameUtil.SendTell then
                ChatFrameUtil.SendTell(fullName, contextData.chatFrame)
            end
        end
        return
    end

    local blizzBox = contextData.chatFrame and contextData.chatFrame.editBox
    if not blizzBox then
        blizzBox = self.OrigEditBox
            or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
            or _G.ChatFrame1EditBox
    end

    local existingText = ""
    if blizzBox and blizzBox.GetText then
        existingText = blizzBox:GetText() or ""
    end

    -- Already open: retarget in place via the shared routing helper.
    if self.Overlay and self.Overlay:IsShown() then
        self:RetargetOpenWhisper(fullName, blizzBox, chatType)
        return
    end

    if blizzBox and blizzBox.Hide then
        blizzBox:Hide()
        if blizzBox.SetText then
            blizzBox:SetText("")
        end
    end

    self:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)
    self.ChatType = chatType
    self.Target = fullName
    self._secureReplySource = nil
    self.ChannelName = nil
    -- Transient external whisper must not become the LastUsed sticky.
    self._externalWhisperTarget = fullName

    if existingText ~= "" and self.OverlayEdit and self.OverlayEdit.SetText then
        self.OverlayEdit:SetText(existingText)
    end

    self:RefreshLabel()
end

--- Menu.ModifyMenu callback: find the Whisper element in the freshly built
--- description and swap its responder for Yapper's routing (descriptions
--- are regenerated per open). Handles regular and BNet contexts; BNet is
--- no longer skipped because the old approach (native responder +
--- SendBNetTell hooksecurefunc) raced: SendBNetTell calls OpenChat(""),
--- which short-circuits via CHAT_FOCUS_OVERRIDE while the overlay is shown,
--- so the target appeared briefly then reverted.
local function OnUnitMenuOpened(_, rootDescription, contextData)
    if type(contextData) ~= "table" then
        return
    end

    -- While any addon restriction is enforced, unit context fields are
    -- secret: reading them inside our responder errors on the first
    -- comparison under tainted execution. Leave the native Whisper
    -- responder in place -- Blizzard's click path handles secrets.
    if Utils and type(Utils.IsAnyAddOnRestriction) == "function"
        and Utils:IsAnyAddOnRestriction() then
        return
    end

    MenuUtil.TraverseMenu(rootDescription, function(elementDescription)
        if MenuUtil.GetElementText(elementDescription) ~= WHISPER then
            return false
        end
        elementDescription:SetResponder(function()
            local eb = YapperTable.EditBox
            if eb and eb.OpenWhisperFromUnitMenu then
                eb:OpenWhisperFromUnitMenu(contextData)
            end
            return MenuResponse.CloseAll
        end)
        return true -- Whisper found; stop traversal.
    end)
end

--- Install the Menu.ModifyMenu registrations.  Idempotent; called from
--- Yapper.lua on PLAYER_ENTERING_WORLD (Blizzard_Menu is always loaded by
--- then, and tag registration does not require Blizzard_UnitPopup).
function EditBox:InstallUnitPopupWhisperOverride()
    if self._unitPopupMenuHandles then
        return true
    end

    if not (Menu and type(Menu.ModifyMenu) == "function" and MenuUtil and MenuResponse) then
        if YapperTable.Utils then
            YapperTable.Utils:VerbosePrint("Menu API unavailable; unit-popup whisper routing relies on the SendTell hook only.")
        end
        return false
    end

    local handles = {}
    for _, tag in ipairs(WHISPER_MENU_TAGS) do
        handles[#handles + 1] = Menu.ModifyMenu(tag, OnUnitMenuOpened)
    end
    self._unitPopupMenuHandles = handles

    if YapperTable.Utils then
        YapperTable.Utils:VerbosePrint("Unit-popup whisper routing installed for " .. tostring(#handles) .. " menu tags.")
    end
    return true
end
