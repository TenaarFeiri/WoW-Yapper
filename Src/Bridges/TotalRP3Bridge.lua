-- ---------------------------------------------------------------------------
-- Total RP 3 Bridge
-- ---------------------------------------------------------------------------
-- Bridges TRP3 features. Can/May be expanded as necessary.
-- ---------------------------------------------------------------------------

local C_AddOns = C_AddOns or {}
local function Load()
    -- We only need to register the protocols if Yapper API is available.
    if not _G.YapperAPI then return end

    -- Declare the TRP3 link protocol as a known, first-class link type in Yapper.
    YapperAPI:RegisterLinkProtocol("addon:totalrp3")

    -- Register the unformatted TRP3 text format as an atomic token.
    -- This prevents Yapper's chunker from splitting "[TRP3:Identifier]" links.
    YapperAPI:RegisterAtomicPattern("%[TRP3:[^%]]+%]")
end

-- Wait for PLAYER_LOGIN to ensure APIs are available, but since we don't
-- strictly need TRP3 to be loaded for Yapper to know about the pattern,
-- we can just register it directly.
Load()
