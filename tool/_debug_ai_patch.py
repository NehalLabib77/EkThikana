"""Debug: confirm that the AI router's extract_pdf_text is patched."""
import sys
sys.path.insert(0, "d:/EkThikana_Full_Production_Starter/backend")
sys.path.insert(0, "d:/EkThikana_Full_Production_Starter/backend/tests")

from app.routers import ai as ai_mod
print("Before fixture:")
print("  ai.extract_pdf_text is pypdf-backed:",
      ai_mod.extract_pdf_text.__module__,
      ai_mod.extract_pdf_text.__name__)

# Apply the same fixture patches inline.
import app.services.pdf_service as pdf_mod
new_fn = lambda data, page=None, max_chars=70000: f"fake-pdf-text bytes={len(data)}"
ai_mod.extract_pdf_text = new_fn
print("After direct set:")
print("  ai.extract_pdf_text:", ai_mod.extract_pdf_text(b"hello"))