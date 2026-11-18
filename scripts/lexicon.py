"""Build the sorted local completion table from the licensed FrequencyWords file."""
import hashlib
from pathlib import Path
import sys
import unicodedata

source = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(source).hexdigest() != "f81f7c570b6433764da99aa30f4dfb08d81c5926301377b709af23a13b1f9596":
    raise ValueError("Le fichier de fréquences reçu est invalide")

rows = []
for line in source.decode("utf-8").splitlines():
    word, _ = line.rsplit(" ", 1)
    if len(word) >= 2 and word.isalpha() and word == word.lower():
        key = "".join(c for c in unicodedata.normalize("NFKD", word) if not unicodedata.combining(c))
        rows.append((key.replace("œ", "oe").replace("æ", "ae"), word, len(rows)))

destination = Path("Keyboard/Lexique/fr.tsv")
destination.write_text("".join(f"{k}\t{w}\t{r}\n" for k, w, r in sorted(rows)), encoding="utf-8")
print(f"{len(rows)} formes françaises préparées")
