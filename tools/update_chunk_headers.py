#!/usr/bin/env python3
import os
import fnmatch

root = os.path.dirname(os.path.dirname(__file__))  # WoW-Yapper
count = 0
old = 'local _, YapperTable = ...\nif not YapperTable or not YapperTable.Spellcheck then return end\n'
new = ("local _, YapperTable = ...\n"
       "local mainY = _G.Yapper or Yapper\n"
       "if (not YapperTable or not YapperTable.Spellcheck) and mainY and mainY.Spellcheck then\n"
       "    YapperTable = YapperTable or {}\n"
       "    YapperTable.Spellcheck = mainY.Spellcheck\n"
       "end\n"
       "if not YapperTable or not YapperTable.Spellcheck then return end\n")

for dirpath, dirnames, filenames in os.walk(root):
    if fnmatch.fnmatch(dirpath, os.path.join(root, 'Yapper_Dict_*', 'Dicts')):
        for fname in filenames:
            if fname.endswith('.lua'):
                path = os.path.join(dirpath, fname)
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        text = f.read()
                    if old in text:
                        text2 = text.replace(old, new, 1)
                        with open(path, 'w', encoding='utf-8') as f:
                            f.write(text2)
                        count += 1
                except Exception as e:
                    print('ERROR', path, e)

print('Updated', count, 'files')
