-- Verification of User Dictionary Migration Shim
-- Legacy flat AddedWords/IgnoredWords are parked under "_legacy" and folded
-- into the first real locale partition that asks (GetUserDict).
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
local f = assert(loadfile("Src/Utils.lua"))
f(YapperName, YapperTable)
local g = assert(loadfile("Src/Spellcheck.lua"))
g(YapperName, YapperTable)

local SC = YapperTable.Spellcheck
print("Initial Store State (Mocking Legacy):")
for k, v in pairs(_G.YapperDB.Spellcheck.Dict) do
    print("  ", k, type(v) == "table" and ("#=" .. #v) or v)
end

-- First call parks the flat lists under _legacy.
local store = SC:GetUserDictStore()

print("\nPost-Park Store State:")
for k, v in pairs(_G.YapperDB.Spellcheck.Dict) do
    if type(v) == "table" then
        print("  ", k, "{")
        for sk, sv in pairs(v) do
            print("    ", sk, type(sv) == "table" and ("#=" .. #sv) or sv)
        end
        print("  }")
    else
        print("  ", k, v)
    end
end

local ok1 = _G.YapperDB.Spellcheck.Dict._legacy
    and #_G.YapperDB.Spellcheck.Dict._legacy.AddedWords == 2
    and _G.YapperDB.Spellcheck.Dict.AddedWords == nil
if ok1 then
    print("\nOK: Flat lists parked under _legacy.")
else
    print("\nFAILURE: Flat lists not parked under _legacy.")
end

-- First real locale request folds _legacy into that partition.
local dict = SC:GetUserDict("enUS")
local ok2 = dict and #dict.AddedWords == 2 and #dict.IgnoredWords == 1
    and _G.YapperDB.Spellcheck.Dict._legacy == nil
if ok2 then
    print("SUCCESS: _legacy folded into enUS; stranded keys drained.")
else
    print("FAILURE: _legacy not folded into the first real locale.")
end

if ok1 and ok2 then os.exit(0) else os.exit(1) end
