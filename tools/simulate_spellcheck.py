#!/usr/bin/env python3
import re
import os
import sys
from collections import defaultdict, Counter

# Configure paths relative to repo root
ROOT = os.path.dirname(os.path.dirname(__file__))
EN_PATH = os.path.join(ROOT, 'Src', 'Spellcheck', 'Dicts', 'enUS.lua')
DE_DIR = os.path.join(ROOT, 'Yapper_Dict_deDE', 'Dicts')

STRING_RE = re.compile(r'"((?:\\"|[^"])+)"')

def parse_lua_words_from_file(path):
    out = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = f.read()
    except Exception as e:
        print('ERR reading', path, e, file=sys.stderr)
        return out
    # Find the words = { ... } block
    m = re.search(r'words%s*=s*{(.*?)}' , data, re.S)
    if not m:
        # fallback: collect all quoted strings after 'words = {'
        start = data.find('words = {')
        if start >= 0:
            sub = data[start:]
            out = STRING_RE.findall(sub)
        return out
    block = m.group(1)
    out = STRING_RE.findall(block)
    return out

def parse_en_words():
    return parse_lua_words_from_file(EN_PATH)

def parse_de_words():
    words = []
    if not os.path.isdir(DE_DIR):
        print('de dict dir not found:', DE_DIR)
        return words
    for fn in sorted(os.listdir(DE_DIR)):
        if not fn.endswith('.lua'):
            continue
        path = os.path.join(DE_DIR, fn)
        words.extend(parse_lua_words_from_file(path))
    return words

# Normalize similar to Lua NormalizeWord (lowercase unicode)
def normalize(word):
    if not isinstance(word, str):
        return ''
    return word.lower()

# Damerau-Levenshtein with early abandonment like Lua
def edit_distance(a, b, max_dist):
    if a == b:
        return 0
    la = len(a); lb = len(b)
    if abs(la - lb) > max_dist:
        return None
    prevprev = [0] * (lb + 1)
    prev = list(range(lb + 1))
    for i in range(1, la + 1):
        cur = [0] * (lb + 1)
        cur[0] = i
        minrow = cur[0]
        ai = a[i-1]
        for j in range(1, lb + 1):
            bj = b[j-1]
            cost = 0 if ai == bj else 1
            val = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            if i > 1 and j > 1:
                if ai == b[j-2] and a[i-2] == bj:
                    val = min(val, (prevprev[j-2] if j-2>=0 else 0) + 1)
            cur[j] = val
            if val < minrow:
                minrow = val
        if minrow > max_dist:
            return None
        prevprev, prev = prev, cur
    return prev[lb]

# Scoring utilities
SCORE_WEIGHTS = {
    'lenDiff': 0.25,
    'prefix': 0.15,
    'letterBag': 0.08,
    'longerPenalty': 0.12,
}

def common_prefix_len(a,b):
    ln = min(len(a), len(b))
    c = 0
    for i in range(ln):
        if a[i] != b[i]: break
        c += 1
    return c

def letter_bag_score(a,b):
    bag = Counter(a)
    for ch in b:
        if bag.get(ch,0):
            bag[ch] -= 1
        else:
            bag[ch] = bag.get(ch,0) - 1
    score = sum(abs(v) for v in bag.values())
    return score

def simulate(words, query):
    words_norm = [normalize(w) for w in words if isinstance(w,str) and w]
    index = defaultdict(list)
    for w in words_norm:
        key = w[:1]
        index[key].append(w)
    lower = normalize(query)
    if not lower:
        print('empty query')
        return
    first = lower[:1]
    candidates = index.get(first, [])

    print('\nQuery:', query)
    print('Total words in locale:', len(words_norm))
    print('Candidates for first char "{}": {}'.format(first, len(candidates)))

    max_dist = 2 if len(lower) <= 4 else 3
    max_len_diff = max_dist + 1

    after_len = [c for c in candidates if abs(len(c)-len(lower)) <= max_len_diff]
    print('After len-diff filter (<= {}): {}'.format(max_len_diff, len(after_len)))

    # run edit distance and score, measure counts
    matches = []
    checks = 0
    for c in after_len:
        checks += 1
        d = edit_distance(lower, c, max_dist)
        if d is not None:
            # compute score
            candidate_len = len(c)
            len_diff = abs(candidate_len - len(lower))
            prefix = common_prefix_len(lower, c)
            bag = letter_bag_score(lower, c)
            longer_penalty = (candidate_len > len(lower)) and ((candidate_len - len(lower)) * SCORE_WEIGHTS['longerPenalty']) or 0
            score = d + (len_diff * SCORE_WEIGHTS['lenDiff']) + longer_penalty - (prefix * SCORE_WEIGHTS['prefix']) + (bag * SCORE_WEIGHTS['letterBag'])
            matches.append((c, d, score))
    print('EditDistance computations (after len filter):', checks)
    print('Matches with dist <= {}: {}'.format(max_dist, len(matches)))
    matches.sort(key=lambda x: (x[2], x[1], x[0]))
    for i,m in enumerate(matches[:20], start=1):
        print('{:2d}. {:30s} dist={} score={:.3f}'.format(i, m[0], m[1], m[2]))

    return {
        'total_words': len(words_norm),
        'candidates': len(candidates),
        'after_len': len(after_len),
        'matches': len(matches)
    }

if __name__ == '__main__':
    queries = ['deutshc', 'supercallifragilistic']
    en_words = parse_en_words()
    de_words = parse_de_words()
    print('Loaded en words:', len(en_words))
    print('Loaded de chunks words:', len(de_words))

    for q in queries:
        print('\n=== enUS ===')
        simulate(en_words, q)
        print('\n=== deDE ===')
        simulate(de_words, q)
