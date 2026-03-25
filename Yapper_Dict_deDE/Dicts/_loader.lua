-- Loader marker for LOD dictionary (robust detection)
local locale = 'deDE'
local YapperTable = select(2, ...) or nil
local Y = YapperTable or _G.Yapper

-- If the main addon's Spellcheck exists, expose it on this addon's private table
if YapperTable and Y and Y.Spellcheck then
    YapperTable.Spellcheck = Y.Spellcheck
end

if Y and Y.Spellcheck then
    local sc = Y.Spellcheck
    sc._lodLoaded = sc._lodLoaded or {}
    sc._lodLoaded[locale] = true
    if sc.ScheduleRefresh then sc:ScheduleRefresh() end
    if Y.System and Y.System.DEBUG then
        if C_Timer and C_Timer.NewTimer then
            C_Timer.NewTimer(0.5, function()
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                    DEFAULT_CHAT_FRAME:AddMessage('Yapper: LOD loader ran for '..locale)
                end
            end)
        elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage('Yapper: LOD loader ran for '..locale)
        end
    end
else
    -- Ensure a global flag exists so the main addon can detect that this LOD ran
    _G.Yapper_LOD = _G.Yapper_LOD or {}
    _G.Yapper_LOD[locale] = true
end

