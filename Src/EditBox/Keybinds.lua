--[[
    EditBox/Keybinds.lua
    Keybind override system for Yapper.
    Replaces ChatFrameUtil.OpenChat hook with SetOverrideBinding for primary chat open path.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local Utils = YapperTable.Utils

-- Keybind module
local Keybinds = {}
EditBox.Keybinds = Keybinds

-- State tracking
Keybinds._registered = false
Keybinds._pendingRegistration = false
Keybinds._overrideBindings = {
    "OPENCHAT",
    "OPENCHATSLASH",
    "REPLY",
    "REPLYTELL2"
}

-- Lockdown state preservation (using Yapper's existing LastUsed system)
Keybinds._preLockdownLastUsed = nil

-- Housing editor decor-selection state, tracked from the editor's
-- SELECTED_TARGET_CHANGED event payloads so yield checks don't have to poll
-- a C API whose return may be unusable (secret/erroring) in that context.
Keybinds._decorSelected = false
Keybinds._decorSelectionObserved = false

-- Secure buttons for each binding type
Keybinds._secureButtons = {}

-- Safe verbose printing helper
local function LogVerbose(msg)
    YapperTable.Utils:VerbosePrint(msg)
end

local function IsNativeChatEditBox(eb)
    if not eb or eb == EditBox.OverlayEdit or not eb.GetName then
        return false
    end
    local name = eb:GetName()
    return type(name) == "string" and name:match("^ChatFrame%d+EditBox$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Secure Button Creation
-- ---------------------------------------------------------------------------

--- Sync Yapper's channel/target to Blizzard's editbox for lockdown handling.
local function SyncAttributesToBlizzard()
    local yapperChatType = EditBox.ChatType
    local yapperTarget = Utils:SanitizeTarget(EditBox.Target)
    local yapperLanguage = EditBox.Language

    if not yapperChatType then
        return
    end
    if Utils:IsChatOrCombatLockdown() then
        return
    end
    
    -- Get the default Blizzard editbox
    local blizzEditBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or _G.ChatFrame1EditBox
    if not (blizzEditBox and blizzEditBox.SetAttribute) then
        return
    end
    
    -- Resolve chat type to override key if needed
    local overrideCT = yapperChatType
    if yapperChatType == "PARTY_LEADER" then
        overrideCT = "PARTY"
    elseif yapperChatType == "RAID_LEADER" then
        overrideCT = "RAID"
    end

    -- For whisper/BN whisper, do not write tellTarget to the native editbox.
    -- Blizzard owns tellTarget for whispers and normalising it can produce a
    -- secret value under Midnight lockdown; writing it from tainted code taints
    -- the attribute and causes UpdateHeader to error.
    if yapperChatType == "WHISPER" or yapperChatType == "BN_WHISPER" then
        return
    end

    blizzEditBox:SetAttribute("chatType", overrideCT)

    if yapperChatType == "CHANNEL" then
        if yapperTarget then
            blizzEditBox:SetAttribute("channelTarget", yapperTarget)
        end
        blizzEditBox:SetAttribute("tellTarget", nil)
    else
        blizzEditBox:SetAttribute("tellTarget", nil)
        blizzEditBox:SetAttribute("channelTarget", nil)
    end

    if yapperLanguage then
        blizzEditBox:SetAttribute("language", yapperLanguage)
    else
        blizzEditBox:SetAttribute("language", nil)
    end
end

--- Resolve a reply target through Yapper's secret-safe readers. Returns nil,
--- nil when no usable target exists — including when Blizzard's remembered-target
--- list holds a secret value.
local function ResolveSafeReplyTarget(rewhisper)
    local getInfo = EditBox and (rewhisper
        and EditBox.GetLastToldTargetInfo or EditBox.GetLastTellTargetInfo)
    if type(getInfo) ~= "function" then
        return nil, nil
    end
    local ok, lastType, lastTarget = pcall(getInfo)
    if not ok then
        return nil, nil
    end
    return lastType, lastTarget
end

--- Common handler for all keybind buttons.
--- @param bindingName string The binding that triggered this
--- @param prefillText string Optional text to pre-fill in the editbox
--- @param syncAttributes boolean Whether to sync attributes during lockdown
local function HandleKeybindClick(bindingName, prefillText, syncAttributes)
    if not (EditBox and EditBox.Show) then
        return
    end

    -- If the post queue is stalled and waiting for Enter to continue,
    -- progress the queue instead of opening Yapper.
    local Queue = YapperTable.Queue
    if Queue and Queue.TryContinue and Queue:TryContinue() then
        Queue:SendNext(true)
        return
    end

    local isRewhisper = (bindingName == "REPLYTELL2")
    local isReply = (bindingName == "REPLY" or isRewhisper)

    -- Check for chat messaging lockdown before opening Yapper
    local inLockdown = Utils:IsChatLockdown()
    if isReply and inLockdown then
        -- Do not call Blizzard's ReplyTell from this tainted click path. Its
        -- remembered-target comparison is not safe when the target is secret.
        LogVerbose((isRewhisper and "REPLYTELL2" or "REPLY")
            .. " keybind: reply unavailable during lockdown; ignoring.")
        return
    end
    if inLockdown then
        -- Save Yapper's LastUsed state for restoration after lockdown
        if not Keybinds._preLockdownLastUsed and EditBox.LastUsed then
            Keybinds._preLockdownLastUsed = {
                chatType = EditBox.LastUsed.chatType,
                target = Utils:SanitizeTarget(EditBox.LastUsed.target),
                language = EditBox.LastUsed.language
            }
        end

        -- IMPORTANT: Do not write chatType/tellTarget/channelTarget attributes
        -- during lockdown from keybind code. Those SetAttribute writes can taint
        -- the native header path (UpdateHeader) when Blizzard focuses the box.
        -- In lockdown we delegate fully to Blizzard's own OpenChat flow.
        if syncAttributes then
            LogVerbose("Keybind lockdown fallback: skipping SyncAttributesToBlizzard to avoid taint")
        end

        if ChatFrameUtil and ChatFrameUtil.OpenChat then
            -- Preserve OPENCHATSLASH semantics in fallback mode while still
            -- using Blizzard as the authority during lockdown.
            if prefillText and prefillText ~= "" then
                ChatFrameUtil.OpenChat(prefillText)
            else
                ChatFrameUtil.OpenChat()
            end
        end
        return
    end
    
    -- Lockdown ended: restore the pre-lockdown LastUsed sticky so the next
    -- open recovers the channel the user was on before combat, instead of
    -- falling back to SAY (Blizzard's Deactivate reverts chatType to
    -- stickyType, which Yapper keeps in sync via SyncAttributesToBlizzard,
    -- but the keybind path bypasses Show()'s draft/affinity resolution and
    -- needs LastUsed populated). Only LastUsed is restored — transient
    -- ChatType/Target/Language are re-resolved by Show()'s
    -- ResolveOpenSelection, so we don't risk thrashing overlay state. This
    -- touches only Yapper-side tables (no secure attributes), so there is
    -- no taint surface. Restores a safety net removed in 1ec4628 that was
    -- never replaced (the comment referenced a ResyncFromBlizzardAfterLockdown
    -- function that was never implemented).
    if Keybinds._preLockdownLastUsed and not inLockdown then
        if EditBox.LastUsed then
            EditBox.LastUsed.chatType = Keybinds._preLockdownLastUsed.chatType
            EditBox.LastUsed.target = Keybinds._preLockdownLastUsed.target
            EditBox.LastUsed.language = Keybinds._preLockdownLastUsed.language
        end
        Keybinds._preLockdownLastUsed = nil
    end

    -- REPLY: resolve the last incoming whisper through Yapper's secret-safe
    -- reader before any open. Without a usable target the key is a no-op —
    -- matching Blizzard's native behaviour with an empty remembered list, and
    -- deliberately giving up secret targets rather than erroring.
    local replyType, replyTarget
    if isReply then
        replyType, replyTarget = ResolveSafeReplyTarget(isRewhisper)
        if not replyTarget or replyTarget == "" then
            LogVerbose("REPLY keybind: no usable reply target (empty or secret); ignoring.")
            return
        end
    end

    local function ApplyReplyTarget()
        if not isReply or not replyTarget then return end
        EditBox.ChatType = replyType or "WHISPER"
        EditBox.Target = replyTarget
        -- Mark that this target came from a secure reply source so
        -- ResolveWhisperTarget can re-source it from Blizzard at send time.
        EditBox._secureReplySource = isRewhisper and "told" or "tell"
        EditBox.ChannelName = nil
        EditBox.Language = nil
        if EditBox.RefreshLabel then
            EditBox:RefreshLabel()
        end
    end

    local function SuppressReplyKeyCharacter()
        if not isReply or not EditBox.OverlayEdit then return end
        local replyEdit = EditBox.OverlayEdit
        if replyEdit.ClearFocus then
            replyEdit:ClearFocus()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if EditBox.Overlay and EditBox.Overlay:IsShown()
                    and replyEdit and replyEdit.SetFocus then
                    replyEdit:SetFocus()
                end
            end)
        end
    end

    -- Don't show if already shown to prevent state thrashing
    if EditBox.Overlay and EditBox.Overlay:IsShown() then
        ApplyReplyTarget()
        if EditBox.OverlayEdit then
            EditBox.OverlayEdit:SetFocus()
        end
        SuppressReplyKeyCharacter()
        return
    end
    
    -- Fire PRE_EDITBOX_SHOW filter so external addons (CEBE, WIMBridge, etc.)
    -- can inspect and react before the overlay opens.  This mirrors the filter
    -- call in HookBlizzardEditBox so addons see a consistent activation path.
    if YapperTable.API then
        local filterCT = (EditBox.LastUsed and EditBox.LastUsed.chatType) or "SAY"
        local filterTarget = EditBox.LastUsed
            and Utils:SanitizeTarget(EditBox.LastUsed.target) or nil
        local result = YapperTable.API:RunFilter("PRE_EDITBOX_SHOW", {
            chatType = filterCT,
            target   = filterTarget,
        })
        if result == false then
            return
        end
    end

    -- Prefer the currently active native chat editbox first; IM history can lag
    -- behind during whisper retarget/close sequences and reopen stale contexts.
    local activeWindow = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    local targetEditBox = IsNativeChatEditBox(activeWindow) and activeWindow or nil
    if not targetEditBox and IsNativeChatEditBox(EditBox._lastActiveIMEditBox) then
        targetEditBox = EditBox._lastActiveIMEditBox
    end
    if not targetEditBox then
        targetEditBox = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox
    end

    Utils:DebugPrint("Secure button clicked, showing Yapper overlay")
    local ok, err = pcall(function()
        EditBox:Show(targetEditBox)
    end)
    if not ok then
        -- Error in Show - print to chat so user can see it
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Yapper Error:|r " .. tostring(err))
        return
    end

    -- Force the reply whisper context AFTER Show() as the final authority
    -- (same pattern as the SendTell hook), since Show()'s open-selection can
    -- resolve to LastUsed/frame context instead of the reply target.
    ApplyReplyTarget()
    SuppressReplyKeyCharacter()

    -- NOTE: We intentionally do NOT apply prefillText here. Show() has already
    -- focused the overlay synchronously inside the key-DOWN event, so the
    -- physical char event (e.g. "/" for OPENCHATSLASH) fires on the focused
    -- overlay immediately after all Lua returns.  Manually SetText("/") here
    -- would double-fill: our "/" plus the physical char's "/" → "//".
    -- The prefillText parameter is still used by the lockdown fallback above,
    -- where Blizzard's OpenChat handles the char itself.

    -- Use the proper Blizzard function to set focus override
    if EditBox.UpdateFocusOverride then
        EditBox:UpdateFocusOverride()
    end
end

--- Create a secure button for a specific binding type.
--- @param bindingName string The binding name this button handles
--- @param prefillText string Optional text to pre-fill when this binding is triggered
--- @param syncAttributes boolean Whether to sync attributes during lockdown
local function CreateSecureButtonForBinding(bindingName, prefillText, syncAttributes)
    local button = CreateFrame("Button", "YapperKeybindButton_" .. bindingName, nil, "SecureActionButtonTemplate")
    button:SetAttribute("type", "click")
    button:Hide() -- Hide the button, we only use it for keybind routing

    -- Fire on key DOWN, like Blizzard's native OPENCHAT binding. A plain
    -- Button defaults to LeftButtonUp, so the override CLICK binding would
    -- only run PostClick on key RELEASE: the overlay opened a keypress-length
    -- late, and any keys rolled between Enter-down and Enter-up had no
    -- focused editbox to land in (hence action-bar bleed-through for fast
    -- typists). With down-clicks the whole open path, including the final
    -- OverlayEdit:SetFocus(), completes synchronously inside the Enter-down
    -- event, so every subsequent key event already has a focused editbox.
    button:RegisterForClicks("AnyDown")
    
    -- Use PostClick to run our insecure code after the secure click
    button:SetScript("PostClick", function()
        local ok, err = pcall(function()
            HandleKeybindClick(bindingName, prefillText, syncAttributes)
        end)
        if not ok then
            -- The click silently did nothing otherwise; leave a trace for diagnosis.
            Utils:DebugPrint("Keybind PostClick failed for " .. tostring(bindingName)
                .. ": " .. tostring(err))
        end
    end)
    
    LogVerbose("Secure button created for binding: " .. bindingName)
    return button
end

--- Create secure buttons for all override bindings.
--- Idempotent: existing buttons are kept. Recreating a button that holds an
--- override binding would leave the stale frame intercepting the key with no
--- way to clear it (override bindings persist on the old frame object).
function Keybinds:CreateSecureButtons()
    if not self._secureButtons["OPENCHAT"] then
        -- OPENCHAT - standard chat open, sync attributes for lockdown
        self._secureButtons["OPENCHAT"] = CreateSecureButtonForBinding("OPENCHAT", nil, true)
    end

    if not self._secureButtons["OPENCHATSLASH"] then
        -- OPENCHATSLASH - chat open with "/" pre-filled, sync attributes for lockdown
        self._secureButtons["OPENCHATSLASH"] = CreateSecureButtonForBinding("OPENCHATSLASH", "/", true)
    end

    if not self._secureButtons["REPLY"] then
        -- REPLY - reply to last incoming whisper via Yapper's secret-safe reader.
        -- Overridden because the native binding runs Blizzard's ReplyTell inside
        -- execution tainted by Yapper's ChatFrameUtil wrappers; a secret entry in
        -- Blizzard's remembered-target list then errors and eats the keypress.
        self._secureButtons["REPLY"] = CreateSecureButtonForBinding("REPLY", nil, false)
    end

    if not self._secureButtons["REPLYTELL2"] then
        -- REPLYTELL2 - re-whisper the last outgoing target via Yapper's safe reader.
        self._secureButtons["REPLYTELL2"] = CreateSecureButtonForBinding("REPLYTELL2", nil, false)
    end
end

-- ---------------------------------------------------------------------------
-- Override Registration
-- ---------------------------------------------------------------------------

--- Context bindings that are inert until a decor item is selected.
--- HOUSING_REMOVEDECOR no-ops without a selection (HousingFramesUtil
--- .RemoveSelectedDecor guards on C_HousingDecor.IsDecorSelected), so we only
--- yield its key while a decor is actually selected; otherwise the key keeps
--- its chat meaning (e.g. R still replies to the last whisper).
local SELECTION_GATED_CONTEXT_BINDINGS = {
    HOUSING_REMOVEDECOR = true,
}

local function IsSelectionGatedBindingInert(binding)
    if not SELECTION_GATED_CONTEXT_BINDINGS[binding] then
        return false
    end
    -- Selection state is tracked from the editor's target-selection event
    -- payloads (see Init). Before the first observed event this session we
    -- fall back to the C API — inside pcall, since its return may be a secret
    -- value that errors on comparison. If we cannot prove the binding is
    -- inert we treat it as live and yield: a swallowed context key (dead
    -- remove-decor) is a worse failure than a yielded reply key.
    if Keybinds._decorSelectionObserved then
        return Keybinds._decorSelected ~= true
    end
    local ok, inert = pcall(function()
        return (C_HousingDecor and C_HousingDecor.IsDecorSelected
            and C_HousingDecor.IsDecorSelected()) == false
    end)
    return ok and inert == true
end

--- Return the name of a binding that claims `key` inside a currently active
--- non-default binding context, or nil when the key is unclaimed.
--- Binding contexts (Enum.BindingContext) let the client bind a key that is
--- already bound in the default context — e.g. the housing editor's decor
--- modes claim R for HOUSING_REMOVEDECOR while R is also REPLY. Our override
--- bindings outrank context bindings in the engine's key dispatch, so an
--- overridden chat key becomes a dead key inside the editor (the click
--- handler resolves no reply target and silently returns). When a context
--- claims the key we must yield it.
local function GetConflictingContextBinding(key)
    if not (C_KeyBindings and Enum and Enum.BindingContext) then
        return nil
    end
    local isActive = C_KeyBindings.IsBindingContextActive
    local getByKey = C_KeyBindings.GetBindingByKey
    if type(isActive) ~= "function" or type(getByKey) ~= "function" then
        return nil
    end
    for _, context in pairs(Enum.BindingContext) do
        if context ~= Enum.BindingContext.None then
            -- Restricted-adjacent C calls: a runtime error here must not
            -- abort override registration mid-loop.
            local ok, binding = pcall(function()
                if isActive(context) == true then
                    local found = getByKey(key, context)
                    if type(found) == "string" and found ~= "" and found ~= "NONE" then
                        return found
                    end
                end
            end)
            if ok and binding and not IsSelectionGatedBindingInert(binding) then
                return binding
            end
        end
    end
    return nil
end

--- Clear a button's overrides and re-apply only the keys not claimed by an
--- active binding context. SetOverrideBindingClick/ClearOverrideBindings are
--- not protected calls, so this is safe under combat and chat-messaging
--- lockdown — which matters, because deferring a yield until regen would
--- leave the context's key dead for an entire session (e.g. the whole time
--- the housing editor is open).
local function ApplyButtonOverrides(button, bindingName)
    pcall(ClearOverrideBindings, button)
    local key1, key2 = GetBindingKey(bindingName)
    for index = 1, 2 do
        local key = index == 1 and key1 or key2
        local slot = "key" .. index
        if type(key) ~= "string" or key == "" then
            LogVerbose("Skipping " .. bindingName .. " " .. slot .. " - no key")
        else
            local contextBinding = GetConflictingContextBinding(key)
            if contextBinding then
                LogVerbose("Yielding " .. bindingName .. " " .. slot .. " (" .. key
                    .. ") to active binding context: " .. contextBinding)
            else
                local success, err = pcall(function()
                    SetOverrideBindingClick(button, false, key, button:GetName())
                end)
                if success then
                    LogVerbose("Registered override for " .. bindingName .. " " .. slot .. ": " .. key)
                else
                    LogVerbose("Failed to register override for " .. bindingName .. " " .. slot .. ": " .. tostring(err))
                end
            end
        end
    end
end

--- Register keybind overrides to route chat opens to Yapper.
--- Must be called outside of combat/lockdown.
function Keybinds:RegisterOverrides()
    if self._registered then
        return
    end

    -- Ensure secure buttons exist for all bindings
    self:CreateSecureButtons()

    -- Check if we can set overrides (not in combat/lockdown)
    if InCombatLockdown and InCombatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RegisterOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RegisterOverrides deferred - in lockdown")
        return
    end

    -- Register overrides for each binding
    for _, bindingName in ipairs(self._overrideBindings) do
        if type(bindingName) == "string" and GetBindingKey then
            local button = self._secureButtons[bindingName]
            if not button then
                LogVerbose("Skipping " .. bindingName .. " - no secure button created")
            else
                ApplyButtonOverrides(button, bindingName)
            end
        else
            LogVerbose("Skipping " .. bindingName .. " - invalid binding name or GetBindingKey not available")
        end
    end

    self._registered = true
    self._pendingRegistration = false
    LogVerbose("Keybind overrides registered successfully")
end

--- Unregister keybind overrides.
--- Must be called outside of combat/lockdown.
function Keybinds:UnregisterOverrides()
    if not self._registered then
        return
    end

    -- Check if we can clear overrides (not in combat/lockdown)
    if InCombatLockdown and InCombatLockdown() then
        LogVerbose("Keybinds:UnregisterOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        LogVerbose("Keybinds:UnregisterOverrides deferred - in lockdown")
        return
    end

    -- Clear all overrides from all secure buttons
    for bindingName, button in pairs(self._secureButtons) do
        if button then
            local success, err = pcall(function()
                ClearOverrideBindings(button)
            end)
            if success then
                LogVerbose("Cleared overrides for " .. bindingName)
            else
                LogVerbose("Failed to clear overrides for " .. bindingName .. ": " .. tostring(err))
            end
        end
    end

    self._registered = false
    self._pendingRegistration = false
    LogVerbose("Keybind overrides unregistered")
end

--- Refresh overrides (e.g., after keybind changes).
--- Unregisters and re-registers all overrides.
function Keybinds:RefreshOverrides()
    if InCombatLockdown and InCombatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RefreshOverrides deferred - in combat")
        return
    end

    if Utils:IsChatLockdown() then
        self._pendingRegistration = true
        LogVerbose("Keybinds:RefreshOverrides deferred - in lockdown")
        return
    end

    self:UnregisterOverrides()
    self:RegisterOverrides()
end

--- Re-apply overrides so keys claimed by active binding contexts stay
--- yielded. Unlike RefreshOverrides this intentionally runs during combat
--- and chat lockdown: it only clears/re-sets override bindings, which are
--- not protected operations, and deferring a yield until regen would leave
--- the context's key dead for the entire session.
--- Called by binding-context and housing-selection change triggers.
function Keybinds:SyncContextYields()
    if not self._registered or not GetBindingKey then
        return
    end
    for _, bindingName in ipairs(self._overrideBindings) do
        local button = type(bindingName) == "string" and self._secureButtons[bindingName]
        if button then
            ApplyButtonOverrides(button, bindingName)
        end
    end
end

--- Check if overrides are currently registered.
--- @return boolean
function Keybinds:IsRegistered()
    return self._registered
end

--- Check if registration is pending (waiting for combat/lockdown to end).
--- @return boolean
function Keybinds:IsPendingRegistration()
    return self._pendingRegistration
end

--- Complete pending registration if combat/lockdown has ended.
--- Called by combat/lockdown end event handlers.
function Keybinds:CompletePendingRegistration()
    if self._pendingRegistration then
        self:RegisterOverrides()
    end
end

-- ---------------------------------------------------------------------------
-- Event Handlers
-- ---------------------------------------------------------------------------

--- Initialize keybind event listeners.
--- Called during addon boot.
function Keybinds:Init()
    -- Create the secure buttons
    self:CreateSecureButtons()
    -- Listen for keybind changes to refresh overrides
    if YapperTable.Events and YapperTable.Events.Register then
        YapperTable.Events:Register("PARENT_FRAME", "UPDATE_BINDINGS", function()
            if self._registered then
                LogVerbose("Keybinds detected UPDATE_BINDINGS, refreshing overrides")
                self:RefreshOverrides()
            end
        end)

        -- Re-evaluate yields on events that can change which keys an active
        -- context claims. Selection state for selection-gated context
        -- bindings (HOUSING_REMOVEDECOR) is tracked from the selection
        -- events' own payloads so the yield gate never has to rely on a
        -- potentially restricted C API inside the editor.
        for _, event in ipairs({
            "HOUSE_EDITOR_MODE_CHANGED",
            "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED",
            "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED",
            "HOUSING_DECOR_REMOVED",
        }) do
            YapperTable.Events:Register("PARENT_FRAME", event, function(...)
                if event == "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED"
                    or event == "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED" then
                    -- Payload: selected, targetType, isPreview — only a Decor
                    -- target makes a selection-gated binding live.
                    local ok, isDecor = pcall(function(...)
                        local selected, targetType = ...
                        local decorType = (Enum.HousingBasicModeTargetType
                                and Enum.HousingBasicModeTargetType.Decor)
                            or (Enum.HousingExpertModeTargetType
                                and Enum.HousingExpertModeTargetType.Decor)
                            or 1
                        return selected == true and targetType == decorType
                    end, ...)
                    if ok then
                        Keybinds._decorSelected = isDecor == true
                        Keybinds._decorSelectionObserved = true
                    end
                elseif event == "HOUSING_DECOR_REMOVED" then
                    Keybinds._decorSelected = false
                    Keybinds._decorSelectionObserved = true
                elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
                    -- Mode switches may keep or clear the selection;
                    -- re-derive (contained) so stale state can't stick.
                    local ok, selected = pcall(function()
                        return C_HousingDecor.IsDecorSelected() == true
                    end)
                    if ok then
                        Keybinds._decorSelected = selected == true
                        Keybinds._decorSelectionObserved = true
                    end
                end
                if self._registered then
                    self:SyncContextYields()
                end
            end)
        end
    end

    -- Binding contexts (housing editor modes, etc.) claim keys while active.
    -- Re-sync yields on every context change so claimed keys are yielded to
    -- the context action instead of being swallowed by our secure button.
    -- Deferred one frame so back-to-back (de)activations settle in one pass.
    if C_KeyBindings and type(C_KeyBindings.ActivateBindingContext) == "function" then
        local function OnBindingContextChanged()
            C_Timer.After(0, function()
                if Keybinds._registered then
                    Keybinds:SyncContextYields()
                end
            end)
        end
        hooksecurefunc(C_KeyBindings, "ActivateBindingContext", OnBindingContextChanged)
        hooksecurefunc(C_KeyBindings, "DeactivateBindingContext", OnBindingContextChanged)
    end

    -- Listen for combat/lockdown end to complete pending registration
    if YapperTable.Events and YapperTable.Events.Register then
        YapperTable.Events:Register("PARENT_FRAME", "PLAYER_REGEN_ENABLED", function()
            self:CompletePendingRegistration()
        end)
        
        YapperTable.Events:Register("PARENT_FRAME", "CHALLENGE_MODE_COMPLETED", function()
            self:CompletePendingRegistration()
        end)
    end
end
