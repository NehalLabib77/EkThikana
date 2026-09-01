from app.routers import ai
print("extract_pdf_text on ai:", hasattr(ai, "extract_pdf_text"))
print("generate on ai:", hasattr(ai, "generate"))
print("generate_multimodal on ai:", hasattr(ai, "generate_multimodal"))