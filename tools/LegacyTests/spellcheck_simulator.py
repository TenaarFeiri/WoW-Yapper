import re
import math
import os

# --- 1. Definitive Algorithm Parity (The Yapper Simulator) ---

KB_LAYOUT = {
    'q':(0,0),    'w':(1,0),    'e':(2,0),    'r':(3,0),    't':(4,0),
    'y':(5,0),    'u':(6,0),    'i':(7,0),    'o':(8,0),    'p':(9,0),
    'a':(0.25,1), 's':(1.25,1), 'd':(2.25,1), 'f':(3.25,1), 'g':(4.25,1),
    'h':(5.25,1), 'j':(6.25,1), 'k':(7.25,1), 'l':(8.25,1),
    'z':(0.75,2), 'x':(1.75,2), 'c':(2.75,2), 'v':(3.75,2), 'b':(4.75,2),
    'n':(5.75,2), 'm':(6.75,2),
}

def get_phonetic_hash(word):
    if not word: return ""
    h = word.upper()
    h = re.sub(r'(.)\1+', r'\1', h)
    
    # Parity rules for silent/variable phonetics
    h = h.replace("GHT", "T")
    h = h.replace("GH", "F") if h.endswith("GH") else h.replace("GH", "")
    h = h.replace("PH", "F")
    h = h.replace("KN", "N")
    h = h.replace("GN", "N")
    h = h.replace("WR", "R")
    h = h.replace("CH", "K")
    h = h.replace("SH", "X")
    h = h.replace("C", "K")
    h = h.replace("Z", "S")
    
    if not h: return ""
    first, rest = h[0], re.sub(r'[AEIOUY]', '', h[1:])
    return first + rest

def damerau_levenshtein(s1, s2, max_dist=3):
    d = {}
    len1, len2 = len(s1), len(s2)
    if abs(len1 - len2) > max_dist: return None
    for i in range(-1, len1 + 1): d[(i, -1)] = i + 1
    for j in range(-1, len2 + 1): d[(-1, j)] = j + 1
    for i in range(len1):
        for j in range(len2):
            cost = 0 if s1[i] == s2[j] else 1
            res = min(d[(i-1, j)] + 1, d[(i, j-1)] + 1, d[(i-1, j-1)] + cost)
            if i > 0 and j > 0 and s1[i] == s2[j-1] and s1[i-1] == s2[j]:
                res = min(res, d[(i-2, j-2)] + 1)
            d[(i, j)] = res
    return d[(len1-1, len2-1)]

def get_kb_dist(a, b):
    pa, pb = KB_LAYOUT.get(a), KB_LAYOUT.get(b)
    if not pa or not pb: return 1.0
    return math.sqrt((pa[0]-pb[0])**2 + (pa[1]-pb[1])**2)

def calculate_score(input_word, candidate, dist, is_phonetic=False):
    # Yapper Priority: Phonetic matches are drastically boosted
    score = (dist * 1.5) - (2.5 if is_phonetic else 0)
    
    # Standard weighting
    if candidate.startswith(input_word[:2]): score -= 0.3 # Prefix bonus
    if candidate.startswith(input_word[:1]): score -= 0.1
    
    # Keyboard distance for single-char typos
    if dist == 1 and len(input_word) == len(candidate):
        for i in range(len(input_word)):
            if input_word[i] != candidate[i]:
                score -= (1.0 - min(1.0, get_kb_dist(input_word[i], candidate[i]))) * 0.5
                break
    
    # Length diff penalty
    score += abs(len(input_word) - len(candidate)) * 0.3
    return score

# --- 2. Corrected Simulation Engine ---

class SpellcheckSimulator:
    def __init__(self, dict_path):
        self.words = []
        self.phonetics = {}
        self.load_dictionary(dict_path)
        
    def load_dictionary(self, path):
        with open(path, 'r') as f:
            content = f.read()
            word_blocks = re.findall(r'function getWords_\d+\(\).*?return \{(.*?)\}\nend', content, re.DOTALL)
            for block in word_blocks:
                self.words.extend(re.findall(r'"([^"]+)"', block))
            
            phon_blocks = re.findall(r'function getPhonetics_\d+\(\).*?return \{(.*?)\}\nend', content, re.DOTALL)
            for block in phon_blocks:
                matches = re.findall(r'\["([^"]+)"\] = \{([^\}]+)\}', block)
                for p_hash, idx_list in matches:
                    self.phonetics[p_hash] = [int(i.strip()) - 1 for i in idx_list.split(',')]

    def get_suggestions(self, input_word, max_count=4):
        input_word = input_word.lower()
        p_hash = get_phonetic_hash(input_word)
        phon_words = set()
        if p_hash in self.phonetics:
            for idx in self.phonetics[p_hash]:
                if idx < len(self.words): phon_words.add(self.words[idx])
        
        # Candidate collection
        candidates = set(phon_words)
        pfx = input_word[:1]
        for w in self.words:
            if w.lower().startswith(pfx) and abs(len(w) - len(input_word)) <= 2:
                candidates.add(w)
            if len(candidates) > 1000: break
            
        results = []
        for cand in candidates:
            dist = damerau_levenshtein(input_word, cand.lower(), max_dist=3)
            if dist is not None:
                is_p = (cand in phon_words)
                score = calculate_score(input_word, cand.lower(), dist, is_p)
                results.append({'word': cand, 'score': score, 'dist': dist, 'is_p': is_p})
        
        results.sort(key=lambda x: (x['score'], x['dist'], x['word'].lower()))
        return results[:max_count]

def run_simulation():
    sim = SpellcheckSimulator("Src/Spellcheck/Dicts/enBase.lua")
    
    test_cases = [
        ("nite", "night"), ("fone", "phone"), ("tuff", "tough"), ("enuff", "enough"), ("laf", "laugh"), 
        ("kue", "queue"), ("fisix", "physics"), ("nefew", "nephew"), ("oxigen", "oxygen"), ("site", "cite"),
        ("applr", "apple"), ("wuick", "quick"), ("hellp", "hello"), ("soace", "space"), ("rivera", "rivers"),
        ("teh", "the"), ("recieve", "receive"), ("freind", "friend"), ("beleive", "believe"), ("wierd", "weird"),
        ("aple", "apple"), ("appple", "apple"), ("comming", "coming"), ("hapened", "happened"), ("arguement", "argument"),
        ("congratsulations", "congratulations"), ("unbeleebable", "unbelievable"), ("buisness", "business"), ("minuite", "minute"),
        ("dont", "don't"), ("cant", "can't"), ("shouldnt", "shouldn't")
    ]
    
    scores = []
    print("| Input | Expected | Rank | Top Candidates |")
    print("|-------|----------|------|----------------|")
    
    for input_w, expected in test_cases:
        suggestions = sim.get_suggestions(input_w)
        rank = "Miss"
        for i, sugg in enumerate(suggestions, 1):
            if sugg['word'].lower() in [expected.lower(), expected.replace("'","").lower()]:
                rank = str(i)
                break
        
        # Calculate rank-based score (1 = Top, 4 = Miss)
        score = 1 if rank == "1" else (4 if rank != "Miss" else 10)
        scores.append(score)
        
        top_words = ", ".join([f"{s['word']}" for s in suggestions])
        print(f"| {input_w} | {expected} | {rank} | {top_words} |")

    avg = sum(scores) / len(scores)
    print(f"\n**Final Accuracy Score: {avg:.2f} (Target: < 2.0)**")

if __name__ == "__main__":
    run_simulation()
