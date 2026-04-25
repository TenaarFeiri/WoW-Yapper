#!/usr/bin/env python3
import re
import os

# Paths relative to the script's directory (assumed to be tools/)
API_LUA_PATH = "../Src/API.lua"
API_MD_PATH = "../Documentation/API.md"

def sync_docs():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    lua_path = os.path.join(script_dir, API_LUA_PATH)
    md_path = os.path.join(script_dir, API_MD_PATH)

    if not os.path.exists(lua_path):
        print(f"Error: Could not find {lua_path}")
        return
    if not os.path.exists(md_path):
        print(f"Error: Could not find {md_path}")
        return

    # 1. Map functions to line numbers
    # Pattern matches: function YapperAPI:Name(...)
    func_map = {}
    with open(lua_path, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f, 1):
            match = re.search(r'function\s+YapperAPI:([a-zA-Z0-9_]+)', line)
            if match:
                func_name = match.group(1)
                func_map[func_name] = i

    # 2. Update API.md
    # Pattern matches: YapperAPI:Name(...) ([`#LNNN`](../Src/API.lua#LNNN))
    # We look for the function name followed by the specific link format.
    updated_lines = []
    changes = 0
    with open(md_path, 'r', encoding='utf-8') as f:
        for line in f:
            # We look for the YapperAPI method followed by a link
            # Example: - `YapperAPI:GetVersion() → string` ([`#L684`](../Src/API.lua#L684))
            found_func = None
            for func_name in func_map:
                if f"YapperAPI:{func_name}" in line:
                    found_func = func_name
                    break
            
            if found_func:
                new_line_no = func_map[found_func]
                # Regex to replace #L followed by digits in both the link text and the URL
                new_line = re.sub(r'#L\d+', f'#L{new_line_no}', line)
                if new_line != line:
                    changes += 1
                    line = new_line
            
            updated_lines.append(line)

    if changes > 0:
        with open(md_path, 'w', encoding='utf-8') as f:
            f.writelines(updated_lines)
        print(f"Updated {changes} line links in {API_MD_PATH}.")
    else:
        print("No changes needed.")

if __name__ == "__main__":
    sync_docs()
