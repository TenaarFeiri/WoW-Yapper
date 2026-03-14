#!/usr/bin/env python3
"""Convert a Hunspell .dic/.aff file into a Lua word list.

Usage:
    python3 convert_hunspell_to_lua.py \
        --dic /path/to/index.dic \
        --aff /path/to/index.aff \
        --locale enGB \
        --out /path/to/WoW-Yapper/Src/Spellcheck/Dicts/enGB.lua
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert Hunspell .dic to Lua word list.")
    parser.add_argument("--dic", required=True, help="Path to Hunspell .dic file")
    parser.add_argument("--aff", help="Path to Hunspell .aff file (optional)")
    parser.add_argument("--locale", required=True, help="Locale key (e.g., enGB)")
    parser.add_argument("--out", required=True, help="Output Lua file path")
    parser.add_argument("--source", default="", help="Source URL for the dictionary repo")
    parser.add_argument("--package", default="", help="Dictionary package name")
    parser.add_argument("--license", default="", help="License identifier")
    return parser.parse_args()


def split_word_and_flags(line: str) -> tuple[str, str | None]:
    # Hunspell uses unescaped '/' to separate flags. '\/' is a literal slash.
    parts = re.split(r"(?<!\\)/", line, maxsplit=1)
    word = parts[0]
    word = word.replace("\\/", "/")
    flags = parts[1] if len(parts) > 1 else None
    return word, flags


def parse_flags(flags: str | None, flag_type: str, flag_aliases: list[str] | None) -> list[str]:
    if not flags:
        return []

    flags = flags.strip()
    if not flags:
        return []

    if flag_aliases and flags.isdigit():
        idx = int(flags)
        if 1 <= idx <= len(flag_aliases):
            flags = flag_aliases[idx - 1]

    if flag_type == "long":
        return [flags[i : i + 2] for i in range(0, len(flags), 2)]
    if flag_type == "num":
        return [f.strip() for f in flags.split(",") if f.strip()]
    return list(flags)


def parse_aff(aff_path: Path) -> tuple[str, list[str] | None, dict[str, dict], dict[str, dict]]:
    flag_type = "short"
    flag_aliases: list[str] | None = None
    prefixes: dict[str, dict] = {}
    suffixes: dict[str, dict] = {}

    if not aff_path or not aff_path.exists():
        return flag_type, flag_aliases, prefixes, suffixes

    with aff_path.open("r", encoding="utf-8", errors="replace") as handle:
        lines = [ln.strip() for ln in handle]

    idx = 0
    while idx < len(lines):
        line = lines[idx]
        idx += 1
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        if not parts:
            continue

        if parts[0] == "FLAG" and len(parts) > 1:
            flag_type = parts[1].lower()
            continue

        if parts[0] == "AF" and len(parts) == 2 and parts[1].isdigit():
            count = int(parts[1])
            flag_aliases = []
            for _ in range(count):
                if idx >= len(lines):
                    break
                alias_line = lines[idx].strip()
                idx += 1
                flag_aliases.append(alias_line)
            continue

        if parts[0] in {"PFX", "SFX"} and len(parts) >= 4:
            kind = parts[0]
            flag = parts[1]
            cross = parts[2].upper() == "Y"
            count = int(parts[3])
            rules = []
            for _ in range(count):
                if idx >= len(lines):
                    break
                rule_line = lines[idx].strip()
                idx += 1
                rule_parts = rule_line.split()
                if len(rule_parts) < 5:
                    continue
                strip = "" if rule_parts[2] == "0" else rule_parts[2]
                add = "" if rule_parts[3] == "0" else rule_parts[3]
                cond = rule_parts[4]
                if cond == ".":
                    cond_re = None
                elif kind == "PFX":
                    cond_re = re.compile(r"^" + cond)
                else:
                    cond_re = re.compile(cond + r"$")
                rules.append({
                    "strip": strip,
                    "add": add,
                    "cond": cond_re,
                })

            target = prefixes if kind == "PFX" else suffixes
            target[flag] = {"cross": cross, "rules": rules}
            continue

    return flag_type, flag_aliases, prefixes, suffixes


def apply_prefix(word: str, rule: dict) -> str | None:
    strip = rule["strip"]
    if strip and not word.startswith(strip):
        return None
    base = word[len(strip) :] if strip else word
    cond = rule["cond"]
    if cond and not cond.search(base):
        return None
    return rule["add"] + base


def apply_suffix(word: str, rule: dict) -> str | None:
    strip = rule["strip"]
    if strip and not word.endswith(strip):
        return None
    base = word[: -len(strip)] if strip else word
    cond = rule["cond"]
    if cond and not cond.search(base):
        return None
    return base + rule["add"]


def is_wordish(token: str) -> bool:
    if token.isdigit():
        return False
    for ch in token:
        if ch.isalpha():
            return True
    return False


def read_words(dic_path: Path,
               flag_type: str,
               flag_aliases: list[str] | None,
               prefixes: dict[str, dict],
               suffixes: dict[str, dict]) -> list[str]:
    words: list[str] = []
    with dic_path.open("r", encoding="utf-8", errors="replace") as handle:
        first = True
        for raw in handle:
            line = raw.strip()
            if first:
                # first line is entry count
                first = False
                if line.isdigit():
                    continue
            if not line or line.startswith("#"):
                continue
            # Words are the first token; trailing data can include flags or tags.
            token = line.split()[0]
            word, flags_raw = split_word_and_flags(token)
            if not word or not is_wordish(word):
                continue

            flags = parse_flags(flags_raw, flag_type, flag_aliases)
            base_words = [word]
            lower = word.lower()
            if lower != word:
                base_words.append(lower)

            for base in base_words:
                expanded = expand_word(base, flags, prefixes, suffixes)
                words.extend(expanded)
    return words


def expand_word(word: str,
                flags: list[str],
                prefixes: dict[str, dict],
                suffixes: dict[str, dict]) -> list[str]:
    out = {word}

    prefix_forms: list[tuple[str, bool]] = []
    for flag in flags:
        if flag not in prefixes:
            continue
        entry = prefixes[flag]
        for rule in entry["rules"]:
            result = apply_prefix(word, rule)
            if result:
                if is_wordish(result):
                    out.add(result)
                prefix_forms.append((result, entry["cross"]))

    suffix_forms: list[tuple[str, bool]] = []
    for flag in flags:
        if flag not in suffixes:
            continue
        entry = suffixes[flag]
        for rule in entry["rules"]:
            result = apply_suffix(word, rule)
            if result:
                if is_wordish(result):
                    out.add(result)
                suffix_forms.append((result, entry["cross"]))

    # Cross-product of prefixes and suffixes where both allow it.
    if prefix_forms and suffix_forms:
        for flag_p in flags:
            if flag_p not in prefixes:
                continue
            if not prefixes[flag_p]["cross"]:
                continue
            for flag_s in flags:
                if flag_s not in suffixes:
                    continue
                if not suffixes[flag_s]["cross"]:
                    continue
                for rule_p in prefixes[flag_p]["rules"]:
                    pref_word = apply_prefix(word, rule_p)
                    if not pref_word:
                        continue
                    for rule_s in suffixes[flag_s]["rules"]:
                        combined = apply_suffix(pref_word, rule_s)
                        if combined:
                            if is_wordish(combined):
                                out.add(combined)

    return list(out)


def write_lua(out_path: Path,
              locale: str,
              words: list[str],
              source: str = "",
              package: str = "",
              license_name: str = "") -> None:
    unique = sorted(set(words))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as handle:
        handle.write("-- Generated from Hunspell .dic\n")
        if source:
            handle.write("-- Source: %s\n" % source)
        if package:
            handle.write("-- Package: %s\n" % package)
        if license_name:
            handle.write("-- License: %s\n" % license_name)
        handle.write("-- Locale: %s\n\n" % locale)
        handle.write("local _, YapperTable = ...\n")
        handle.write("if not YapperTable or not YapperTable.Spellcheck then return end\n\n")
        handle.write("YapperTable.Spellcheck:RegisterDictionary(\"%s\", {\n" % locale)
        handle.write("    words = {\n")

        per_line = 6
        for i, word in enumerate(unique):
            sep = "" if i % per_line == 0 else " "
            if i % per_line == 0:
                handle.write("        ")
            handle.write("%s\"%s\"," % (sep, word))
            if (i + 1) % per_line == 0:
                handle.write("\n")
        if unique and len(unique) % per_line != 0:
            handle.write("\n")

        handle.write("    },\n")
        handle.write("})\n")


def main() -> None:
    args = parse_args()
    dic_path = Path(args.dic)
    out_path = Path(args.out)
    aff_path = Path(args.aff) if args.aff else None
    flag_type, flag_aliases, prefixes, suffixes = parse_aff(aff_path) if aff_path else ("short", None, {}, {})
    words = read_words(dic_path, flag_type, flag_aliases, prefixes, suffixes)
    write_lua(
        out_path,
        args.locale,
        words,
        source=args.source,
        package=args.package,
        license_name=args.license,
    )


if __name__ == "__main__":
    main()
