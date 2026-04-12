-- Blizzard-style theme for Yapper overlay
local YapperName, YapperTable = ...

local function GetChatTypeColor(chatType, fallback)
    local info = ChatTypeInfo and chatType and ChatTypeInfo[chatType]
    if not info then
        return fallback
    end
    return {
        r = (type(info.r) == "number") and info.r or fallback.r,
        g = (type(info.g) == "number") and info.g or fallback.g,
        b = (type(info.b) == "number") and info.b or fallback.b,
        a = fallback.a or 1,
    }
end

local theme = {
    name = "Blizzard EditBox",
    description = "Mimics the default Blizzard chat editbox styling with a visible border.",
    -- inputBg / labelBg / textColor are seeded into per-character config when this
    -- theme is selected, and applied from there by ApplyConfigToLiveOverlay.
    inputBg    = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
    labelBg    = { r = 0.09, g = 0.09, b = 0.09, a = 0.98 },
    textColor  = { r = 1,    g = 1,    b = 1,    a = 1    },
    border     = true,
    borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
    channelTextColors = {
        SAY           = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
        YELL          = { r = 1.00, g = 0.25, b = 0.25, a = 1 },
        PARTY         = { r = 0.67, g = 0.67, b = 1.00, a = 1 },
        WHISPER       = { r = 1.00, g = 0.50, b = 1.00, a = 1 },
        -- Keep BN_WHISPER consistent with the Engine default so "Reset to Default"
        -- doesn't cause the theme to substitute a different colour unexpectedly.
        BN_WHISPER    = { r = 0.25, g = 0.78, b = 0.94, a = 1 },
        CHANNEL       = GetChatTypeColor("CHANNEL", { r = 1.00, g = 0.75, b = 0.75, a = 1 }),
        CLUB          = GetChatTypeColor("COMMUNITIES_CHANNEL", { r = 0.25, g = 0.78, b = 0.94, a = 1 }),
        INSTANCE_CHAT = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
        RAID          = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
        RAID_WARNING  = { r = 1.00, g = 0.28, b = 0.03, a = 1 },
    },
    font = { path = nil, flags = "" },
}

if YapperTable and YapperTable.RegisterTheme then
    YapperTable:RegisterTheme(theme.name, theme)
end

return theme
