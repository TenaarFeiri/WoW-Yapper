#!/usr/bin/env python3
"""Bulk convert Hunspell dictionaries to Lua word lists for WoW locales."""

from __future__ import annotations

import argparse
from pathlib import Path

from convert_hunspell_to_lua import parse_aff, read_words, write_lua


WOW_LOCALE_MAP = {
    "enUS": "en",
    "enGB": "en-GB",
    "frFR": "fr",
    "deDE": "de",
    "esES": "es",
    "esMX": "es-MX",
    "itIT": "it",
    "ptBR": "pt",
    "ruRU": "ru",
    "koKR": "ko",
    "zhCN": None,
    "zhTW": None,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bulk convert Hunspell dictionaries.")
    parser.add_argument("--dict-root", required=True, help="Root folder of dictionaries")
    parser.add_argument("--out-dir", required=True, help="Output directory for Lua dictionaries")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    dict_root = Path(args.dict_root)
    out_dir = Path(args.out_dir)

    missing = []
    for wow_locale, dict_dir in WOW_LOCALE_MAP.items():
        if not dict_dir:
            missing.append((wow_locale, "no dictionary mapping"))
            continue

        src_dir = dict_root / dict_dir
        dic_path = src_dir / "index.dic"
        aff_path = src_dir / "index.aff"
        if not dic_path.exists():
            missing.append((wow_locale, f"missing {dic_path}"))
            continue

        flag_type, flag_aliases, prefixes, suffixes = parse_aff(aff_path) if aff_path.exists() else ("short", None, {}, {})
        words = read_words(dic_path, flag_type, flag_aliases, prefixes, suffixes)
        out_path = out_dir / f"{wow_locale}.lua"
        write_lua(out_path, wow_locale, words)
        print(f"Converted {wow_locale} <- {dict_dir} ({len(words)} forms)")

    if missing:
        print("\nMissing locales:")
        for locale, reason in missing:
            print(f"- {locale}: {reason}")


if __name__ == "__main__":
    main()
