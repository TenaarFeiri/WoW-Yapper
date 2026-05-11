local function HashWord(word)
    local h = 5381
    for i = 1, #word do
        local b = string.byte(word, i)
        h = ((h * 32) + h + b) % 4294967296
    end
    return h
end

print("Hash of 'dog':", HashWord("dog"))
print("Hash of 'Dog':", HashWord("Dog"))
