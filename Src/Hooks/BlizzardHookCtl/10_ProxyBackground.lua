local _, YapperTable = ...
local EditBox = YapperTable.EditBox
--- In proxy mode the native editbox is the visible background. A channel link
--- or chat-menu selection activates that editbox, and when focus returns to the
--- overlay Blizzard deactivates it on empty-text focus loss — which, in classic
--- chat style, also Hides it, wiping the background. Re-show it next frame so
--- the proxy background survives. No-op outside proxy mode.
function EditBox:EnsureProxyBackgroundShown()
    local cfg = YapperTable.Config and YapperTable.Config.EditBox
    local isProxy = cfg and cfg.UseBlizzardSkinProxy == true and cfg.UseLegacyCloneProxy ~= true
    if not isProxy then return end
    local eb = self.OrigEditBox
    if not eb or not eb.Show then return end
    C_Timer.After(0, function()
        -- Don't resurrect the background if the user just closed Yapper —
        -- Classic style relies on the natural Deactivate/Hide path then.
        if self._closing then return end
        if self.Overlay and self.Overlay:IsShown() and eb and not eb:IsShown() then
            pcall(function()
                eb:Show()
                if eb.SetAlpha then eb:SetAlpha(1.0) end
            end)
        end
        -- In proxy mode the Blizzard editbox is only a visual shell under Yapper.
        -- Keep its text empty so deferred OpenChat/ParseText writes never show underneath.
        if self.Overlay and self.Overlay:IsShown() and eb and eb.GetText and eb.SetText then
            local blizzText = eb:GetText() or ""
            if blizzText ~= "" then
                pcall(function() eb:SetText("") end)
            end
        end
        if self.EnsureProxyHeaderHidden then
            self:EnsureProxyHeaderHidden(eb)
        end
    end)
end
