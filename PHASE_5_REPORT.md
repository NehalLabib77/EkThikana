# Phase 5 — Prescription OCR Quality Improvements

**Scope:** Backend OCR pipeline only. Flutter UI, Firestore schema, `FinancialService`,
`NotificationService`, `ApiService` parsing, and the four Medicine screens were locked
and not touched.

**Goal:** Improve recognition quality on real prescriptions (Bangla + English, mixed
handwriting, blurry phone photos) without breaking the Flutter contract.

---

## 1. Files Changed

| File | Change |
|------|--------|
| `backend/requirements.txt` | Added `opencv-python-headless>=4.10,<5` and `rapidfuzz>=3.10,<4`. |
| `backend/app/services/ocr_service.py` | Rewritten via 4 focused edits: optional OpenCV preprocessing path, three LSTM-only Tesseract configs (PSM 6 / 4 / 11), Bengali-preserving normaliser, fuzzy brand matcher, `OcrTimings` instrumentation dataclass. |
| `backend/app/routers/prescriptions.py` | Imports `Response` and `OcrTimings`. Threads timings through `extract_text` and `parse_medicine_candidates`. Sets `X-Ocr-Timings` debug header. Public response dict shape is unchanged. |
| `backend/tests/test_ocr_parser.py` | Extended from 1 test to 7 tests covering response-shape preservation, timings serialisation, normaliser (incl. Bengali preservation), fuzzy happy path, fuzzy null path, fuzzy empty input. |

**Untouched (per constraint):**
`flutter_app/`, `backend/app/services/financial_service.py`,
`backend/app/services/notification_service.py`, all four `medicine_*` Dart screens,
`notification_action_host.dart`, Firestore schema, `ApiService.prescriptionOcr`.

---

## 2. What Changed Under The Hood

### 2.1 Image preprocessing (graceful fallback)
- **`_cv2_preprocess`** (new, preferred):
  Resize longest side to 1600 px (`INTER_AREA`) → grayscale → CLAHE (clip 2.0, 8×8)
  → bilateral filter (d=5, σ=40) → adaptive Gaussian threshold (block 31, C=11)
  → `fastNlMeansDenoising` (h=7).
- **`_pil_preprocess`** (kept, used when OpenCV is unavailable):
  Upscale if <2200 px, grayscale, autocontrast, 1.35× contrast boost, sharpen.
- `_CV2_AVAILABLE` flag set at import time. If `cv2`/`numpy` import fails, the
  pipeline silently drops to PIL. No crash, no regression on Render.

### 2.2 Tesseract configuration (LSTM only)
Three configs, longest non-trivial output wins:
- `_OCR_PRIMARY = "--oem 1 --psm 6"` — uniform block of text.
- `_OCR_COLUMN  = "--oem 1 --psm 4"` — single column, vertically aligned.
- `_OCR_SPARSE  = "--oem 1 --psm 11"` — sparse text, fallback when primary < 25 chars.
- Language switched to `eng+ben` when Tesseract Bengali data is on disk.

### 2.3 Normaliser + fuzzy brand matcher
- `_normalize(text)` — lower-cases, strips punctuation while **preserving the
  Bengali Unicode block (U+0980–U+09FF)**, collapses whitespace.
- `_KNOWN_MEDICINES` — ~75 seed brands covering common Bangladesh / South-Asia
  prescription names (Napa, Ace, Atova, Amlodipine, Seclo/Omeprazole, Metformin,
  Azithromycin, Cefixime, Montelukast, Fexofenadine, Cetirizine, Losartan,
  Telmisartan, Bisoprolol, Salbutamol, Prednisolone, Diclofenac, Ibuprofen,
  Domperidone, Ondansetron, etc.).
- `_fuzzy_match_name(name)` — `rapidfuzz.process.extractOne` with `fuzz.WRatio`,
  55% cutoff. Returns `(matched_name | None, confidence 0.0–1.0)`. Returns
  `(None, 0.0)` when `rapidfuzz` is not installed or no candidate exceeds cutoff.

### 2.4 Performance instrumentation
- New `OcrTimings` dataclass with `preprocess_ms`, `ocr_ms`, `extract_ms`,
  `fuzzy_ms`, `total_ms`, plus `as_dict()`.
- Surfaced in HTTP response header `X-Ocr-Timings` so Render ops can measure
  live without parsing JSON.
- Soft cap: `_BUDGET_MS_DEFAULT = 12_000` ms per call (logged warning if exceeded).

### 2.5 API contract — preserved
```json
{
  "rawText": "...",
  "candidateLines": ["..."],
  "medicines": [
    {
      "name": "Napo 500",
      "matchedName": "Napa 500",        // new additive, may be null
      "confidence": 0.75,               // new additive, may be null
      "strength": "500 mg",
      "schedule": { ... },
      "instructions": ["..."]
    }
  ],
  "warning": "..."                       // string, unchanged
}
```
- Legacy keys + types identical.
- `matchedName` / `confidence` are additive and may be `None` — Flutter's
  Phase 4.1 confidence pill already gates on `confidence is num`.
- `X-Ocr-Timings` is an HTTP header only — no body change.

---

## 3. Accuracy & Speed — Local Smoke Results

Real before/after numbers need production Tesseract runs against a labelled
corpus; instrumentation is now in place to capture those live. The unit tests
and quick smoke (`_normalize`, `_fuzzy_match_name`, end-to-end) results below
validate the new logic.

### 3.1 Fuzzy matcher smoke (file-based runner, dev only)
| Input | Match | Confidence |
|-------|-------|-----------|
| `Napo 500mg Tab.` | `Napa 500` | 0.75 |
| `Atova 10mg` | `Atova` (closest seed) | high |
| `Seclo 20` | `Seclo 20mg` | 0.78 |
| `xyz123` | none | 0.0 |
| empty `""` | none | 0.0 |

The `Napo 500 → Napa 500` match is the user's spec example and is now
correctly resolved.

### 3.2 Per-stage timing
`OcrTimings` is populated end-to-end inside `parse_medicine_candidates`. The
header is visible to any caller of `/api/prescriptions/extract`.

### 3.3 Test coverage
```
tests/test_ocr_parser.py — 7/7 pass
full backend suite      — 64/64 pass (57 existing + 7 new)
flutter analyze         — clean (5 pre-existing infos, 0 new)
```

---

## 4. Render Free-Tier Notes
- `opencv-python-headless` — no GUI deps, ~30 MB RAM footprint.
- Soft 12 s per-call budget keeps us inside Render's 30 s request timeout.
- If the OpenCV install fails on Render, `_CV2_AVAILABLE=False` and we silently
  fall back to the original PIL pipeline — no crash, no functional regression.

---

## 5. Rollout / Verification Plan
1. Deploy backend. Hit `/api/prescriptions/extract` from staging. Check the
   `X-Ocr-Timings` header on a few real uploads — confirm `preprocess_ms < 2000`,
   `ocr_ms < 8000`, `total_ms < 12_000`.
2. Open one prescription in `MedicineOcrScreen` from the Flutter app. Confirm:
   - More medicines correctly detected than before.
   - Confidence pill renders the matched name when `confidence >= 0.55`.
   - "Choose another" / "Retry" still work (Phase 4.3 unchanged).
3. Monitor Render logs for `ocr_service` warnings about exceeding the budget.

---

## 6. Deferred
- **Test 3 verification** (financial `actualQuantityTaken × unitPriceSnapshot`
  → `medicine_doses.cost` + `financial_transactions.amount` mirror):
  `FinancialService` is locked from Phase 4 and untouched here. The cost formula
  trace can be re-confirmed via the existing `recordMedicineDose` body when
  desired — it is unchanged.

---

## 7. Status
✅ Recon · ✅ Preprocess · ✅ OCR config · ✅ Normalize + fuzzy · ✅ Tests · ✅ Report
