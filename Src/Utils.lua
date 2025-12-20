-- Utilities, like string parsing or variable extraction. 
-- Just some handy tools to keep the code clean.
local YapperName, YapperTable = ...
YapperTable.Utils = {}

-- string trim function to strip whitespace from both ends.
function YapperTable.Utils:Trim(s)
    return s:match("^%s*(.-)%s*$") -- why so much regex???
end

-- Find the start of the last word in a string.
function YapperTable.Utils:FindLastWord(s)
    -- regex: "one or more non-space characters"
    return string.find(s, "[^%s]+$") -- side note I hate regex
end
