local YapperTable = { 
    Config = { 
        System = { DEBUG = true }, 
        Spellcheck = { Enabled = true, MaxSuggestions = 4, Dictionary = "enBase" } 
    },
    Utils = {
        Print = function(self, kind, ...) print("[" .. kind .. "]", ...) end
    }
}

local chunk = assert(loadfile("Src/Spellcheck.lua"))
chunk("Src/Spellcheck.lua", YapperTable)
local Spellcheck = YapperTable.Spellcheck

local baseFunc = assert(loadfile("Src/Spellcheck/Dicts/enBase.lua"))
baseFunc(nil, YapperTable)

local builder = Spellcheck.DictionaryBuilders["enBase"]
local success, err = pcall(builder)
if not success then
    print("BUILDER ERROR: ", err)
else
    print("Builder success")
    Spellcheck:RegisterDictionary("enBase", err)
end

print("Dict present: ", Spellcheck.Dictionaries["enBase"] ~= nil)
