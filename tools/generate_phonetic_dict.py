#!/usr/bin/env python3
import re
import os

from phonetics_en import get_phonetic_hash

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
        f.write("if not YapperAPI or not YapperAPI.RegisterDictionary then return end\n\n")
        
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
        f.write(f'YapperAPI:RegisterDictionary("{locale}", function()\n')
        f.write('    local d = {\n')
        if extends:
            f.write(f'        extends = "{extends}",\n')
            f.write('        isDelta = true,\n')
        else:
            f.write('        languageFamily = "en",\n')
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
    dicts_dir_base = os.path.normpath(os.path.join(script_dir, "../Dictionaries"))
    
    print(f"Scanning for dictionaries in {dicts_dir_base}/Yapper_Dict_en*...")
    
    import glob
    all_files = glob.glob(os.path.join(dicts_dir_base, "Yapper_Dict_en*", "Dict_en*.lua"))
    all_files.extend(glob.glob(os.path.join(dicts_dir_base, "Yapper_Dict_en*", "en*.lua")))
    
    # Identify locales vs base
    locales = [os.path.basename(f)[:-4].replace("Dict_", "") for f in all_files if "enBase" not in f and "Dict_enBase" not in f]
    
    # Try to find base_path
    base_path = None
    for f in all_files:
        if "enBase" in f or "Dict_enBase" in f:
            base_path = f
            break
    
    if not locales:
        print("No English locale dictionaries found (e.g., enUS.lua, enGB.lua)!")
        return

    print(f"Found locales: {', '.join(locales)}")
    
    # 2. Extract existing words
    base_existing = extract_words_from_lua(base_path)
    locale_full_sets = {}
    
    for loc in locales:
        # Find the actual path for this locale
        locale_path = None
        for f in all_files:
            if f.endswith(f"{loc}.lua"):
                locale_path = f
                break
        
        if not locale_path:
            print(f"  Cannot find path for {loc}.lua, skipping")
            continue
            
        existing = extract_words_from_lua(locale_path)
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
        loc_path = None
        for f in all_files:
            if f.endswith(f"{loc}.lua"):
                loc_path = f
                break
        write_lua_dict(loc_path, loc, "enBase", delta_list, delta_phon)
    
    print(f"Done! Restructured {len(locales)} dictionaries + enBase successfully.")

if __name__ == "__main__":
    main()
