-- Utilities, like string parsing or variable extraction. 
-- Just some handy tools to keep the code clean.
local YapperName, YapperTable = ...
YapperTable.Utils = {
}
local YapperNameInGreen = "|cFF00FF00"..YapperName.."|r"


-- string trim function to strip whitespace from both ends.
function YapperTable.Utils:Trim(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "Trim", "string", type(s))
        return ""
    end
    return s:match("^%s*(.-)%s*$") -- Use a Lua pattern to return a trimmed string.
end

-- Find the start of the last word in a string.
function YapperTable.Utils:FindLastWord(s)
    if type(s) ~= "string" then
        YapperTable.Error:PrintError("BAD_ARG", "FindLastWord", "string", type(s))
        return nil
    end
    -- pattern: "one or more non-space characters"
    return string.find(s, "[^%s]+$")
end

--- Prints a message from Yapper to the chat frame.
--- @param ... any The message to print.
function YapperTable.Utils:Print(...)
    local Args = {...}
    for i = 1, #Args do
        Args[i] = tostring(Args[i])
    end
    print(YapperNameInGreen .. ": " .. table.concat(Args, " "))
end

-- We can expose utils globally too. They're useful.
_G.YAPPER_UTILS = YapperTable.Utils

function YapperTable.Utils:VerbosePrint(...)
    if YapperTable.Config.System.VERBOSE then
        YapperTable.Utils:Print(...)
    end
end
