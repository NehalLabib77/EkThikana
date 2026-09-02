"""Guards for prescription OCR quality and, above all, for its honesty.

Tesseract is not installed in CI, so the recogniser is driven with a fake
``pytesseract`` that returns known confidences. That is the right level to
test at: what needs pinning is not whether Tesseract can read handwriting --
it is whether *this code* reports what Tesseract actually said, picks the
variant that measurably read best, and refuses to improve a medicine name
behind the reader's back.

The rules being held down:

  1. A confidence is never invented. No words, no number -- ``None`` and a
     band of ``unknown``, never a plausible default.
  2. A medicine name is never silently corrected. Suggestions are offered and
     labelled ``applied: false``; ambiguous ones are withheld entirely.
  3. The model pass may regroup OCR text and may not add to it. Anything it
     returns that is not in the source is dropped.
  4. A missing language pack is reported, not worked around.
"""
from __future__ import annotations

import sys
import types

import pytest
import numpy as np
from PIL import Image, ImageDraw

from app.services.ocr import languages, medicine_names, preprocess, structuring
from app.services.ocr.recognition import (
    RecognitionResult,
    WordResult,
    band_for,
    recognise,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _page(width=900, height=1200, *, angle=0.0, background=245) -> Image.Image:
    """A synthetic prescription-ish page: dark text rows on light paper.

    Deliberately not a clean two-value image. Real paper is not uniform and
    real ink is not one grey, and an Otsu test against a perfectly bimodal
    image proves nothing about the photos this code will actually see.
    """
    rng = np.random.default_rng(7)
    pixels = np.clip(
        rng.normal(background, 6, size=(height, width)), 0, 255
    ).astype(np.uint8)
    image = Image.fromarray(pixels, mode="L")

    draw = ImageDraw.Draw(image)
    margin = max(20, width // 8)
    for row in range(8):
        top = 120 + row * 110
        if top + 34 >= height:
            break
        draw.rectangle([margin, top, width - margin, top + 34], fill=35)

    if angle:
        image = image.rotate(angle, resample=Image.Resampling.BICUBIC, fillcolor=background)
    return image


def _result(words, text="some recognised text that is long enough to count"):
    return RecognitionResult(
        text=text,
        words=[WordResult(text=t, confidence=c, line_index=0) for t, c in words],
    )


class _FakeTesseract:
    """Stands in for pytesseract, returning scripted confidences."""

    def __init__(self, by_call):
        self._by_call = list(by_call)
        self.calls = []

    def image_to_data(self, image, lang=None, config="", output_type=None):
        self.calls.append({"lang": lang, "config": config, "size": image.size})
        payload = self._by_call[min(len(self.calls) - 1, len(self._by_call) - 1)]
        words = payload["words"]
        count = len(words)
        return {
            "text": [w[0] for w in words],
            "conf": [w[1] for w in words],
            "block_num": [0] * count,
            "par_num": [0] * count,
            "line_num": list(range(count)),
        }


@pytest.fixture
def fake_tesseract(monkeypatch):
    """Install a scripted pytesseract for the duration of one test."""

    def install(by_call):
        module = types.ModuleType("pytesseract")
        fake = _FakeTesseract(by_call)
        module.image_to_data = fake.image_to_data
        module.get_languages = lambda config="": ["ben", "eng", "osd"]
        module.get_tesseract_version = lambda: "5.3.0"
        output = types.ModuleType("pytesseract.Output")
        output.DICT = "dict"
        module.Output = output
        monkeypatch.setitem(sys.modules, "pytesseract", module)
        return fake

    return install


# ---------------------------------------------------------------------------
# Confidence is measured, never invented
# ---------------------------------------------------------------------------


def test_a_result_with_no_words_reports_unknown_not_zero():
    empty = RecognitionResult(text="")

    assert empty.mean_confidence is None
    assert empty.band == "unknown"


def test_bands_follow_the_documented_boundaries():
    assert band_for(95.0) == "high"
    assert band_for(80.0) == "high"
    assert band_for(79.9) == "medium"
    assert band_for(60.0) == "medium"
    assert band_for(59.9) == "low"
    assert band_for(None) == "unknown"


def test_noise_words_do_not_drag_down_a_clean_read():
    # Page edges and staple shadows come back as very low-confidence tokens.
    # Averaging them in would demote a genuinely clean prescription.
    result = _result([("Amlodipine", 94.0), ("5mg", 91.0), ("|", 3.0), (".", 1.0)])

    assert result.mean_confidence == pytest.approx(92.5)
    assert result.band == "high"


def test_the_reported_confidence_is_a_whole_number():
    # The underlying score is not calibrated finely enough for a decimal to
    # mean anything, and "82.4%" implies a precision it does not have.
    payload = _result([("Metformin", 82.4), ("500mg", 82.8)]).to_dict()

    assert payload["meanConfidence"] == 83
    assert payload["band"] == "high"


def test_a_word_confidence_is_none_when_the_word_was_not_recognised():
    # The parser cleans names, so a cleaned name may not map back to any
    # recognised word. Substituting the page average there would attach a
    # number this name never earned.
    result = _result([("Amlodipine", 94.0), ("5mg", 91.0)])

    assert result.confidence_for("Amlodipine") == pytest.approx(94.0)
    assert result.confidence_for("Rosuvastatin") is None
    assert result.confidence_for("") is None


def test_a_short_read_scores_zero_however_confident_it_looks():
    # Tesseract is extremely sure about the four characters it found on a
    # blank page. That is not a usable prescription.
    confident_but_empty = _result([("Rx", 99.0)], text="Rx")

    assert confident_but_empty.mean_confidence == pytest.approx(99.0)
    assert confident_but_empty.score == 0.0


# ---------------------------------------------------------------------------
# The best variant wins on measurement
# ---------------------------------------------------------------------------


def test_recognise_returns_the_variant_that_actually_read_best(fake_tesseract):
    long_text = " ".join(["Tab Amlodipine 5mg 1+0+0 after breakfast"] * 6)
    fake_tesseract(
        [
            # First pass reads poorly ...
            {"words": [(word, 45.0) for word in long_text.split()]},
            # ... a later one reads the same page cleanly.
            {"words": [(word, 92.0) for word in long_text.split()]},
        ]
    )

    result = recognise(_page(), try_orientations=False)

    assert result.mean_confidence == pytest.approx(92.0)
    assert result.band == "high"
    assert result.variant, "the winning variant must be named for the logs"


def test_recognise_stops_early_on_a_clean_read(fake_tesseract):
    long_text = " ".join(["Tab Amlodipine 5mg after breakfast"] * 8)
    fake = fake_tesseract([{"words": [(w, 95.0) for w in long_text.split()]}])

    recognise(_page(), try_orientations=False)

    # Four variants times three page-segmentation modes is twelve passes. A
    # page that read cleanly on the first must not pay for the other eleven.
    assert len(fake.calls) == 1


def test_recognise_returns_an_empty_result_rather_than_raising(fake_tesseract):
    fake_tesseract([{"words": []}])

    result = recognise(_page(), try_orientations=False)

    assert result.text == ""
    assert result.band == "unknown"


def test_a_short_but_clean_read_is_returned_rather_than_discarded(fake_tesseract):
    # `score` zeroes anything shorter than a prescription, which is right for
    # ranking a full page and wrong as a test of existence. A crop of just the
    # medicine list -- or one Bengali instruction line -- reads perfectly and
    # scores zero, and used to come back as "nothing was recognised".
    fake_tesseract([{"words": [("খাবারের", 94.0), ("পরে", 94.0)]}])

    result = recognise(_page(), try_orientations=False)

    # The fake puts each word on its own line, so compare on content.
    assert result.text.split() == ["খাবারের", "পরে"]
    assert result.band == "high"
    assert result.score == 0.0, "still ranked below a full page, just not discarded"


def test_a_full_page_still_outranks_a_short_one(fake_tesseract):
    short = [("Rx", 99.0)]
    full = [(word, 70.0) for word in ("Tab Amlodipine 5mg 1+0+0 after breakfast " * 3).split()]
    fake_tesseract([{"words": short}, {"words": full}])

    result = recognise(_page(), try_orientations=False)

    assert "Amlodipine" in result.text
    assert result.mean_confidence == pytest.approx(70.0)


def test_recognise_survives_tesseract_being_absent(monkeypatch):
    # No pytesseract at all: an unreadable page, not a 500.
    monkeypatch.setitem(sys.modules, "pytesseract", None)

    result = recognise(_page(), try_orientations=False)

    assert result.text == ""
    assert result.band == "unknown"


def test_the_configured_language_reaches_tesseract(fake_tesseract):
    fake = fake_tesseract([{"words": [("Tab", 90.0)]}])

    recognise(_page(), language="eng+ben", try_orientations=False)

    assert fake.calls[0]["lang"] == "eng+ben"


# ---------------------------------------------------------------------------
# Preprocessing
# ---------------------------------------------------------------------------


def test_otsu_finds_the_split_between_ink_and_paper():
    threshold = preprocess.otsu_threshold(_page())

    # Ink sits around 35 and paper around 245, so a working cut lands between
    # them. Anything outside that range would binarise the page to one colour.
    assert 35 < threshold < 245


def test_otsu_lands_in_the_middle_of_the_plateau_not_on_the_ink():
    # Crisp text leaves a wide band of equally-good thresholds. Taking the
    # lowest would put the cut exactly on the ink value, where anti-aliased
    # stroke edges fall on the paper side and the text thins out.
    crisp = Image.new("L", (200, 200), 250)
    ImageDraw.Draw(crisp).rectangle([20, 20, 180, 100], fill=20)

    threshold = preprocess.otsu_threshold(crisp)

    assert 20 < threshold < 250
    assert abs(threshold - 135) < 40, "the cut should sit between the two peaks"


def test_otsu_survives_a_blank_page():
    blank = Image.new("L", (50, 50), 255)

    # No bimodality to find. It must return a usable number, not divide by
    # zero, because a blank page is a thing users photograph.
    assert 0 <= preprocess.otsu_threshold(blank) <= 255


def test_binarising_leaves_only_black_and_white():
    binary = np.asarray(preprocess.binarise(_page()))

    assert set(np.unique(binary).tolist()) <= {0, 255}


def test_skew_is_detected_on_a_tilted_page():
    # estimate_skew returns the rotation that *straightens* the page, so a
    # page tilted by -4 degrees needs +4 to correct it.
    assert preprocess.estimate_skew(_page(angle=-4.0)) == pytest.approx(4.0, abs=1.5)
    assert preprocess.estimate_skew(_page(angle=3.0)) == pytest.approx(-3.0, abs=1.5)


def test_a_straight_page_is_not_rotated():
    straight = _page()

    # Rotation resamples every pixel, so a spurious correction costs
    # sharpness it cannot repay.
    assert preprocess.deskew(straight) is straight


def test_a_tilted_page_produces_deskew_variants():
    names = [v.name for v in preprocess.variants(_page(angle=-4.0))]

    assert any(name.startswith("deskew_") for name in names)


def test_a_straight_page_produces_no_deskew_variants():
    names = [v.name for v in preprocess.variants(_page())]

    assert not any(name.startswith("deskew_") for name in names)
    assert names[0] == "normalised", "the cheapest variant must be tried first"


def test_small_images_are_upscaled_and_large_ones_are_not():
    small = preprocess.normalise(Image.new("RGB", (400, 500), 255))
    large = preprocess.normalise(Image.new("RGB", (3000, 4000), 255))

    assert max(small.size) > 500
    assert max(small.size) <= 500 * preprocess.MAX_UPSCALE + 1
    # Already large enough: upscaling further would invent no detail and only
    # cost recognition time.
    assert large.size == (3000, 4000)


def test_orientations_covers_every_right_angle():
    names = [v.name for v in preprocess.orientations(_page(300, 500))]

    assert names == ["rotate_90", "rotate_180", "rotate_270"]


# ---------------------------------------------------------------------------
# Medicine names: suggest, never replace
# ---------------------------------------------------------------------------


def test_the_shipped_vocabulary_loads():
    vocab = medicine_names.vocabulary()

    assert len(vocab) > 100
    assert "paracetamol" in vocab
    assert all(name == name.lower() for name in vocab)


def test_common_ocr_digit_confusions_resolve_to_the_real_name():
    # A zero read for an "o" and a one for an "l" are the two commonest
    # Tesseract slips on a Latin drug name.
    assert medicine_names.is_known("Metf0rmin")
    assert medicine_names.is_known("0meprazole")
    assert medicine_names.is_known("Paracetamo1")


def test_a_near_miss_gets_a_suggestion():
    suggestion = medicine_names.suggest("Amlodipin")

    assert suggestion is not None
    assert suggestion.suggested == "amlodipine"
    assert suggestion.band in {"high", "medium"}


def test_a_suggestion_is_never_applied_automatically():
    # The one mistake this feature must not make.
    annotated = medicine_names.annotate("Azithromicin")

    assert annotated["name"] == "Azithromicin", "the recognised text is what is shown"
    assert annotated["suggestion"]["suggested"] == "azithromycin"
    assert annotated["suggestion"]["applied"] is False


def test_a_different_drug_is_not_suggested_as_a_correction():
    # Clobazam and clonazepam are different medicines with different
    # indications. Offering one for the other would be dangerous, and
    # "clobazam" is simply not in the list.
    assert medicine_names.suggest("Clobazam") is None


def test_an_ambiguous_match_is_withheld():
    # Two equally plausible answers means we do not know which was meant,
    # and the alphabetically luckier one is not an answer.
    vocab = ("cefixime", "cefixima")

    assert medicine_names.suggest("cefixim", vocab=vocab) is None


def test_a_close_rival_below_the_floor_still_blocks_a_suggestion():
    # The runner-up need not itself clear the floor to make the winner an
    # unsafe pick. These two are constructed near-neighbours of "amlodipin":
    # the first scores 0.889 and would be suggested on its own, the second
    # 0.857 -- below the 0.86 floor, but only 0.032 behind. Scoring only
    # candidates above the floor made that rival invisible and let the
    # suggestion through.
    vocab = ("atlodipin", "azmlodippine")

    assert medicine_names.suggest("amlodipin", vocab=vocab) is None
    # On its own, the same winner is offered -- so the guard above is doing
    # the work, not the floor.
    assert medicine_names.suggest("amlodipin", vocab=("atlodipin",)) is not None


def test_an_unrivalled_near_miss_is_still_suggested():
    # The ambiguity guard must not swallow the ordinary case it exists
    # alongside.
    suggestion = medicine_names.suggest("cefixim", vocab=("cefixime", "metformin"))

    assert suggestion is not None
    assert suggestion.suggested == "cefixime"


def test_a_first_letter_mismatch_blocks_a_suggestion():
    # Nearly every dangerous confusion between two real drugs starts
    # differently; OCR slips rarely do.
    assert medicine_names.suggest("Xmlodipine") is None


def test_a_name_too_short_to_identify_anything_gets_no_suggestion():
    for fragment in ("Tab", "Cef", "Inj", "x"):
        assert medicine_names.suggest(fragment) is None


def test_an_exact_match_produces_no_suggestion():
    assert medicine_names.suggest("Paracetamol") is None
    assert medicine_names.annotate("Paracetamol")["recognisedAsKnownGeneric"] is True


def test_a_brand_name_is_left_completely_alone():
    # Most prescriptions here are written as brand names, which the list
    # deliberately excludes. No suggestion is the correct, ordinary outcome.
    for brand in ("Napa", "Seclo", "Monas", "Bizoran"):
        annotated = medicine_names.annotate(brand)
        assert annotated["name"] == brand
        assert annotated["suggestion"] is None


def test_an_empty_vocabulary_disables_suggestions_entirely():
    # No list means no basis for proposing a change.
    assert medicine_names.suggest("Amlodipin", vocab=()) is None
    assert medicine_names.is_known("Paracetamol", vocab=()) is False


# ---------------------------------------------------------------------------
# The model pass may regroup, never add
# ---------------------------------------------------------------------------


SOURCE = """
Tab. Amlodipine 5mg
1+0+0 after breakfast
Cap Omeprazole 20mg before food
"""


def test_the_model_may_regroup_what_ocr_actually_read():
    validated = structuring.validate(
        {
            "medicines": [
                {"name": "Amlodipine", "dose": "5mg", "instruction": "after breakfast"},
                {"name": "Omeprazole", "dose": "20mg", "instruction": "before food"},
            ]
        },
        SOURCE,
    )

    assert [m["name"] for m in validated] == ["Amlodipine", "Omeprazole"]
    assert validated[0]["instruction"] == "after breakfast"


def test_an_invented_medicine_is_dropped():
    # The prompt asks the model not to invent. This is what makes the
    # request enforceable.
    validated = structuring.validate(
        {
            "medicines": [
                {"name": "Amlodipine", "dose": "5mg", "instruction": ""},
                {"name": "Rosuvastatin", "dose": "10mg", "instruction": ""},
            ]
        },
        SOURCE,
    )

    assert [m["name"] for m in validated] == ["Amlodipine"]


def test_an_invented_dose_is_stripped_but_the_medicine_is_kept():
    # The name is real, so the entry is worth keeping; the dose was never
    # written, so it must not survive.
    validated = structuring.validate(
        {"medicines": [{"name": "Amlodipine", "dose": "10mg", "instruction": ""}]},
        SOURCE,
    )

    assert validated[0]["name"] == "Amlodipine"
    assert validated[0]["dose"] == ""


def test_an_invented_instruction_is_stripped():
    validated = structuring.validate(
        {"medicines": [{"name": "Omeprazole", "dose": "", "instruction": "twice daily"}]},
        SOURCE,
    )

    assert validated[0]["instruction"] == ""


def test_a_malformed_response_is_rejected_wholesale():
    assert structuring.validate("not json", SOURCE) is None
    assert structuring.validate({"medicines": "nope"}, SOURCE) is None
    assert structuring.validate({}, SOURCE) is None


def test_json_is_recovered_from_a_fenced_reply():
    parsed = structuring._extract_json(
        'Here you go:\n```json\n{"medicines": []}\n```\nHope that helps.'
    )

    assert parsed == {"medicines": []}


def test_a_reply_with_no_json_yields_nothing():
    assert structuring._extract_json("I could not read that prescription.") is None


@pytest.mark.anyio
async def test_structuring_falls_back_silently_when_the_model_is_unavailable(monkeypatch):
    # No API key, a quota refusal and a provider outage all arrive here as an
    # exception. None of them may break prescription scanning.
    import app.services.ai_service as ai

    async def _boom(uid, prompt):
        raise RuntimeError("no API key")

    monkeypatch.setattr(ai, "generate", _boom)

    assert await structuring.structure("uid", SOURCE) is None


@pytest.mark.anyio
async def test_structuring_declines_text_too_short_to_be_a_prescription():
    assert await structuring.structure("uid", "Rx") is None


# ---------------------------------------------------------------------------
# Language availability is reported, not assumed
# ---------------------------------------------------------------------------


def test_a_missing_bengali_pack_is_reported_rather_than_worked_around(monkeypatch):
    # An English-only engine does not fail on a Bengali prescription -- it
    # returns confident-looking Latin nonsense. That has to be visible.
    monkeypatch.setattr(languages, "installed", lambda: ("eng", "osd"))
    monkeypatch.setattr(languages, "tesseract_version", lambda: "5.3.0")

    status = languages.status()

    assert status["available"] is True
    assert status["bengaliSupported"] is False
    assert status["missingRecommended"] == ["ben"]
    assert status["language"] == "eng"
    assert "Bengali is not installed" in status["message"]


def test_both_packs_present_uses_both(monkeypatch):
    monkeypatch.setattr(languages, "installed", lambda: ("ben", "eng"))
    monkeypatch.setattr(languages, "tesseract_version", lambda: "5.3.0")

    status = languages.status()

    assert status["available"] is True
    assert status["bengaliSupported"] is True
    assert status["language"] == "eng+ben"


def test_tesseract_missing_entirely_is_its_own_state(monkeypatch):
    monkeypatch.setattr(languages, "installed", lambda: ())
    monkeypatch.setattr(languages, "tesseract_version", lambda: None)

    status = languages.status()

    assert status["available"] is False
    assert status["reason"] == "tesseract_not_found"


def test_best_language_never_requests_a_pack_it_cannot_confirm():
    # Asking for "ben" when the list could not be read would turn a missing
    # pack into a hard failure instead of a degraded read.
    assert languages.best_language(()) == "eng"
    assert languages.best_language(("eng",)) == "eng"
    assert languages.best_language(("ben",)) == "ben"
    assert languages.best_language(("ben", "eng")) == "eng+ben"
