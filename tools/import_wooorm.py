#!/usr/bin/env python3
import os
import argparse
import subprocess
import re
import importlib

def extract_base_words(filepath):
    """Extracts strings from a Yapper dictionary file (used for extracting enBase)."""
    if not os.path.exists(filepath):
        print(f"Warning: Base file not found at {filepath}. Returning empty set.")
        return set()
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    words = set()
    chunks = re.findall(r'local function getWords_\d+\(\)\s+return \{([^}]+)\}\s+end', content, re.DOTALL)
    if chunks:
        for chunk in chunks:
            words.update(re.findall(r'"([^"]+)"', chunk))
        if words: return words
        
    match = re.search(r'words\s*=\s*\{([^}]+)\}', content, re.DOTALL)
    if match:
        words.update(re.findall(r'"([^"]+)"', match.group(1)))
    return words

def run_unmunch(dic_path, aff_path):
    """Uses the system 'unmunch' command to expand a hunspell dictionary."""
    print(f"Running unmunch on {dic_path} with {aff_path}...")
    try:
        # Run unmunch and capture output. It outputs to stdout.
        # unmunch can output invalid utf-8 if dicts are bad, so we use replace.
        result = subprocess.run(['unmunch', dic_path, aff_path], 
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, errors='replace')
        
        if result.returncode != 0:
            print(f"unmunch error: {result.stderr}")
            return None
        
        # Split output into words
        raw_words = result.stdout.splitlines()
        
        # Clean up words: remove those with digits or non-alphabetics that Yapper ignores
        clean_words = set()
        for w in raw_words:
            w = w.strip()
            # Yapper's engine filters words with numbers/spaces prior to processing.
            # We allow a-z, A-Z, apostrophe, and all Unicode alphabetic characters.
            if not w or re.search(r'[^a-zA-Z\'\u00C0-\u017F]', w):
                continue
            clean_words.add(w)
            
        print(f"unmunch produced {len(clean_words)} clean, usable words.")
        return clean_words

    except FileNotFoundError:
        print("ERROR: 'unmunch' command not found. Please install hunspell-tools.")
        return None

def write_yapper_delta_dict(out_path, locale, extends, words_list, phonetics_dict):
    """Writes the optimized dictionary format for Lua 5.1 constant limits."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(f"-- Generated Yapper Dictionary\n")
        f.write(f"-- Locale: {locale}\n")
        f.write(f"-- This file is part of the Yapper_Dict_{locale} LOD addon.\n")
        f.write(f"-- Registration is via YapperAPI; do NOT require YapperTable directly.\n\n")
        
        # Chunked Words
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
            
        # Chunked Phonetics
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

        # Registration Builder
        f.write(f'YapperAPI:RegisterDictionary("{locale}", (function()\n')
        f.write('    local d = {\n')
        f.write(f'        languageFamily = "{locale[:2].lower()}",\n')
        if extends:
            f.write(f'        extends        = "{extends}",\n')
            f.write('        isDelta        = true,\n')
        f.write('        words          = {},\n')
        f.write('        phonetics      = {},\n')
        f.write('    }\n')
        
        f.write('    local tinsert = table.insert\n')
        for i in range(0, len(words_list), WORD_CHUNK_SIZE):
            f.write(f'    for _, w in ipairs(getWords_{i//WORD_CHUNK_SIZE}()) do tinsert(d.words, w) end\n')
        
        for i in range(0, len(phon_items), PHON_CHUNK_SIZE):
            f.write(f'    for h, m in pairs(getPhonetics_{i//PHON_CHUNK_SIZE}()) do d.phonetics[h] = m end\n')
            
        f.write('    return d\n')
        f.write('end)())\n')

def main():
    parser = argparse.ArgumentParser(description="Convert a wooorm Hunspell dictionary into a Yapper LOD Lua dictionary.")
    parser.add_argument('--locale', required=True, help="Output locale name (e.g., enAU, deDE).")
    parser.add_argument('--family', required=True, help="Language family ID to load correct phonetics engine (e.g., en, de).")
    parser.add_argument('--dic', required=True, help="Path to wooorm .dic file.")
    parser.add_argument('--aff', required=True, help="Path to wooorm .aff file.")
    parser.add_argument('--base', required=False, help="Optional: Path to base .lua dictionary to generate a delta (e.g. enBase.lua).")
    args = parser.parse_args()

    # 1. Dynamically load the language-specific phonetic hashing logic
    phonetics_module_name = f"phonetics_{args.family}"
    try:
        phonetics_mod = importlib.import_module(phonetics_module_name)
        get_phonetic_hash = phonetics_mod.get_phonetic_hash
    except ImportError:
        print(f"ERROR: Could not load phonetic engine '{phonetics_module_name}.py'. Ensure it exists in tools/.")
        return

    # 2. Extract Base Words (if generating a Delta)
    base_words_set = set()
    extends_name = None
    base_count = 0
    if args.base:
        print(f"Loading base words from {args.base} to calculate delta...")
        base_words_set = extract_base_words(args.base)
        base_count = len(base_words_set)
        # Try to infer extends name from filename if standard naming is used
        fname = os.path.basename(args.base)
        extends_name = fname.replace("Dict_", "").replace(".lua", "")
        print(f"Base dictionary loaded with {base_count} words. Extends context: {extends_name}")

    # 3. Generate raw flat list from Hunspell .dic + .aff via unmunch
    target_words_set = run_unmunch(args.dic, args.aff)
    if target_words_set is None:
        return

    # 4. Compute Delta (or keep full set if not extending)
    if args.base:
        delta_set = target_words_set - base_words_set
        print(f"Calculated Delta: {len(delta_set)} new words to add over base.")
        process_set = delta_set
        index_offset = base_count
    else:
        print(f"Generating full base dictionary ({len(target_words_set)} words).")
        process_set = target_words_set
        index_offset = 0

    sorted_words = sorted(list(process_set))
    phonetics_dict = {}

    # 5. Phonetize
    print(f"Applying '{args.family}' phonetic rules to {len(sorted_words)} words...")
    for idx, word in enumerate(sorted_words, start=1 + index_offset):
        p_hash = get_phonetic_hash(word)
        if not p_hash: continue
        if p_hash not in phonetics_dict:
            phonetics_dict[p_hash] = []
        phonetics_dict[p_hash].append(idx)

    # 6. Write Output
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", f"Dictionaries/Yapper_Dict_{args.locale}")
    out_path = os.path.join(out_dir, f"Dict_{args.locale}.lua")
    
    print(f"Writing to {out_path}...")
    write_yapper_delta_dict(out_path, args.locale, extends_name, sorted_words, phonetics_dict)
    print("Done!")

if __name__ == "__main__":
    main()
