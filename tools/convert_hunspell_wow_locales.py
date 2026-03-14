#!/usr/bin/env python3
"""Convert Hunspell dictionaries for WoW locales into Lua word lists.

Usage:
  python3 convert_hunspell_wow_locales.py \
    --src /path/to/dictionaries/dictionaries \
    --out /path/to/WoW-Yapper/Src/Spellcheck/Dicts
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert Hunspell dictionaries for WoW locales.")
    parser.add_argument("--src", required=True, help="Root dictionaries folder")
    parser.add_argument("--out", required=True, help="Output Dicts folder")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    src_root = Path(args.src)
    out_root = Path(args.out)

    mapping = {
        "enUS": "en",
        "enGB": "en-GB",
        "frFR": "fr",
        "deDE": "de",
        "esES": "es",
        "esMX": "es-MX",
        "itIT": "it",
        "ptBR": "pt",
        "ruRU": "ru",
    }

    converter = Path(__file__).resolve().parent / "convert_hunspell_to_lua.py"

    for locale, folder in mapping.items():
        src_dir = src_root / folder
        dic_path = src_dir / "index.dic"
        aff_path = src_dir / "index.aff"
        if not dic_path.exists():
            print(f"Skip {locale}: missing {dic_path}")
            continue
        out_path = out_root / f"{locale}.lua"
        cmd = [
            "python3",
            str(converter),
            "--dic",
            str(dic_path),
            "--aff",
            str(aff_path) if aff_path.exists() else "",
            "--locale",
            locale,
            "--out",
            str(out_path),
        ]
        cmd = [c for c in cmd if c]
        subprocess.check_call(cmd)
        print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
