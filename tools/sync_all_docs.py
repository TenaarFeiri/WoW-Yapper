#!/usr/bin/env python3
import re
import os
import argparse

# Root directory of the project
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SRC_DIR = os.path.join(ROOT_DIR, "Src")
DOCS_DIR = os.path.join(ROOT_DIR, "Documentation")

# Mapping from Lua file (relative to Src/) to Markdown section in Internals.md
FILE_SECTION_MAP = {
    "API.lua": ("API.md", "## Public API"), # Special case: separate file
    "Core.lua": ("Internals.md", "## Core"),
    "Utils.lua": ("Internals.md", "## Utilities"),
    "Events.lua": ("Internals.md", "## Event System"),
    "Queue.lua": ("Internals.md", "## Queue"),
    "Interface.lua": ("Internals.md", "## Interface"),
    "Interface/Config.lua": ("Internals.md", "## Interface.Config"),
    "Interface/Pages.lua": ("Internals.md", "## Interface.Pages"),
    "Interface/Schema.lua": ("Internals.md", "## Interface.Schema"),
    "Interface/Widgets.lua": ("Internals.md", "## Interface.Widgets"),
    "Interface/Window.lua": ("Internals.md", "## Interface.Window"),
    "IconGallery.lua": ("Internals.md", "## IconGallery"),
    "EditBox.lua": ("Internals.md", "## EditBox"),
    "EditBox/SkinProxy.lua": ("Internals.md", "## EditBox.SkinProxy"),
    "EditBox/Hooks.lua": ("Internals.md", "## EditBox"),
    "EditBox/Handlers.lua": ("Internals.md", "## EditBox"),
    "EditBox/Overlay.lua": ("Internals.md", "## EditBox"),
    "EditBoxCompat.lua": ("Internals.md", "## EditBox"),
    "Spellcheck.lua": ("Internals.md", "## Spellcheck"),
    "Spellcheck/Engine.lua": ("Internals.md", "## Spellcheck.Engine"),
    "Spellcheck/UI.lua": ("Internals.md", "## Spellcheck.UI"),
    "Spellcheck/Underline.lua": ("Internals.md", "## Spellcheck.Underline"),
    "Spellcheck/YALLM.lua": ("Internals.md", "## Spellcheck.YALLM"),
    "Chat.lua": ("Internals.md", "## Chat"),
    "Multiline.lua": ("Internals.md", "## Multiline"),
    "Autocomplete.lua": ("Internals.md", "## Autocomplete"),
    "History.lua": ("Internals.md", "## History"),
    "Theme.lua": ("Internals.md", "## Theme"),
    "Router.lua": ("Internals.md", "## Router"),
    "Chunking.lua": ("Internals.md", "## Chunking"),
    "Error.lua": ("Internals.md", "## Utilities"),
}

# Regex to find links like ([`../Path/File.lua#L123`](../Path/File.lua#L123))
# or ([`File.lua#L123`](`../File.lua#L123`))
LINK_RE = re.compile(r'\(\[`([^#]+)#L(\d+)`\]\(`?([^#`)]+)`?#L(\d+)`?\)\)')

def find_line_in_file(file_path, search_term):
    """Searches for a term in a file and returns the 1-indexed line number."""
    if not os.path.exists(file_path):
        return None
    
    # Heuristics for search patterns
    patterns = [
        # Method: function table:name
        re.compile(r'function\s+[a-zA-Z0-9_.:]+[:.]' + re.escape(search_term) + r'\b'),
        # Assignment: table.name = or name =
        re.compile(r'[a-zA-Z0-9_.:]+[:.]' + re.escape(search_term) + r'\s*='),
        # Local assignment: local name =
        re.compile(r'local\s+' + re.escape(search_term) + r'\s*='),
        # Function: function name(
        re.compile(r'function\s+' + re.escape(search_term) + r'\b'),
        # Fallback: just the term
        re.compile(r'\b' + re.escape(search_term) + r'\b'),
    ]

    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        
        for pattern in patterns:
            for i, line in enumerate(lines, 1):
                # Skip comments
                stripped = line.strip()
                if stripped.startswith("--") or stripped.startswith("]]"):
                    continue
                if "--" in line:
                    # Only check part before comment
                    line = line.split("--")[0]

                if pattern.search(line):
                    return i
    return None

def extract_comment_info(lua_path, line_no):
    """Extracts summary and signature from comments above the given line."""
    try:
        with open(lua_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return "No description provided.", "() \u2192 nil"
    
    # Go backwards from line_no-2 (0-indexed)
    idx = line_no - 2
    comment_lines = []
    while idx >= 0:
        line = lines[idx].strip()
        if line.startswith("---") or line.startswith("--"):
            comment_lines.insert(0, line.lstrip("-").strip())
            idx -= 1
        else:
            break
    
    summary = "No description provided."
    params = []
    returns = "nil"
    
    for line in comment_lines:
        if line.startswith("@param"):
            # Extract param name
            m = re.search(r'@param\s+([a-zA-Z0-9_]+)', line)
            if m: params.append(m.group(1))
        elif line.startswith("@return"):
            m = re.search(r'@return\s+([a-zA-Z0-9_ |]+)', line)
            if m: returns = m.group(1).strip()
        elif not line.startswith("@") and summary == "No description provided." and line:
            summary = line
            
    signature = f"({', '.join(params)}) \u2192 {returns}"
    return summary, signature

def inject_to_doc(md_filename, section_header, table, func, lua_rel_path, line_no, summary, signature):
    """Injects a new function entry into the specified markdown section."""
    md_path = os.path.join(DOCS_DIR, md_filename)
    if not os.path.exists(md_path): return
    
    with open(md_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    section_start = -1
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            section_start = i
            break
    
    if section_start == -1:
        # Fallback: append to end of file
        section_start = len(lines)
        lines.append(f"\n{section_header}\n\n- Methods:\n")
        
    # Find the "- Methods:" or "- Description:" list
    target_idx = -1
    for i in range(section_start, len(lines)):
        if "- Methods:" in lines[i]:
            target_idx = i + 1
            break
        if i > section_start + 20: # Don't wander too far
            break
            
    if target_idx == -1:
        # Append to section
        target_idx = section_start + 1
        while target_idx < len(lines) and lines[target_idx].strip() != "" and not lines[target_idx].startswith("##"):
            target_idx += 1
        lines.insert(target_idx, "- Methods:\n")
        target_idx += 1

    # Insert the new method
    # Use British English spelling
    new_entry = f"  - [TODO] `{table}:{func}{signature}`: {summary} ([`../Src/{lua_rel_path}#L{line_no}`](../Src/{lua_rel_path}#L{line_no}))\n"
    lines.insert(target_idx, new_entry)
    
    with open(md_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print(f"[{md_filename}] Injected orphan: {table}:{func}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Synchronise documentation line numbers with source code.")
    parser.add_argument("--inject", action="store_true", help="Automatically inject missing functions into documentation.")
    args = parser.parse_args()

    # Get all markdown files
    md_files = [f for f in os.listdir(DOCS_DIR) if f.endswith(".md")]
    
    # 1. Sync existing links
    all_docs = ""
    total_changes = 0
    for filename in md_files:
        md_path = os.path.join(DOCS_DIR, filename)
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
            all_docs += content # Keep aggregate for orphan detection later

        new_content = content
        matches = list(LINK_RE.finditer(content))
        
        # Process matches in reverse to avoid offset issues
        for match in reversed(matches):
            full_match = match.group(0)
            rel_lua_path = match.group(1)
            old_line_no = match.group(2)
            url_path = match.group(3)
            
            # Identify search term from the same line
            line_start = content.rfind('\n', 0, match.start()) + 1
            line_end = content.find('\n', match.end())
            if line_end == -1: line_end = len(content)
            line_text = content[line_start:line_end]
            
            # Heuristic: Find something that looks like a method or field name
            # 1. Look for content in backticks immediately preceding the link
            prefix = line_text[:match.start() - line_start]
            backtick_matches = re.findall(r'`([^`]+)`', prefix)
            search_term = None
            if backtick_matches:
                # Iterate backwards through backticks to find a symbol, skipping path-like strings
                for candidate in reversed(backtick_matches):
                    if "#L" in candidate or candidate.endswith(".lua"):
                        continue
                    
                    # Try to find Name:Method or Name.Field
                    m = re.search(r'([a-zA-Z0-9_.]+?)[:.]([a-zA-Z0-9_]+)', candidate)
                    if m:
                        search_term = m.group(2)
                        break
                    else:
                        # Just a name
                        m = re.search(r'\b([a-zA-Z0-9_]+)\b', candidate)
                        if m:
                            search_term = m.group(1)
                            break

            if not search_term or search_term.lower() == "lua":
                continue

            lua_path = os.path.normpath(os.path.join(DOCS_DIR, url_path.split('#')[0]))
            new_line_no = find_line_in_file(lua_path, search_term)
            
            if new_line_no:
                # Symbol found. Check if we need to remove [MISSING] flag
                curr_line_start = new_content.rfind('\n', 0, match.start()) + 1
                curr_line_end = new_content.find('\n', match.end())
                if curr_line_end == -1: curr_line_end = len(new_content)
                curr_line_text = new_content[curr_line_start:curr_line_end]
                
                if "[MISSING]" in curr_line_text:
                    restored_line = curr_line_text.replace("[MISSING] ", "")
                    new_content = new_content[:curr_line_start] + restored_line + new_content[curr_line_end:]
                    # Update indices for replacement (though length change is constant)
                    shift = len("[MISSING] ")
                    current_match_start = match.start() - shift
                    current_match_end = match.end() - shift
                else:
                    current_match_start = match.start()
                    current_match_end = match.end()

                if str(new_line_no) != old_line_no:
                    # Replace #LNNN with #LNewNNN
                    new_link = full_match.replace(f"#L{old_line_no}", f"#L{new_line_no}")
                    new_content = new_content[:current_match_start] + new_link + new_content[current_match_end:]
                    total_changes += 1
                    print(f"[{filename}] Updated {search_term} -> L{new_line_no} (was L{old_line_no})")
            else:
                # Symbol missing! Flag it in the text if not already flagged
                curr_line_start = new_content.rfind('\n', 0, match.start()) + 1
                curr_line_end = new_content.find('\n', match.end())
                if curr_line_end == -1: curr_line_end = len(new_content)
                
                curr_line_text = new_content[curr_line_start:curr_line_end]
                if "[MISSING]" not in curr_line_text:
                    # Maintain indentation
                    indent = curr_line_text[:len(curr_line_text) - len(curr_line_text.lstrip())]
                    flagged_line = indent + "[MISSING] " + curr_line_text.lstrip()
                    new_content = new_content[:curr_line_start] + flagged_line + new_content[curr_line_end:]
                    print(f"[{filename}] FLAG MISSING: {search_term} (last seen L{old_line_no})")

        if new_content != content:
            with open(md_path, 'w', encoding='utf-8') as f:
                f.write(new_content)

    print(f"Total documentation links updated: {total_changes}")

    # 2. Orphan detection and optional injection
    print("\n--- Scanning for potentially undocumented functions ---")
    for root, dirs, files in os.walk(SRC_DIR):
        for filename in sorted(files):
            if not filename.endswith(".lua"): continue
            
            lua_path = os.path.join(root, filename)
            rel_lua_path = os.path.relpath(lua_path, SRC_DIR)
            
            with open(lua_path, "r", encoding="utf-8", errors="ignore") as f:
                lua_content = f.read()

            # Find all function Table:Method (handles nested tables like Table.Sub:Method)
            functions = re.findall(r'function\s+([a-zA-Z0-9_.:]+)[:.]([a-zA-Z0-9_]+)', lua_content)
            for table, func in functions:
                if func.startswith("_"): continue # Ignore internal-convention helpers
                
                # Check if documented: `Table:Func`, `Table.Func`, or just `Func` in backticks
                patterns = [
                    re.compile(r'`' + re.escape(f"{table}:{func}") + r'(\(|`)'),
                    re.compile(r'`' + re.escape(f"{table}.{func}") + r'(\(|`)'),
                    re.compile(r'`' + re.escape(func) + r'(\(|`)'),
                    # Special case for normalized table names in docs (e.g. Core: instead of YapperTable.Core:)
                    re.compile(r'`' + re.escape(f"{table.split('.')[-1]}:{func}") + r'(\(|`)'),
                ]
                
                is_documented = False
                for p in patterns:
                    if p.search(all_docs):
                        is_documented = True
                        break
                
                if not is_documented:
                    print(f"[?] Potential orphan in {rel_lua_path}: {table}:{func}")
                    if args.inject:
                        # Find the exact line number for injection
                        line_no = find_line_in_file(lua_path, func)
                        if not line_no: continue
                        
                        summary, signature = extract_comment_info(lua_path, line_no)
                        
                        if rel_lua_path in FILE_SECTION_MAP:
                            target_md, target_section = FILE_SECTION_MAP[rel_lua_path]
                            inject_to_doc(target_md, target_section, table.split('.')[-1], func, rel_lua_path, line_no, summary, signature)
