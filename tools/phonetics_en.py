import re

def get_phonetic_hash(word):
    if not word: return ""
    # Convert to uppercase
    hash_str = word.upper()
    
    # Strip non-alphabetic characters (including apostrophes)
    hash_str = re.sub(r'[^A-Z]', '', hash_str)
    
    # Strip duplicate adjacent letters (e.g., "LL" -> "L")
    hash_str = re.sub(r'([A-Z])\1+', r'\1', hash_str)
    
    # Silent/Variable replacements
    hash_str = hash_str.replace("GHT", "T")
    hash_str = hash_str.replace("PH", "F")
    hash_str = hash_str.replace("KN", "N")
    hash_str = hash_str.replace("GN", "N")
    hash_str = hash_str.replace("WR", "R")
    hash_str = hash_str.replace("CH", "K")
    hash_str = hash_str.replace("SH", "X")
    hash_str = hash_str.replace("C", "K")
    hash_str = hash_str.replace("Q", "K")
    hash_str = hash_str.replace("X", "KS")
    hash_str = hash_str.replace("Z", "S")

    # GH at the end of word often sounds like F (laugh, enough)
    if hash_str.endswith("GH"):
        hash_str = hash_str[:-2] + "F"
    else:
        hash_str = hash_str.replace("GH", "") # Silent GH (night, through)
    
    if not hash_str: return ""
    
    # Keep the first letter, strip vowels from the rest
    first_char = hash_str[0]
    rest = hash_str[1:]
    rest = re.sub(r'[AEIOUY]', '', rest)
    
    return first_char + rest
