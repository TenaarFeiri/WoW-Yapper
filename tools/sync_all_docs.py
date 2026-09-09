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
    "State.lua": ("Internals.md", "## State"),
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
    "EditBox/Handlers.lua": ("Internals.md", "## EditBox.Handlers"),
    "EditBox/Keybinds.lua": ("Internals.md", "## EditBox.Keybinds"),
    "EditBox/Overlay.lua": ("Internals.md", "## EditBox.Overlay"),
    "Hooks/Hub.lua": ("Internals.md", "## Hooks.Hub"),
    "Hooks/ShowHide.lua": ("Internals.md", "## Hooks.ShowHide"),
    "Hooks/Label.lua": ("Internals.md", "## Hooks.Label"),
    "Hooks/History.lua": ("Internals.md", "## Hooks.History"),
    "Hooks/Slash.lua": ("Internals.md", "## Hooks.Slash"),
    "Hooks/BlizzardHookCtl/10_ProxyBackground.lua": ("Internals.md", "## Hooks.Blizzard"),
    "Hooks/BlizzardHookCtl/20_EditBoxHooks.lua": ("Internals.md", "## Hooks.Blizzard"),
    "Hooks/BlizzardHookCtl/30_ChatFrameHooks.lua": ("Internals.md", "## Hooks.Blizzard"),
    "Hooks/BlizzardHookCtl/40_IMWindowMemory.lua": ("Internals.md", "## Hooks.Blizzard"),
    "EditBoxCompat.lua": ("Internals.md", "## EditBoxCompat"),
    "Spellcheck.lua": ("Internals.md", "## Spellcheck"),
    "Spellcheck/Engine.lua": ("Internals.md", "## Spellcheck.Engine"),
    "Spellcheck/UI.lua": ("Internals.md", "## Spellcheck.UI"),
    "Spellcheck/Adaptive.lua": ("Internals.md", "## Spellcheck.YAS"),
    "Chat.lua": ("Internals.md", "## Chat"),
    "Multiline.lua": ("Internals.md", "## Multiline"),
    "Autocomplete.lua": ("Internals.md", "## Autocomplete"),
    "Emotes.lua": ("Internals.md", "## Emotes"),
    "History.lua": ("Internals.md", "## History"),
    "Theme.lua": ("Internals.md", "## Theme"),
    "Router.lua": ("Internals.md", "## Router"),
    "Chunking.lua": ("Internals.md", "## Chunking"),
    "Error.lua": ("Internals.md", "## Utilities"),
}


def get_doc_target(rel_lua_path):
    """Resolve the documentation target for a Lua file path.

    Explicit entries in FILE_SECTION_MAP win. Unknown modules fall back to a
    section name derived from their path so new folders remain self-describing.
    """
    if rel_lua_path in FILE_SECTION_MAP:
        return FILE_SECTION_MAP[rel_lua_path]

    rel_path = rel_lua_path[:-4] if rel_lua_path.endswith(".lua") else rel_lua_path
    parts = [part for part in rel_path.split("/") if part]
    if not parts:
        return None

    if parts[0] == "Policies":
        return ("Internals.md", "## Policies")

    if parts[0] == "Bridges":
        return ("Internals.md", f"## {parts[-1]}")

    if len(parts) > 1:
        return ("Internals.md", f"## {'.'.join(parts)}")

    return ("Internals.md", f"## {parts[0]}")

# Regex to find links like ([`../Path/File.lua#L123`](../Path/File.lua#L123))
# or ([`File.lua#L123`](`../File.lua#L123`))
LINK_RE = re.compile(r'\(\[`([^#]+)#L(\d+)`\]\(`?([^#`)]+)`?#L(\d+)`?\)\)')

# Functions that are intentionally undocumented (internal implementation details)
IGNORED_FUNCTIONS = {
    "Migrations:MigrateYALLMToYAS",
    "Migrations:MigrateChannelColorMode",
    "Migrations:RunMigrations",
    "Migrations:MarkCompleted",
    "Migrations:IsCompleted",
    "Bridge:IsYapperCompatAvailable",
    "EditBox:RecordTabChannel",
    "Keybinds:CreateSecureButtons",
    "Keybinds:RegisterOverrides",
    "Keybinds:UnregisterOverrides",
    "Keybinds:RefreshOverrides",
    "Keybinds:IsRegistered",
    "Keybinds:IsPendingRegistration",
    "Keybinds:CompletePendingRegistration",
    "Interface:RegisterInternalCategories",
}

def legacy_find_line_in_file(file_path, search_term):
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

# Some bridge modules intentionally use a short local receiver (`Bridge`) while
# their documented/public identity is the module name. Keep the aliasing
# automatic for Bridges/<ModuleName>.lua as new integrations are added.
def documentation_table_names(rel_lua_path, source_table):
    names = {source_table}
    if "." in source_table:
        names.add(source_table.split(".")[-1])
    rel_path = rel_lua_path.replace(os.sep, "/")
    if rel_path.startswith("Bridges/") and source_table == "Bridge":
        names.add(os.path.splitext(os.path.basename(rel_path))[0])
    return names


def documentation_table_name(rel_lua_path, source_table):
    rel_path = rel_lua_path.replace(os.sep, "/")
    if rel_path.startswith("Bridges/") and source_table == "Bridge":
        return os.path.splitext(os.path.basename(rel_path))[0]
    return source_table


def _source_lines(file_path):
    if not os.path.exists(file_path):
        return []
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        return f.readlines()


def find_definition_lines(file_path, search_term, receiver=None):
    """Return exact 1-based definition lines for a documented identifier.

    Do not fall back to arbitrary word occurrences: a link must resolve to a
    function or assignment definition, not prose or an unrelated expression.
    """
    lines = _source_lines(file_path)
    if not lines:
        return []

    term = re.escape(search_term)
    patterns = []
    if receiver:
        recv = re.escape(receiver)
        patterns.extend([
            re.compile(rf"^\s*function\s+{recv}[:.]{term}\s*\("),
            re.compile(rf"^\s*{recv}[.:]{term}\s*=\s*"),
        ])
    patterns.extend([
        re.compile(rf"^\s*function\s+[A-Za-z0-9_.]+[:.]{term}\s*\("),
        re.compile(rf"^\s*(?:local\s+)?function\s+{term}\s*\("),
        re.compile(rf"^\s*[A-Za-z0-9_.:]+[.:]{term}\s*=\s*"),
        re.compile(rf"^\s*local\s+{term}\s*=\s*"),
        re.compile(rf"^\s*{term}\s*=\s*"),
    ])

    hits = []
    for line_no, raw_line in enumerate(lines, 1):
        code = raw_line.split("--", 1)[0]
        if any(pattern.search(code) for pattern in patterns):
            hits.append(line_no)
    return sorted(set(hits))


def find_unique_definition_line(file_path, search_term, receiver=None):
    hits = find_definition_lines(file_path, search_term, receiver)
    return hits[0] if len(hits) == 1 else None


def extract_link_identifier(line_text, link_offset):
    """Extract a signature symbol without mistaking prose code for one.

    Prefer a method/function signature anywhere before the link. For entries
    without parentheses, only accept a standalone symbol immediately adjacent
    to the link. This prevents descriptions such as `or 0` or `{id, label}`
    from becoming relocation keys.
    """
    prefix = line_text[:link_offset]
    candidates = list(re.finditer(r'`([^`]+)`', prefix))
    for candidate in reversed(candidates):
        content = candidate.group(1)
        if "→" not in content:
            continue
        symbol = re.match(r'\s*([A-Za-z_][\w.:]*)\s*(?:\(|→)', content)
        if symbol:
            full = symbol.group(1)
            parts = re.split(r'[:.]', full)
            return parts[-1], (parts[-2] if len(parts) > 1 else None), True

    # Plain symbols are useful for relocating field links, but are not
    # confident enough to auto-create a [MISSING] annotation if no assignment
    # definition exists at the referenced line.
    adjacent = re.search(r'`([A-Za-z_][\w.:]*)`\s*$', prefix)
    if adjacent:
        full = adjacent.group(1)
        parts = re.split(r'[:.]', full)
        return parts[-1], (parts[-2] if len(parts) > 1 else None), False

    return None, None, False


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
    return_list = []
    
    for line in comment_lines:
        if line.startswith("@param"):
            # Extract param name (usually the first word)
            m = re.search(r'@param\s+([a-zA-Z0-9_?]+)', line)
            if m: params.append(m.group(1))
        elif line.startswith("@return"):
            # Extract type (usually the first word)
            m = re.search(r'@return\s+([a-zA-Z0-9_? |/]+)', line)
            if m: return_list.append(m.group(1).strip())
        elif not line.startswith("@") and summary == "No description provided." and line:
            summary = line
            
    returns = ", ".join(return_list) if return_list else "nil"
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
    new_entry = f"  - [NEW] `{table}:{func}{signature}`: {summary} ([`../Src/{lua_rel_path}#L{line_no}`](../Src/{lua_rel_path}#L{line_no}))\n"
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
            
            search_term, receiver, confident = extract_link_identifier(
                line_text, match.start() - line_start)
            if not search_term or search_term.lower() == "lua":
                continue

            lua_path = os.path.normpath(os.path.join(DOCS_DIR, url_path.split('#')[0]))
            definition_lines = find_definition_lines(lua_path, search_term, receiver)
            new_line_no = definition_lines[0] if len(definition_lines) == 1 else None

            if len(definition_lines) > 1:
                if confident:
                    print(f"[{filename}] Skipped ambiguous {search_term}: "
                          f"{', '.join('L' + str(line) for line in definition_lines)}")
                continue

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
                # Only confident signatures may create [MISSING] annotations.
                # Plain field/prose references are bounds-checked but left
                # untouched when no exact definition is available.
                if not confident:
                    continue
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

    # Re-read after link synchronization so orphan detection evaluates the
    # documentation that will actually be written, not the pre-sync snapshot.
    all_docs = ""
    for filename in md_files:
        with open(os.path.join(DOCS_DIR, filename), "r", encoding="utf-8") as f:
            all_docs += f.read()

    # 2. Orphan detection and optional injection
    print("\n--- Scanning for potentially undocumented functions ---")
    for root, dirs, files in os.walk(SRC_DIR):
        for filename in sorted(files):
            if not filename.endswith(".lua"): continue
            
            lua_path = os.path.join(root, filename)
            rel_lua_path = os.path.relpath(lua_path, SRC_DIR).replace(os.sep, '/')
            
            with open(lua_path, "r", encoding="utf-8", errors="ignore") as f:
                lua_content = f.read()

            # Find all function Table:Method (handles nested tables like Table.Sub:Method)
            functions = re.findall(r'function\s+([a-zA-Z0-9_.:]+)[:.]([a-zA-Z0-9_]+)', lua_content)
            for table, func in functions:
                if func.startswith("_"): continue # Ignore internal-convention helpers
                
                # Check if this function is in the ignore list
                full_func_name = f"{table}:{func}"
                if full_func_name in IGNORED_FUNCTIONS:
                    continue
                
                # Check if documented under the source receiver, its module
                # alias, or the method name itself.
                documented_tables = documentation_table_names(rel_lua_path, table)
                patterns = []
                for documented_table in documented_tables:
                    patterns.extend([
                        re.compile(r'`' + re.escape(f"{documented_table}:{func}") + r'(\(|`)'),
                        re.compile(r'`' + re.escape(f"{documented_table}.{func}") + r'(\(|`)'),
                    ])
                patterns.append(re.compile(r'`' + re.escape(func) + r'(\(|`)'))

                is_documented = any(pattern.search(all_docs) for pattern in patterns)

                if not is_documented:
                    print(f"[?] Potential orphan in {rel_lua_path}: {table}:{func}")
                    if args.inject:
                        # The regex already found the exact definition line;
                        # do not perform a loose word search for it again.
                        line_no = find_unique_definition_line(lua_path, func, table)
                        if not line_no:
                            print(f"[{rel_lua_path}] Skipped ambiguous definition for {table}:{func}")
                            continue

                        summary, signature = extract_comment_info(lua_path, line_no)

                        target = get_doc_target(rel_lua_path)
                        if target:
                            target_md, target_section = target
                            doc_table = documentation_table_name(rel_lua_path, table)
                            inject_to_doc(target_md, target_section, doc_table, func, rel_lua_path, line_no, summary, signature)
