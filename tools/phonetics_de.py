import re

def get_phonetic_hash(word):
    if not word: return ""
    # Convert to uppercase
    hash_str = word.upper()
    
    # 1. Standardize Umlauts
    hash_str = hash_str.replace("Ä", "A")
    hash_str = hash_str.replace("Ö", "O")
    hash_str = hash_str.replace("Ü", "U")
    hash_str = hash_str.replace("ß", "SS")
    
    # Strip non-alphabetic characters (including hyphens now, etc.)
    hash_str = re.sub(r'[^A-Z]', '', hash_str)
    if not hash_str: return ""
    
    # 2. Consonant Groupings
    hash_str = hash_str.replace("SCH", "S")
    hash_str = hash_str.replace("CH", "X")
    hash_str = hash_str.replace("PH", "F")
    hash_str = hash_str.replace("V", "F")
    hash_str = hash_str.replace("W", "V")
    hash_str = hash_str.replace("Z", "S")
    hash_str = hash_str.replace("QU", "KV")
    hash_str = hash_str.replace("DT", "T")
    hash_str = hash_str.replace("TH", "T")
    
    # Strip duplicate adjacent letters (e.g., "LL" -> "L", "SS" -> "S")
    hash_str = re.sub(r'([A-Z])\1+', r'\1', hash_str)
    
    if not hash_str: return ""
    
    # Keep the first letter, strip vowels from the rest
    first_char = hash_str[0]
    rest = hash_str[1:]
    rest = re.sub(r'[AEIOUY]', '', rest)
    
    return first_char + rest
