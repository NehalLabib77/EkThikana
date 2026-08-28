"""PART 4 secret-bearer filename scanner. Reports paths only. Never prints contents."""
import os
ROOT = r"d:\EkThikana_Full_Production_Starter"
EXACT = {".env", ".env.example", ".env.local", ".env.production", ".env.production.local", ".env.development",
         "key.properties"}
EXT = (".pem", ".p12", ".jks", ".keystore")
SUBSTR = ("service-account", "firebase-adminsdk")
hits = []
for r, _, fs in os.walk(ROOT):
    # Skip our own venv and obvious caches
    parts = r.split(os.sep)
    if any(p in (".venv", "node_modules", "__pycache__", ".dart_tool", "build") for p in parts):
        continue
    for f in fs:
        low = f.lower()
        if f in EXACT or f.endswith(EXT) or any(s in low for s in SUBSTR):
            hits.append(os.path.join(r, f))
print("\n".join(hits) if hits else "NONE")