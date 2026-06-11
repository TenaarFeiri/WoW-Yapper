#!/usr/bin/env python3
"""
Dead Code Scanner for WoW-Yapper
Identifies unused variables, uncalled functions, and potentially undefined references.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field
from collections import defaultdict


@dataclass
class SymbolInfo:
    """Information about a symbol (variable or function)."""
    name: str
    file: str
    line: int
    kind: str  # 'local_var', 'global_var', 'local_func', 'global_func', 'reference'
    is_set: bool = False
    is_used: bool = False


@dataclass
class FileAnalysis:
    """Analysis results for a single Lua file."""
    path: str
    locals_defined: Dict[str, SymbolInfo] = field(default_factory=dict)
    locals_used: Set[str] = field(default_factory=set)
    funcs_defined: Dict[str, SymbolInfo] = field(default_factory=dict)
    funcs_called: Set[str] = field(default_factory=set)
    globals_used: Set[str] = field(default_factory=set)
    undefined_refs: List[Tuple[str, int]] = field(default_factory=list)
    # Table tracking for cross-file analysis
    table_assignments: Dict[str, str] = field(default_factory=dict)  # var_name -> table_expr
    table_references: List[Tuple[str, str, int]] = field(default_factory=list)  # (table, member, line)


class LuaParser:
    """Simple regex-based Lua parser for extracting symbols."""
    
    # Regex patterns
    LOCAL_ASSIGN_PATTERN = re.compile(r'\blocal\s+(\w+)\s*[=,]')
    LOCAL_FUNC_PATTERN = re.compile(r'\blocal\s+function\s+(\w+)\s*\(')
    GLOBAL_FUNC_PATTERN = re.compile(r'^\s*function\s+(\w+)\s*\(', re.MULTILINE)
    METHOD_DEF_PATTERN = re.compile(r'function\s+(\w+)[:\.](\w+)\s*\(')
    FUNC_CALL_PATTERN = re.compile(r'\b(\w+)\s*\(')
    IDENTIFIER_PATTERN = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\b')
    COLON_CALL_PATTERN = re.compile(r'\b(\w+):(\w+)\s*\(')
    DOT_ACCESS_PATTERN = re.compile(r'\b(\w+)\.(\w+)\b')
    SETSCRIPT_PATTERN = re.compile(r':SetScript\s*\(\s*["\'](\w+)["\']\s*,\s*(\w+)\s*\)')
    HOOKSECUREFUNC_PATTERN = re.compile(r'hooksecurefunc\s*\([^,]+,\s*["\']?(\w+)["\']?\s*\)')
    # Table assignment: YapperTable.EditBox = {} or local EditBox = YapperTable.EditBox
    TABLE_ASSIGN_PATTERN = re.compile(r'(\w+(?:\.\w+)*)\s*=\s*\{')
    TABLE_REF_PATTERN = re.compile(r'(\w+(?:\.\w+)*)\s*=\s*(\w+(?:\.\w+)*)')
    
    def __init__(self, wow_api_whitelist: Set[str]):
        self.wow_api_whitelist = wow_api_whitelist
        self.lua_keywords = {
            'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
            'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
            'return', 'then', 'true', 'until', 'while', 'self'
        }
    
    def parse_file(self, filepath: str, content: str) -> FileAnalysis:
        """Parse a Lua file and extract symbol information."""
        analysis = FileAnalysis(path=filepath)
        lines = content.split('\n')
        
        for line_num, line in enumerate(lines, 1):
            self._parse_line(line, line_num, analysis, content)
        
        return analysis
    
    def _parse_line(self, line: str, line_num: int, analysis: FileAnalysis, full_content: str):
        """Parse a single line for symbols."""
        # Skip comments
        code = line.split('--')[0]
        if not code.strip():
            return
        
        # Track all dot/colon accessed members to exclude from undefined refs
        member_accesses = set()  # All X.Y or X:Y member names
        
        # Local variable assignments: local x = ... or local x, y = ...
        for match in self.LOCAL_ASSIGN_PATTERN.finditer(code):
            var_name = match.group(1)
            if var_name not in self.lua_keywords:
                analysis.locals_defined[var_name] = SymbolInfo(
                    name=var_name,
                    file=analysis.path,
                    line=line_num,
                    kind='local_var',
                    is_set=True
                )
        
        # Local function definitions: local function foo()
        for match in self.LOCAL_FUNC_PATTERN.finditer(code):
            func_name = match.group(1)
            analysis.funcs_defined[func_name] = SymbolInfo(
                name=func_name,
                file=analysis.path,
                line=line_num,
                kind='local_func',
                is_set=True
            )
        
        # Global function definitions: function Foo() at start of line
        for match in self.GLOBAL_FUNC_PATTERN.finditer(code):
            func_name = match.group(1)
            analysis.funcs_defined[func_name] = SymbolInfo(
                name=func_name,
                file=analysis.path,
                line=line_num,
                kind='global_func',
                is_set=True
            )
        
        # Method definitions: function Object:method() - track as function definition
        for match in self.METHOD_DEF_PATTERN.finditer(code):
            obj_name = match.group(1)
            method_name = match.group(2)
            full_name = f"{obj_name}:{method_name}"
            if obj_name in ['self', 'EditBox', 'YapperTable'] or obj_name[0].isupper():
                analysis.funcs_defined[full_name] = SymbolInfo(
                    name=full_name,
                    file=analysis.path,
                    line=line_num,
                    kind='method_def',
                    is_set=True
                )
        
        # Dot access: C_Timer.After, YapperTable.Utils, self.ChatType, etc.
        # Process this FIRST to avoid false positives on member names
        for match in self.DOT_ACCESS_PATTERN.finditer(code):
            namespace = match.group(1)
            member = match.group(2)
            if namespace not in self.lua_keywords:
                # Add the namespace (e.g., C_Timer) as a global reference
                analysis.globals_used.add(namespace)
                # Track member name so we don't flag it as undefined later
                member_accesses.add(member)
                # Also track the full expression
                referenced_vars.add(f"{namespace}.{member}")
        
        # Colon calls: self:method() or frame:Show()
        for match in self.COLON_CALL_PATTERN.finditer(code):
            obj_name = match.group(1)
            method_name = match.group(2)
            full_name = f"{obj_name}:{method_name}"
            
            # If it's self:method(), mark the method as used
            if obj_name == 'self':
                analysis.funcs_called.add(method_name)
            else:
                # Mark the object as used
                analysis.globals_used.add(obj_name)
            # Track method name so we don't flag it as undefined later
            member_accesses.add(method_name)
        
        # Function calls: foo() or self:foo()
        for match in self.FUNC_CALL_PATTERN.finditer(code):
            func_name = match.group(1)
            if func_name not in self.lua_keywords:
                analysis.funcs_called.add(func_name)
        
        # SetScript handlers: :SetScript("OnEvent", Handler)
        for match in self.SETSCRIPT_PATTERN.finditer(code):
            handler_name = match.group(2)
            analysis.funcs_called.add(handler_name)  # Mark as used
        
        # hooksecurefunc callbacks
        for match in self.HOOKSECUREFUNC_PATTERN.finditer(code):
            callback = match.group(1)
            analysis.funcs_called.add(callback)  # Mark as used
        
        # Check for local variable usage (not assignment)
        for match in self.IDENTIFIER_PATTERN.finditer(code):
            ident = match.group(1)
            if ident not in self.lua_keywords and len(ident) > 1:
                # Skip if this is a member that was accessed via dot/colon
                if ident in member_accesses:
                    continue
                
                # Check if this is a local variable being used
                if ident in analysis.locals_defined:
                    analysis.locals_used.add(ident)
                    continue
                
                # Skip if already tracked in dot expressions
                if ident in referenced_vars:
                    continue
                
                # Skip if it's a known WoW API
                if ident in self.wow_api_whitelist:
                    continue
                
                # Skip common patterns
                if ident.startswith('_') or ident.isupper():
                    continue
                
                # Skip if it's defined as a function
                if ident in analysis.funcs_defined:
                    continue
                
                # Otherwise it's a potential global reference
                analysis.globals_used.add(ident)
        
        # Track table assignments: YapperTable.EditBox = {}
        for match in self.TABLE_ASSIGN_PATTERN.finditer(code):
            table_expr = match.group(1)
            parts = table_expr.split('.')
            if len(parts) >= 2:
                # Track as potential table creation
                analysis.table_assignments[parts[-1]] = table_expr
        
        # Track table references: local EditBox = YapperTable.EditBox
        for match in self.TABLE_REF_PATTERN.finditer(code):
            left_side = match.group(1).split('.')[0]
            right_side = match.group(2)
            # If right side looks like a table reference, track it
            if '.' in right_side:
                base = right_side.split('.')[0]
                member = right_side.split('.')[-1]
                analysis.table_references.append((base, member, line_num))


class WoWAPIExtractor:
    """Extract WoW API functions from wow-ui-source or use built-in fallback."""
    
    BUILTIN_WHITELIST = {
        # Common WoW API globals
        'print', 'error', 'tostring', 'tonumber', 'type', 'pairs', 'ipairs',
        'next', 'select', 'unpack', 'pcall', 'xpcall', 'assert', 'loadstring',
        'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal',
        'hooksecurefunc', 'CreateFrame', 'UIParent', 'GameTooltip',
        'ChatFrame1', 'ChatFrame1EditBox', 'DEFAULT_CHAT_FRAME',
        'NUM_CHAT_WINDOWS', 'LE_PARTY_CATEGORY_HOME', 'LE_PARTY_CATEGORY_INSTANCE',
        'IsInGroup', 'IsInRaid', 'IsInGuild', 'InCombatLockdown', 'UnitName',
        'GetRealmName', 'GetUnitName', 'UnitFullName', 'UnitClass',
        'SendChatMessage', 'BNSendWhisper', 'ChatEdit_SendText', 'ChatEdit_GetActiveWindow',
        'ChatFrame_OpenChat', 'ChatFrameUtil', 'ChatFrameUtil_OpenChat',
        'FCF_Tab_OnClick', 'FCF_GetChatFrameByID', 'SetCVar', 'GetCVar',
        'GetChannelName', 'GetChannelList', 'EnumerateServerChannels',
        'C_Timer', 'C_Club', 'C_HouseEditor', 'C_TradeSkillUI',
        '_G', 'string', 'table', 'math', 'bit', 'coroutine',
        'SlashCmdList', 'ChatTypeInfo', 'CHAT_FOCUS_OVERRIDE',
        'ChatEdit_InsertLink', 'ChatEdit_GetLastTellTarget', 'ChatEdit_GetLastToldTarget',
        'CombatLogGetCurrentEventInfo', 'GetTime', 'GetServerTime',
        'UnitGUID', 'UnitExists', 'UnitIsPlayer', 'UnitIsFriend',
        'IsAltKeyDown', 'IsControlKeyDown', 'IsShiftKeyDown', 'IsModifierKeyDown',
        'PlaySound', 'PlaySoundFile', 'GetCursorPosition', 'GetMouseFocus',
        'GetScreenWidth', 'GetScreenHeight', 'GetBuildInfo', 'GetAddOnMetadata',
    }
    
    def __init__(self, wow_ui_source_path: Optional[Path] = None):
        self.wow_ui_source = wow_ui_source_path
        self.cache_file = Path('.wow_api_cache.json')
        self.extracted_apis: Set[str] = set()
    
    def extract(self) -> Set[str]:
        """Extract WoW API whitelist, using cache if available."""
        # Try cache first
        if self.cache_file.exists():
            try:
                with open(self.cache_file, 'r') as f:
                    cached = json.load(f)
                    # Handle both old array format and new object format
                    if isinstance(cached, dict) and 'apis' in cached:
                        apis = cached['apis']
                    elif isinstance(cached, list):
                        apis = [x for x in cached if not x.startswith('_')]
                    else:
                        apis = []
                    print(f"[INFO] Loaded {len(apis)} APIs from cache")
                    return set(apis)
            except Exception as e:
                print(f"[WARN] Failed to load cache: {e}")
        
        # If wow-ui-source available, extract from there
        if self.wow_ui_source and self.wow_ui_source.exists():
            self.extracted_apis = self._extract_from_source()
            self._save_cache(self.extracted_apis)
            return self.extracted_apis
        
        # Fallback to built-in whitelist
        print("[INFO] wow-ui-source not found, using built-in whitelist (~200 APIs)")
        return self.BUILTIN_WHITELIST.copy()
    
    def _extract_from_source(self) -> Set[str]:
        """Extract API definitions from wow-ui-source."""
        apis = set(self.BUILTIN_WHITELIST)  # Start with builtins
        addons_path = self.wow_ui_source / 'Interface' / 'AddOns'
        
        if not addons_path.exists():
            print(f"[WARN] AddOns path not found: {addons_path}")
            return apis
        
        lua_files = list(addons_path.rglob('*.lua'))
        print(f"[INFO] Scanning {len(lua_files)} Lua files from wow-ui-source...")
        
        # Patterns to extract WoW API
        global_func_pattern = re.compile(r'^\s*function\s+([A-Z][A-Za-z0-9_]*)\s*\(', re.MULTILINE)
        c_namespace_pattern = re.compile(r'\b(C_[A-Z][A-Za-z0-9_]*)\.([A-Z][a-zA-Z0-9_]*)')
        widget_method_pattern = re.compile(r':(Set[A-Z][a-zA-Z]*|Get[A-Z][a-zA-Z]*|Show|Hide|Enable|Disable|RegisterEvent|UnregisterEvent|SetScript|HookScript)')
        
        for lua_file in lua_files:
            try:
                with open(lua_file, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                # Global functions (capitalized)
                for match in global_func_pattern.finditer(content):
                    apis.add(match.group(1))
                
                # C_* namespaces
                for match in c_namespace_pattern.finditer(content):
                    namespace = match.group(1)
                    method = match.group(2)
                    apis.add(namespace)
                    apis.add(f"{namespace}.{method}")
                
                # Common widget methods
                for match in widget_method_pattern.finditer(content):
                    apis.add(match.group(1))
                    
            except Exception as e:
                continue
        
        print(f"[INFO] Extracted {len(apis)} total APIs from wow-ui-source")
        return apis
    
    def _save_cache(self, apis: Set[str]):
        """Save extracted APIs to cache file with comment."""
        try:
            cache_data = {
                "_comment": "WoW API Cache - Auto-generated by tools/dead_code_scanner.py. Contains ~15,000 WoW API function names extracted from wow-ui-source. Delete this file to force re-extraction.",
                "apis": sorted(apis)
            }
            with open(self.cache_file, 'w') as f:
                json.dump(cache_data, f, indent=2)
            print(f"[INFO] Saved API cache to {self.cache_file}")
        except Exception as e:
            print(f"[WARN] Failed to save cache: {e}")


class TOCResolver:
    """Parse TOC files to determine Lua file load order."""
    
    def __init__(self, base_path: Path):
        self.base_path = base_path
    
    def get_load_order(self, toc_file: Path) -> List[str]:
        """Get ordered list of Lua files from a TOC."""
        lua_files = []
        
        try:
            with open(toc_file, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    # Skip comments and empty lines
                    if not line or line.startswith('#'):
                        continue
                    # Only include Lua files
                    if line.endswith('.lua'):
                        lua_files.append(line)
        except Exception as e:
            print(f"[ERROR] Failed to read TOC {toc_file}: {e}")
        
        return lua_files


class DeadCodeAnalyzer:
    """Analyze parsed files to find dead code with cross-file tracking."""
    
    def __init__(self, wow_api_whitelist: Set[str]):
        self.wow_api_whitelist = wow_api_whitelist
        self.parser = LuaParser(wow_api_whitelist)
        self.file_analyses: Dict[str, FileAnalysis] = {}
        self.all_globals_defined: Set[str] = set()
        # Cross-file symbol tracking
        self.global_symbol_map: Dict[str, str] = {}  # symbol_name -> defining_file
        self.table_members: Dict[str, Set[str]] = defaultdict(set)  # table_name -> {methods}
        self.file_load_order: List[str] = []
    
    def analyze_files(self, lua_files: List[Path], toc_order: Optional[List[str]] = None):
        """Analyze all Lua files with TOC-aware ordering."""
        print(f"[INFO] Analyzing {len(lua_files)} Lua files...")
        
        # Sort files by TOC order if available
        if toc_order:
            lua_files = self._sort_by_toc_order(lua_files, toc_order)
        
        # First pass: parse all files
        for lua_file in lua_files:
            try:
                with open(lua_file, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                analysis = self.parser.parse_file(str(lua_file), content)
                self.file_analyses[str(lua_file)] = analysis
                self.file_load_order.append(str(lua_file))
                
                # Collect globally defined functions
                for func_name, info in analysis.funcs_defined.items():
                    if info.kind == 'global_func':
                        self.all_globals_defined.add(func_name)
                        self.global_symbol_map[func_name] = str(lua_file)
                    elif info.kind == 'method_def' and ':' in func_name:
                        # Track table:method as member of table
                        table_name = func_name.split(':')[0]
                        method_name = func_name.split(':')[1]
                        self.table_members[table_name].add(method_name)
                        
            except Exception as e:
                print(f"[ERROR] Failed to analyze {lua_file}: {e}")
        
        # Second pass: resolve cross-file references
        self._resolve_cross_file_refs()
        
        print(f"[INFO] Analysis complete - tracked {len(self.global_symbol_map)} global symbols")
        print(f"[INFO] Tracked {len(self.table_members)} tables with members")
    
    def _sort_by_toc_order(self, lua_files: List[Path], toc_order: List[str]) -> List[Path]:
        """Sort Lua files according to TOC load order."""
        file_map = {f.name: f for f in lua_files}
        sorted_files = []
        
        for toc_entry in toc_order:
            filename = Path(toc_entry).name
            if filename in file_map:
                sorted_files.append(file_map[filename])
        
        # Add any remaining files not in TOC
        for f in lua_files:
            if f not in sorted_files:
                sorted_files.append(f)
        
        return sorted_files
    
    def _resolve_cross_file_refs(self):
        """Resolve cross-file table references."""
        # Build a map of table aliases: local EditBox = YapperTable.EditBox
        table_aliases: Dict[str, str] = {}  # alias -> actual_table
        
        for filepath, analysis in self.file_analyses.items():
            for base, member, line in analysis.table_references:
                full_name = f"{base}.{member}"
                # Check if this references a known table
                for table_name in self.table_members.keys():
                    if member == table_name or base == table_name:
                        table_aliases[table_name] = full_name
        
        # Update function call tracking using aliases
        for filepath, analysis in self.file_analyses.items():
            for called_func in list(analysis.funcs_called):
                # Check if this is a method call on an aliased table
                for alias, actual in table_aliases.items():
                    if called_func.startswith(f"{alias}:"):
                        method = called_func.split(':')[1]
                        # Mark as called on the actual table too
                        if alias in self.table_members:
                            if method in self.table_members[alias]:
                                # It's a valid call
                                pass
    
    def find_unused_locals(self) -> List[Tuple[str, str, int]]:
        """Find local variables that are assigned but never used."""
        unused = []
        
        for filepath, analysis in self.file_analyses.items():
            # Debug: print what we found
            if os.environ.get('DEBUG') and analysis.locals_defined:
                print(f"[DEBUG] {filepath}: defined={list(analysis.locals_defined.keys())}, used={analysis.locals_used}")
            
            for var_name, info in analysis.locals_defined.items():
                # Skip underscore (Lua idiom for "don't care")
                if var_name == '_':
                    continue
                # Check if variable is used anywhere
                if var_name not in analysis.locals_used:
                    unused.append((filepath, var_name, info.line))
        
        return unused
    
    def find_uncalled_functions(self) -> List[Tuple[str, str, int, str]]:
        """Find functions defined but never called."""
        uncalled = []
        
        for filepath, analysis in self.file_analyses.items():
            for func_name, info in analysis.funcs_defined.items():
                # Skip if it's called
                if func_name in analysis.funcs_called:
                    continue
                
                # Check if it's a method definition (contains :)
                if ':' in func_name:
                    # Extract just the method name
                    method_name = func_name.split(':')[1]
                    if method_name in analysis.funcs_called:
                        continue
                
                uncalled.append((filepath, func_name, info.line, info.kind))
        
        return uncalled
    
    def find_undefined_references(self) -> List[Tuple[str, str, int]]:
        """Find references to potentially undefined globals."""
        undefined = []
        
        for filepath, analysis in self.file_analyses.items():
            for global_name in analysis.globals_used:
                # Skip known WoW APIs
                if global_name in self.wow_api_whitelist:
                    continue
                # Skip if defined as global function somewhere
                if global_name in self.all_globals_defined:
                    continue
                # Skip common patterns
                if global_name.startswith('_') or global_name.isupper():
                    continue
                
                # Find line number (first occurrence)
                try:
                    with open(filepath, 'r') as f:
                        for line_num, line in enumerate(f, 1):
                            if global_name in line:
                                undefined.append((filepath, global_name, line_num))
                                break
                except:
                    undefined.append((filepath, global_name, 0))
        
        return undefined


class ReportGenerator:
    """Generate console and markdown reports."""
    
    def __init__(self, output_file: str = 'dead_code_report.md'):
        self.output_file = output_file
    
    def generate(self, analyzer: DeadCodeAnalyzer):
        """Generate both console and markdown reports."""
        # Collect findings
        unused_locals = analyzer.find_unused_locals()
        uncalled_funcs = analyzer.find_uncalled_functions()
        undefined_refs = analyzer.find_undefined_references()
        
        # Console output with colors
        self._console_report(unused_locals, uncalled_funcs, undefined_refs)
        
        # Markdown output
        self._markdown_report(unused_locals, uncalled_funcs, undefined_refs)
    
    def _console_report(self, unused_locals, uncalled_funcs, undefined_refs):
        """Print colored report to console."""
        print()
        print("=" * 70)
        print("DEAD CODE SCANNER RESULTS")
        print("=" * 70)
        
        # Unused locals
        print()
        print(f"\033[33m=== Unused Local Variables ({len(unused_locals)}) ===\033[0m")
        for filepath, var_name, line in sorted(unused_locals):
            rel_path = os.path.relpath(filepath)
            print(f"  \033[36m{rel_path}:{line}\033[0m    local \033[31m{var_name}\033[0m (assigned but never used)")
        
        # Uncalled functions
        print()
        print(f"\033[33m=== Uncalled Functions ({len(uncalled_funcs)}) ===\033[0m")
        for filepath, func_name, line, kind in sorted(uncalled_funcs):
            rel_path = os.path.relpath(filepath)
            kind_str = f"[{kind}]" if kind != 'local_func' else ""
            print(f"  \033[36m{rel_path}:{line}\033[0m    function \033[31m{func_name}\033[0m {kind_str}")
        
        # Undefined references
        print()
        print(f"\033[33m=== Potentially Undefined References ({len(undefined_refs)}) ===\033[0m")
        for filepath, ref_name, line in sorted(undefined_refs)[:50]:  # Limit to 50
            rel_path = os.path.relpath(filepath)
            print(f"  \033[36m{rel_path}:{line}\033[0m    \033[35m{ref_name}\033[0m")
        if len(undefined_refs) > 50:
            print(f"  ... and {len(undefined_refs) - 50} more")
        
        print()
        print("=" * 70)
        print(f"Total: {len(unused_locals)} unused locals, {len(uncalled_funcs)} uncalled functions, {len(undefined_refs)} undefined refs")
        print("=" * 70)
    
    def _markdown_report(self, unused_locals, uncalled_funcs, undefined_refs):
        """Generate markdown report file."""
        with open(self.output_file, 'w') as f:
            f.write("# Dead Code Scanner Report\n\n")
            f.write(f"Generated: {__import__('datetime').datetime.now().isoformat()}\n\n")
            
            # Summary
            f.write("## Summary\n\n")
            f.write(f"- **Unused Local Variables**: {len(unused_locals)}\n")
            f.write(f"- **Uncalled Functions**: {len(uncalled_funcs)}\n")
            f.write(f"- **Potentially Undefined References**: {len(undefined_refs)}\n\n")
            
            # Unused locals
            f.write("## Unused Local Variables\n\n")
            f.write("| File | Line | Variable |\n")
            f.write("|------|------|----------|\n")
            for filepath, var_name, line in sorted(unused_locals):
                rel_path = os.path.relpath(filepath)
                f.write(f"| {rel_path} | {line} | `{var_name}` |\n")
            if not unused_locals:
                f.write("| - | - | *None found* |\n")
            f.write("\n")
            
            # Uncalled functions
            f.write("## Uncalled Functions\n\n")
            f.write("| File | Line | Function | Type |\n")
            f.write("|------|------|----------|------|\n")
            for filepath, func_name, line, kind in sorted(uncalled_funcs):
                rel_path = os.path.relpath(filepath)
                f.write(f"| {rel_path} | {line} | `{func_name}` | {kind} |\n")
            if not uncalled_funcs:
                f.write("| - | - | *None found* | - |\n")
            f.write("\n")
            
            # Undefined references
            f.write("## Potentially Undefined References\n\n")
            f.write("| File | Line | Reference |\n")
            f.write("|------|------|-----------|\n")
            for filepath, ref_name, line in sorted(undefined_refs):
                rel_path = os.path.relpath(filepath)
                f.write(f"| {rel_path} | {line} | `{ref_name}` |\n")
            if not undefined_refs:
                f.write("| - | - | *None found* |\n")
            f.write("\n")
            
            f.write("---\n\n")
            f.write("*Note: This is a heuristic analysis. Some findings may be false positives due to:*\n")
            f.write("- Dynamic access patterns (`self[methodName]()`)\n")
            f.write("- String-based callbacks\n")
            f.write("- Metatable-based access\n")
            f.write("- WoW API globals not in whitelist\n")
        
        print(f"\n[INFO] Report saved to: {self.output_file}")


def main():
    parser = argparse.ArgumentParser(description='Dead Code Scanner for WoW-Yapper')
    parser.add_argument('--path', '-p', default='Src', help='Directory to scan (default: Src)')
    parser.add_argument('--toc', '-t', default='Yapper.toc', help='TOC file for load order (default: Yapper.toc)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Include low-confidence findings')
    parser.add_argument('--output', '-o', default='dead_code_report.md', help='Output markdown file')
    parser.add_argument('--no-cache', action='store_true', help='Ignore API cache and re-extract')
    args = parser.parse_args()
    
    # Determine project root (where the script is located, go up one level from tools/)
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    
    # Find wow-ui-source (sibling to project root)
    wow_ui_path = None
    potential_paths = [
        project_root.parent / 'wow-ui-source',
        Path('../wow-ui-source'),
        Path('../../wow-ui-source'),
        Path('wow-ui-source'),
    ]
    
    # Debug: show paths being checked
    if os.environ.get('DEBUG'):
        print(f"[DEBUG] Project root: {project_root}")
        print(f"[DEBUG] Checking paths for wow-ui-source...")
    
    for path in potential_paths:
        if os.environ.get('DEBUG'):
            print(f"[DEBUG] Checking: {path} (absolute: {path.resolve()})")
        addons_path = path / 'Interface' / 'AddOns'
        if path.exists() and addons_path.exists():
            wow_ui_path = path
            break
    
    if wow_ui_path:
        print(f"[INFO] Found wow-ui-source at: {wow_ui_path}")
    else:
        print("[INFO] wow-ui-source not found, using built-in whitelist")
    
    # Cache file in project root
    cache_file = project_root / '.wow_api_cache.json'
    
    # Clear cache if requested
    if args.no_cache and cache_file.exists():
        cache_file.unlink()
        print("[INFO] API cache cleared")
    
    # Extract WoW API whitelist
    extractor = WoWAPIExtractor(wow_ui_path)
    extractor.cache_file = cache_file
    wow_api_whitelist = extractor.extract()
    print(f"[INFO] Using {len(wow_api_whitelist)} known WoW API functions\n")
    
    # Find Lua files to analyze
    base_path = project_root / args.path if not Path(args.path).is_absolute() else Path(args.path)
    if not base_path.exists():
        print(f"[ERROR] Path not found: {base_path}")
        sys.exit(1)
    
    lua_files = list(base_path.rglob('*.lua'))
    if not lua_files:
        print(f"[ERROR] No Lua files found in {base_path}")
        sys.exit(1)
    
    # Read TOC for load order
    toc_file = project_root / args.toc
    toc_order = None
    if toc_file.exists():
        toc_resolver = TOCResolver(project_root)
        toc_order = toc_resolver.get_load_order(toc_file)
        print(f"[INFO] Loaded TOC with {len(toc_order)} Lua files in load order\n")
    
    # Analyze files with TOC-aware ordering
    analyzer = DeadCodeAnalyzer(wow_api_whitelist)
    analyzer.analyze_files(lua_files, toc_order)
    
    # Generate report (output to project root)
    output_path = project_root / args.output
    reporter = ReportGenerator(str(output_path))
    reporter.generate(analyzer)
    
    print(f"\n[INFO] Full report: {output_path}")


if __name__ == '__main__':
    main()
