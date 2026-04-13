import os
import re
import sys
from collections import defaultdict

# Regex for common Lua definitions
RE_DEFS = {
    'local_func': re.compile(r"local\s+function\s+([a-zA-Z0-9_]+)"),
    'member_func': re.compile(r"function\s+[a-zA-Z0-9_]+[:.]([a-zA-Z0-9_]+)"),
    'assign_func': re.compile(r"[a-zA-Z0-9_]+[.]([a-zA-Z0-9_]+)\s*=\s*function"),
    'local_var': re.compile(r"local\s+([a-zA-Z0-9_]+)\s*="),
}

# Standard words to exclude from the orphan report
IGNORE_WORDS = {
    "YapperTable", "YapperDB", "YapperLocalConf", "YapperName", "config", "cfg", "root",
    "self", "this", "value", "text", "event", "data", "args", "i", "j", "k", "v",
    "r", "g", "b", "a", "x", "y", "z", "w", "h", "fs", "tex", "tbl", "cur", "prev",
}

def clean_line(line):
    # Remove strings to avoid false positives
    line = re.sub(r'\"[^\"]*\"', ' STR ', line)
    line = re.sub(r'\'[^\']*\'', ' STR ', line)
    # Remove single-line comments
    line = line.split('--')[0]
    return line

def analyze_project(search_dir):
    all_defs = defaultdict(list)
    word_counts = defaultdict(int)
    
    for root, _, files in os.walk(search_dir):
        for file in files:
            if not file.endswith('.lua'): continue
            path = os.path.join(root, file)
            
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
                
                # Multi-line comment removal
                content_no_multi = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
                
                lines = content_no_multi.splitlines()
                for i, line in enumerate(lines, 1):
                    cleaned = clean_line(line)
                    if not cleaned.strip(): continue
                    
                    # Usages
                    words = re.findall(r'\b([a-zA-Z0-9_]+)\b', cleaned)
                    for w in words:
                        word_counts[w] += 1
                    
                    # Definitions
                    for kind, regex in RE_DEFS.items():
                        match = regex.search(cleaned)
                        if match:
                            name = match.group(1)
                            if name not in IGNORE_WORDS and len(name) > 3:
                                all_defs[name].append((path, i))

    return all_defs, word_counts

def main():
    root_dir = './'
    if not os.path.exists(root_dir): print("Path error"); return

    # Definitions are still primarily in Src/
    # but we scan the whole project for references (excluding docs)
    all_defs, word_counts = analyze_project(root_dir)
    
    # Audit logic: definition sites vs total occurrences
    orphans = []
    for name, locs in all_defs.items():
        total = word_counts[name]
        defs = len(locs)
        if total <= defs:
            orphans.append((name, locs, total, defs))

    print("\n--- [ STRUCTURAL AUDIT: ORPHANS ] ---")
    print(f"{'Name':<35} | {'Refs':<5} | {'Defs':<4} | Location")
    print("-" * 75)
    
    # Sort and filter
    orphans.sort(key=lambda x: (x[1][0][0], x[1][0][1]))
    actual_orphans = 0
    for name, locs, total, defs in orphans:
        # Ignore obvious scratch vars or things used exactly 0 times globally (genuine dead code)
        if name.startswith("_") and total == defs: continue
        
        loc_str = f"{os.path.basename(locs[0][0])}:{locs[0][1]}"
        print(f"{name:<35} | {total:<5} | {defs:<4} | {loc_str}")
        actual_orphans += 1

    print(f"\nAudit complete. Total Structural Orphans: {actual_orphans}")
    
    # Targeted Verification for British English Sweep
    print("\n--- [ LINGUISTIC SYNC VERIFICATION ] ---")
    br_check = ["NormaliseWord", "NormaliseVowels", "NormaliseBnetTarget", "NormaliseMarker", "Tokenise"]
    for word in br_check:
        count = word_counts[word]
        num_defs = len(all_defs[word])
        status = "OK" if count > num_defs else "ORPHAN?"
        print(f"{word:<25} | Total: {count:<4} | Defs: {num_defs:<4} | Status: {status}")

if __name__ == "__main__":
    main()
