--[[
    Hooks/UnitPopup.lua
    Menu-based whisper interception via the modern Menu API (Menu.ModifyMenu).

    Replaces the old UnitPopupWhisperButtonMixin.OnClick override, which tainted
    the entire unit-popup menu: Blizzard's secure menu generator reads OnClick
    off the mixin table (GenerateClosure in CreateMenuDescription), so an
    addon-written OnClick tainted the remainder of the generator pass and every
    element built after the Whisper entry — including protected actions like
    Copy Character Name (CopyToClipboard) and Set Focus, which then got blocked
    and attributed to Yapper.

    Menu.ModifyMenu is Blizzard's sanctioned addon customization surface.  Our
    callback runs behind a securecallfunction boundary AFTER the secure
    generator pass has finished, and element descriptions are per-element
    proxies: replacing one element's responder taints only that element's click
    execution.  Whispering is not a protected action, so a tainted whisper
    click is harmless, and every other menu item keeps its pristine secure
    responder.

    See Documentation/UnitPopupWhisper.md for the full write-up.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox

-- Re-localise Lua globals.
local type     = type
local ipairs   = ipairs
local tostring = tostring

-- Root-menu tags (format "MENU_UNIT_<which>") whose menus can host a Whisper
-- button.  Registering a tag whose menu has no Whisper button is a harmless
-- no-op (the traversal simply finds nothing), so this list favours coverage
-- over precision.  BNet menus (BN_FRIEND*) are registered too but skipped at
-- runtime; their native OnClick calls ChatFrameUtil.SendBNetTell, which
-- Yapper's existing hooksecurefunc already routes.
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

--- True when the menu context targets a Battle.net account rather than a
--- character.  BNet whispers keep Blizzard's native path (SendBNetTell),
--- which Yapper's existing hooksecurefunc in 30_ChatFrameHooks.lua routes.
local function IsBNetContext(contextData)
    if contextData.bnetIDAccount then
        return true
    end
    local playerLocation = contextData.playerLocation
    if playerLocation and type(playerLocation.IsBattleNetGUID) == "function" then
        return playerLocation:IsBattleNetGUID()
    end
    return false
end

--- Resolve "Name-Realm" the same way Blizzard's native whisper button does.
local function ResolveFullPlayerName(contextData)
    if UnitPopupSharedUtil and type(UnitPopupSharedUtil.GetFullPlayerName) == "function" then
        local fullName = UnitPopupSharedUtil.GetFullPlayerName(contextData)
        if type(fullName) == "string" and fullName ~= "" then
            return fullName
        end
    end
    -- Fallback: assemble from the context fields OpenMenu populated.
    local name = contextData.name
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local server = contextData.server
    if type(server) == "string" and server ~= "" then
        return name .. "-" .. server
    end
    return name
end

--- Click-time handler for the overridden Whisper element.  Ported from the
--- old UnitPopupWhisperButtonMixin.OnClick override body; shares
--- RetargetOpenWhisper with the SendTell hook so the two entry points cannot
--- drift apart.
function EditBox:OpenWhisperFromUnitMenu(contextData)
    -- Mirror the native guard: no whispering non-player units.
    local unit = contextData.unit
    if unit and not UnitIsHumanPlayer(unit) then
        return
    end

    local fullName = ResolveFullPlayerName(contextData)
    if not fullName then
        return
    end

    -- Lockdown (or overlay unavailable): replicate the native button by
    -- calling ChatFrameUtil.SendTell ourselves.  It is not protected, so
    -- calling it from this (tainted) click path is safe.  Yapper's SendTell
    -- hooksecurefunc early-returns during lockdown, so Blizzard's editbox
    -- takes over cleanly with no reentrancy.
    local utils = YapperTable.Utils
    local locked = utils and utils.IsChatLockdown and utils:IsChatLockdown()
    if locked or type(self.Show) ~= "function" then
        if ChatFrameUtil and ChatFrameUtil.SendTell then
            ChatFrameUtil.SendTell(fullName, contextData.chatFrame)
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

    -- If already open, retarget in place via the shared routing helper.
    if self.Overlay and self.Overlay:IsShown() then
        self:RetargetOpenWhisper(fullName, blizzBox)
        return
    end

    if blizzBox and blizzBox.Hide then
        blizzBox:Hide()
        if blizzBox.SetText then
            blizzBox:SetText("")
        end
    end

    self:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)
    self.ChatType = "WHISPER"
    self.Target = fullName
    self.ChannelName = nil
    -- Transient external whisper: must not become the global LastUsed sticky.
    self._externalWhisperTarget = fullName

    if existingText ~= "" and self.OverlayEdit and self.OverlayEdit.SetText then
        self.OverlayEdit:SetText(existingText)
    end

    self:RefreshLabel()
end

--- Menu.ModifyMenu callback: find the Whisper element in the freshly built
--- menu description and swap its responder for Yapper's routing.  Runs every
--- time a registered unit menu opens (descriptions are regenerated per open).
local function OnUnitMenuOpened(_, rootDescription, contextData)
    if type(contextData) ~= "table" then
        return
    end

    -- BNet targets stay fully native (see IsBNetContext).
    if IsBNetContext(contextData) then
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
