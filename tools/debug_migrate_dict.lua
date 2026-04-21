-- Verification of User Dictionary Migration Shim
_G.YapperDB = {
    Spellcheck = {
        Dict = {
            AddedWords = { "Legacy1", "Legacy2" },
            IgnoredWords = { "Ignore1" },
            _rev = 1,
        }
    }
}

local YapperName, YapperTable = "Yapper", { Spellcheck = {} }
local f = assert(loadfile("Src/Spellcheck.lua"))
f(YapperName, YapperTable)

local SC = YapperTable.Spellcheck
print("Initial Store State (Mocking Legacy):")
for k, v in pairs(_G.YapperDB.Spellcheck.Dict) do
    print("  ", k, type(v) == "table" and ("#=" .. #v) or v)
end

local store = SC:GetUserDictStore()

print("\nPost-Migration Store State:")
for k, v in pairs(_G.YapperDB.Spellcheck.Dict) do
    if type(v) == "table" and k == "enBASE" then
        print("  ", k, "{")
        for sk, sv in pairs(v) do
            print("    ", sk, type(sv) == "table" and ("#=" .. #sv) or sv)
        end
        print("  }")
    else
        print("  ", k, v)
    end
end

if _G.YapperDB.Spellcheck.Dict["enBASE"] and #_G.YapperDB.Spellcheck.Dict["enBASE"].AddedWords == 2 then
    print("\nSUCCESS: Migration identified and moved legacy data to enBASE.")
else
    print("\nFAILURE: Migration did not occur correctly.")
end
