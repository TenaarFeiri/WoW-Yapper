import sys
import os
import re
import random
import time
from collections import Counter

# ---------------------------------------------------------------------------
# Yapper Constants & Weights (Synchronised with Spellcheck.lua)
# ---------------------------------------------------------------------------
SCORE_WEIGHTS = {
    "lenDiff": 3.0,
    "longerPenalty": 2.0,
    "prefix": 1.5,
    "letterBag": 1.0,
    "bigram": 1.5,
    "kbProximity": 1.0,
    "firstCharBias": 1.5,
    "vowelBonus": 2.5,
    "distMultiplier": 1.25 # Implicit base weight for distance
}

KB_LAYOUT = {
    'q': (0, 0), 'w': (1, 0), 'e': (2, 0), 'r': (3, 0), 't': (4, 0), 'y': (5, 0), 'u': (6, 0), 'i': (7, 0), 'o': (8, 0), 'p': (9, 0),
    'a': (0.25, 1), 's': (1.25, 1), 'd': (2.25, 1), 'f': (3.25, 1), 'g': (4.25, 1), 'h': (5.25, 1), 'j': (6.25, 1), 'k': (7.25, 1), 'l': (8.25, 1),
    'z': (0.75, 2), 'x': (1.75, 2), 'c': (2.75, 2), 'v': (3.75, 2), 'b': (4.75, 2), 'n': (5.75, 2), 'm': (6.75, 2)
}

# ---------------------------------------------------------------------------
# Scoring Engine (Python Port)
# ---------------------------------------------------------------------------

def get_phonetic_hash(word):
    word = word.upper()
    word = re.sub(r'[^A-Z]', '', word)
    word = re.sub(r'(.)\1+', r'\1', word)
    
    word = word.replace("GHT", "T").replace("PH", "F").replace("KN", "N").replace("GN", "N").replace("WR", "R").replace("CH", "K").replace("X", "KS").replace("Z", "S") # Simplified port
    
    if word.endswith("GH"):
        word = word[:-2] + "F"
    else:
        word = word.replace("GH", "")
        
    if not word: return ""
    
    first = word[0]
    rest = re.sub(r'[AEIOUY]', '', word[1:])
    return first + rest

def damerau_levenshtein(s1, s2):
    s1 = s1.lower()
    s2 = s2.lower()
    d = {}
    len1 = len(s1)
    len2 = len(s2)
    for i in range(-1, len1 + 1):
        d[(i, -1)] = i + 1
    for j in range(-1, len2 + 1):
        d[(-1, j)] = j + 1

    for i in range(len1):
        for j in range(len2):
            if s1[i] == s2[j]:
                cost = 0
            else:
                cost = 1
            d[(i, j)] = min(
                d[(i - 1, j)] + 1,
                d[(i, j - 1)] + 1,
                d[(i - 1, j - 1)] + cost,
            )
            if i > 0 and j > 0 and s1[i] == s2[j - 1] and s1[i - 1] == s2[j]:
                d[(i, j)] = min(d[(i, j)], d[(i - 2, j - 2)] + cost)

    return d[(len1 - 1, len2 - 1)]

def get_bag_score(s1, s2):
    s1 = s1.lower()
    s2 = s2.lower()
    c1 = Counter(s1)
    c2 = Counter(s2)
    diff = c1 - c2
    diff.update(c2 - c1)
    return sum(abs(v) for v in diff.values())

def get_proximity_bonus(s1, s2):
    bonus = 0
    l1, l2 = len(s1), len(s2)
    min_len = min(l1, l2)
    for i in range(min_len):
        c1, c2 = s1[i].lower(), s2[i].lower()
        if c1 == c2: continue
        if c1 in KB_LAYOUT and c2 in KB_LAYOUT:
            p1, p2 = KB_LAYOUT[c1], KB_LAYOUT[c2]
            dist = ((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)**0.5
            bonus += (1.5 - dist) if dist < 1.5 else 0
    return bonus

def score_candidate(candidate, target):
    dist = damerau_levenshtein(candidate, target)
    bag = get_bag_score(candidate, target)
    len_diff = abs(len(candidate) - len(target))
    
    score = dist * SCORE_WEIGHTS["distMultiplier"]
    score += (len_diff * SCORE_WEIGHTS["lenDiff"])
    score += (bag * SCORE_WEIGHTS["letterBag"])
    
    if candidate[0].lower() == target[0].lower():
        score -= SCORE_WEIGHTS["firstCharBias"]
        
    if get_phonetic_hash(candidate) == get_phonetic_hash(target):
        score -= SCORE_WEIGHTS["vowelBonus"]
        
    prox = get_proximity_bonus(candidate, target)
    score -= (prox * SCORE_WEIGHTS["kbProximity"])
    
    return score

# ---------------------------------------------------------------------------
# Game Engine
# ---------------------------------------------------------------------------

def load_dictionary(path):
    print(f"Loading dictionary from {path}...")
    try:
        with open(path, 'r') as f:
            content = f.read()
            words = re.findall(r'"([A-Za-z]+)"', content)
            # Filter short words and abbreviations for better gameplay
            filtered = [w for w in words if len(w) > 4]
            return list(set(filtered))
    except Exception as e:
        print(f"Error loading dictionary: {e}")
        return []

def scramble_word(word):
    letters = list(word.lower())
    # Loop to ensure we actually change it
    scrambled = "".join(letters)
    attempts = 0
    while scrambled == word.lower() and attempts < 10:
        random.shuffle(letters)
        scrambled = "".join(letters)
        attempts += 1
    return scrambled

def run_game():
    dict_path = "Src/Spellcheck/Dicts/enBase.lua"
    words = load_dictionary(dict_path)
    if not words:
        print("Failed to load vocabulary. Game over.")
        return

    player_score = 0
    algo_score = 0
    target_score = 5
    round_num = 1

    print("\n" + "="*50)
    print("Welcome to THE YAPPER WORD GAME: MAN vs MACHINE")
    print(f"First to {target_score} wins.")
    print("="*50 + "\n")

    while player_score < target_score and algo_score < target_score:
        actual = random.choice(words)
        scrambled = scramble_word(actual)
        
        print(f"ROUND {round_num}")
        print(f"Scrambled Word: {scrambled}")
        sys.stdout.write("Your Guess? > ")
        sys.stdout.flush()
        
        start_time = time.time()
        # Non-blocking wait is hard in simple script, but sys.stdin.readline is fine for background interaction
        guess = sys.stdin.readline().strip().lower()
        if not guess: break
        
        # Algorithmic Competitor logic
        # For simplicity in this script, we'll scan a random subset + our target
        subset = random.sample(words, 1000)
        if actual not in subset: subset.append(actual)
        
        best_algo_guess = ""
        best_algo_score = float('inf')
        
        for cand in subset:
            s = score_candidate(cand, scrambled)
            if s < best_algo_score:
                best_algo_score = s
                best_algo_guess = cand

        print(f"\nCorrection took: {time.time() - start_time:.2f}s")
        print(f"Correct Word: {actual}")
        print(f"AI Guess:      {guess}")
        print(f"Algorithm:    {best_algo_guess} (Score: {best_algo_score:.2f})")
        
        win_p = (guess == actual.lower())
        win_a = (best_algo_guess.lower() == actual.lower())
        
        if win_p and not win_a:
            player_score += 1
            print(">>> POINT TO HUMAN!")
        elif win_a and not win_p:
            algo_score += 1
            print(">>> POINT TO ALGORITHM!")
        elif win_p and win_a:
            print(">>> DRAW!")
        else:
            print(">>> BOTH FAILED!")
            
        print(f"SCORE: HUMAN {player_score} - ALGORITHM {algo_score}\n")
        round_num += 1
        time.sleep(1)

    if player_score >= target_score:
        print("CONGRATULATIONS! YOU HAVE DEFEATED THE MACHINE.")
    else:
        print("THE ALGORITHM PREVAILS. BETTER LUCK NEXT RELOAD.")

if __name__ == "__main__":
    run_game()
