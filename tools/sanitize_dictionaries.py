#!/usr/bin/env python3
import os
import re
import shutil
import sys
from glob import glob

# We can import from generate_phonetic_dict because we are in the same dir
import generate_phonetic_dict as gen

def normalize_word(word):
    word = word.lower().strip()
    # Strip non-alpha characters to catch things like "dune-coon" or "f.a.g"
    return "".join(c for c in word if c.isalpha())

def get_plurals(word):
    variants = {word + "s", word + "es"}
    if word.endswith("y"):
        variants.add(word[:-1] + "ies")
    return variants

def main():
    bad_words_file = "scratch/filtered-word-lists/bad-word-list-full"
    if not os.path.exists(bad_words_file):
        print(f"Error: {bad_words_file} not found.")
        sys.exit(1)

    base_bad_words = set()
    with open(bad_words_file, "r", encoding="utf-8") as f:
        for line in f:
            w = line.strip().lower()
            if w: base_bad_words.add(w)

    # Expand with plurals
    bad_words = set()
    for w in base_bad_words:
        bad_words.add(w)
        bad_words.update(get_plurals(w))

    print(f"Loaded {len(bad_words)} bad words for sanitization.")

    dicts_parent = "../Dictionaries"
    dict_dirs = glob(os.path.join(dicts_parent, "Yapper_Dict_*"))
    
    for dict_dir in dict_dirs:
        backup_dir = os.path.join(dict_dir, "backup")
        os.makedirs(backup_dir, exist_ok=True)

        lua_files = glob(os.path.join(dict_dir, "*.lua"))
        
        for filepath in lua_files:
            filename = os.path.basename(filepath)
            if filename == "Engine.lua":
                continue
                
            print(f"\nProcessing {filename} in {os.path.basename(dict_dir)}...")
            
            # 1. Backup
            backup_path = os.path.join(backup_dir, filename)
            shutil.copy2(filepath, backup_path)
            print(f"  Backed up to {backup_path}")
            
            # 2. Extract current words
            words = gen.extract_words_from_lua(filepath)
            original_count = len(words)
            print(f"  Extracted {original_count} words.")
            
            if original_count == 0:
                print("  Skipping (no words found).")
                continue
                
            # 3. Filter
            filtered_words = set()
            removed = 0
            for w in words:
                # Check against bad words
                norm = normalize_word(w)
                if norm in bad_words:
                    removed += 1
                else:
                    filtered_words.add(w)
                    
            print(f"  Removed {removed} slurs/bad words.")
            
            # 4. We don't write them back directly here because generate_phonetic_dict 
            # needs to be run anyway to regenerate phonetics. 
            
            # Preserve the file's own registration metadata rather than
            # guessing from the filename: `RegisterDictionary("X")` is the
            # locale key, `extends = "Y"` marks a delta, `languageFamily` is
            # required on bases. (The old code emitted locale "Dict_deDE"
            # and extends="enBase" for the German base dict.)
            with open(filepath, "r", encoding="utf-8") as src:
                content = src.read()
            m = re.search(r'RegisterDictionary\("([^"]+)"', content)
            locale = m.group(1) if m else filename.replace("Dict_", "").replace(".lua", "")
            m = re.search(r'extends\s*=\s*"([^"]+)"', content)
            extends_val = m.group(1) if m else None
            m = re.search(r'languageFamily\s*=\s*"([^"]+)"', content)
            family = m.group(1) if m else "en"

            sorted_words = sorted(list(filtered_words))
            gen.write_lua_dict(filepath, locale, extends_val, sorted_words, {}, family=family)
            print(f"  Wrote sanitized dictionary (phonetics cleared).")

if __name__ == "__main__":
    main()
