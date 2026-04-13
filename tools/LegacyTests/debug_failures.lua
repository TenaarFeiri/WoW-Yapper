local YapperTable = { 
    Config = { 
        System = { DEBUG = false }, 
        Spellcheck = { Enabled = true, MaxSuggestions = 4, Dictionary = "enUS" } 
    },
    Utils = {
        Print = function(self, kind, ...) print("[" .. kind .. "]", ...) end
    }
}

local chunk = assert(loadfile("Src/Spellcheck.lua"))
chunk("Src/Spellcheck.lua", YapperTable)
local Spellcheck = YapperTable.Spellcheck

local function Load(locale)
    local path = string.format("Src/Spellcheck/Dicts/%s.lua", locale)
    local f = assert(loadfile(path))
    f(nil, YapperTable)
    Spellcheck:LoadDictionary(locale)
end

-- Load both enBase and enUS since enUS extends enBase
Load("enBase")
Load("enUS")

local function debugWord(input, expected)
    print(string.format("\n--- DEBUGGING: '%s' -> '%s' ---", input, expected))
    
    local lowerInput = input:lower()
    local phoneticHash = Spellcheck.GetPhoneticHash(lowerInput)
    print("Input Phonetic Hash:", phoneticHash)
    
    local expectedPhonetic = Spellcheck.GetPhoneticHash(expected:lower())
    print("Expected Phonetic Hash:", expectedPhonetic)
    
    if phoneticHash ~= expectedPhonetic then
        print("[!] Phonetic Hash Mismatch!")
    end

    local results = Spellcheck:GetSuggestions(input)
    print(string.format("Found %d suggestions", #results))
    
    local foundAt = "Miss"
    for i, res in ipairs(results) do
        if res.value:lower() == expected:lower() then
            foundAt = i
            print(string.format("[MATCH] Target Found at Rank %d with Score %s (Dist: %s, Bag: %s)", i, tostring(res.score), tostring(res.dist), tostring(res.bag)))
        end
        if i <= 5 then
            print(string.format("  Rank %d: %s (Score: %s)", i, tostring(res.value), tostring(res.score)))
        end
    end
end

debugWord("zhukov'", "Zhukov")
debugWord("oxymoras", "oxymora")
debugWord("reincarnaye", "reincarnate")
debugWord("unspezkable", "unspeakable")
