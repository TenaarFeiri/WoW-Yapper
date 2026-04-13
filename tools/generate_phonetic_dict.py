#!/usr/bin/env python3
import re
import os

# --- 1. The Parity Hashing Algorithm (Must match Lua exactly) ---
def get_phonetic_hash(word):
    if not word: return ""
    # Convert to uppercase
    hash_str = word.upper()
    
    # Strip non-alphabetic characters (including apostrophes)
    hash_str = re.sub(r'[^A-Z]', '', hash_str)
    
    # Strip duplicate adjacent letters (e.g., "LL" -> "L")
    # Python equivalent of hash = string_gsub(hash, "(%a)%1", "%1") in my Lua code
    hash_str = re.sub(r'([A-Z])\1+', r'\1', hash_str)
    
    # Silent/Variable replacements
    hash_str = hash_str.replace("GHT", "T")
    hash_str = hash_str.replace("PH", "F")
    hash_str = hash_str.replace("KN", "N")
    hash_str = hash_str.replace("GN", "N")
    hash_str = hash_str.replace("WR", "R")
    hash_str = hash_str.replace("CH", "K")
    hash_str = hash_str.replace("SH", "X")
    hash_str = hash_str.replace("C", "K")
    hash_str = hash_str.replace("Q", "K")
    hash_str = hash_str.replace("X", "KS")
    hash_str = hash_str.replace("Z", "S")

    # GH at the end of word often sounds like F (laugh, enough)
    if hash_str.endswith("GH"):
        hash_str = hash_str[:-2] + "F"
    else:
        hash_str = hash_str.replace("GH", "") # Silent GH (night, through)
    
    if not hash_str: return ""
    
    # Keep the first letter, strip vowels from the rest
    first_char = hash_str[0]
    rest = hash_str[1:]
    rest = re.sub(r'[AEIOUY]', '', rest)
    
    return first_char + rest

# --- 2. Lua Parser/Writer Helpers ---
def extract_words_from_lua(filepath):
    """Extracts strings from a Yapper dictionary file (handles both flat and chunked formats)."""
    if not os.path.exists(filepath):
        print(f"Warning: File not found: {filepath}")
        return set()
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    words = set()
    
    # 1. Look for chunked format: local function getWords_N() return { "w1", "w2" } end
    chunks = re.findall(r'local function getWords_\d+\(\)\s+return \{([^}]+)\}\s+end', content, re.DOTALL)
    if chunks:
        for chunk in chunks:
            words.update(re.findall(r'"([^"]+)"', chunk))
        if words: return words
        
    # 2. Look for old flat format: words = { "w1", "w2" }
    match = re.search(r'words\s*=\s*\{([^}]+)\}', content, re.DOTALL)
    if match:
        words.update(re.findall(r'"([^"]+)"', match.group(1)))
    
    return words

def write_lua_dict(filepath, locale, extends, words_list, phonetics_dict):
    """Writes the optimized dictionary format with chunked loading for Lua 5.1 constant table limits."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(f"-- Generated Yapper Dictionary\n")
        f.write(f"-- Locale: {locale}\n\n")
        f.write("local _, YapperTable = ...\n")
        f.write("if not YapperTable or not YapperTable.Spellcheck then return end\n\n")
        
        # 1. Chunked Words (Safe limit ~15k unique strings per function)
        WORD_CHUNK_SIZE = 15000
        for i in range(0, len(words_list), WORD_CHUNK_SIZE):
            chunk = words_list[i:i+WORD_CHUNK_SIZE]
            chunk_idx = i // WORD_CHUNK_SIZE
            f.write(f"local function getWords_{chunk_idx}()\n")
            f.write("    return {\n        ")
            formatted_words = [f'"{w}"' for w in chunk]
            for j in range(0, len(formatted_words), 6):
                line = formatted_words[j:j+6]
                f.write(", ".join(line))
                if j + 6 < len(formatted_words):
                    f.write(",\n        ")
            f.write("\n    }\nend\n\n")
            
        # 2. Chunked Phonetics (Safe limit ~10k keys/tables per function)
        PHON_CHUNK_SIZE = 10000
        phon_items = sorted(phonetics_dict.items())
        for i in range(0, len(phon_items), PHON_CHUNK_SIZE):
            chunk = phon_items[i:i+PHON_CHUNK_SIZE]
            chunk_idx = i // PHON_CHUNK_SIZE
            f.write(f"local function getPhonetics_{chunk_idx}()\n")
            f.write("    return {\n")
            for p_hash, indices in chunk:
                idx_str = ', '.join(str(idx) for idx in indices)
                f.write(f'        ["{p_hash}"] = {{{idx_str}}},\n')
            f.write("    }\nend\n\n")

        # 3. Aggregation Registry
        f.write(f'YapperTable.Spellcheck:RegisterDictionary("{locale}", function()\n')
        f.write('    local d = {\n')
        if extends:
            f.write(f'        extends = "{extends}",\n')
            f.write('        isDelta = true,\n')
        f.write('        words = {},\n')
        f.write('        phonetics = {},\n')
        f.write('    }\n')
        
        # Fill words from chunks
        f.write('    local tinsert = table.insert\n')
        for i in range(0, len(words_list), WORD_CHUNK_SIZE):
            f.write(f'    for _, w in ipairs(getWords_{i//WORD_CHUNK_SIZE}()) do tinsert(d.words, w) end\n')
        
        # Fill phonetics from chunks
        for i in range(0, len(phon_items), PHON_CHUNK_SIZE):
            f.write(f'    for h, m in pairs(getPhonetics_{i//PHON_CHUNK_SIZE}()) do d.phonetics[h] = m end\n')
            
        f.write('    return d\n')
        f.write('end)\n')

# --- 3. Main Build Logic ---
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dicts_dir = os.path.normpath(os.path.join(script_dir, "../Src/Spellcheck/Dicts"))
    
    print(f"Scanning for dictionaries in {dicts_dir}...")
    
    # 1. Find all en*.lua files
    all_files = [f for f in os.listdir(dicts_dir) if f.startswith("en") and f.endswith(".lua")]
    
    # Identify locales vs base
    locales = [f[:-4] for f in all_files if f != "enBase.lua"]
    base_path = os.path.join(dicts_dir, "enBase.lua")
    
    if not locales:
        print("No English locale dictionaries found (e.g., enUS.lua, enGB.lua)!")
        return

    print(f"Found locales: {', '.join(locales)}")
    
    # 2. Extract existing words
    base_existing = extract_words_from_lua(base_path)
    locale_full_sets = {}
    
    for loc in locales:
        loc_path = os.path.join(dicts_dir, f"{loc}.lua")
        existing = extract_words_from_lua(loc_path)
        # Combine locale words with existing base to find "True Full Set" for this locale
        locale_full_sets[loc] = existing.union(base_existing)
    
    # 3. Calculate the new Universal Base (Intersection of ALL found locales)
    # We start with the set from the first locale and intersect with the rest
    first_loc = locales[0]
    base_words_set = locale_full_sets[first_loc]
    for i in range(1, len(locales)):
        base_words_set = base_words_set.intersection(locale_full_sets[locales[i]])
    
    print(f"Total unique words across all locales: {len(set().union(*locale_full_sets.values()))}")
    print(f"  -> Universal Base: {len(base_words_set)} words")

    def process_dataset(word_set, index_offset=0):
        sorted_words = sorted(list(word_set))
        phonetics = {}
        # Lua tables are 1-indexed; delta dicts offset past the base to avoid collision
        for idx, word in enumerate(sorted_words, start=1 + index_offset):
            p_hash = get_phonetic_hash(word)
            if not p_hash: continue
            if p_hash not in phonetics:
                phonetics[p_hash] = []
            phonetics[p_hash].append(idx)
        return sorted_words, phonetics

    # 4. Generate enBase
    print("Hashing and writing enBase.lua...")
    base_list, base_phon = process_dataset(base_words_set)
    write_lua_dict(base_path, "enBase", None, base_list, base_phon)

    base_count = len(base_list)
    print(f"  -> Base has {base_count} words; deltas will start indices at {base_count + 1}")

    # 5. Generate individualized Deltas (indices offset past base to avoid collision)
    for loc in locales:
        print(f"Hashing and writing {loc}.lua delta...")
        delta_set = locale_full_sets[loc] - base_words_set
        delta_list, delta_phon = process_dataset(delta_set, index_offset=base_count)
        loc_path = os.path.join(dicts_dir, f"{loc}.lua")
        write_lua_dict(loc_path, loc, "enBase", delta_list, delta_phon)
    
    print(f"Done! Restructured {len(locales)} dictionaries + enBase successfully.")

if __name__ == "__main__":
    main()
