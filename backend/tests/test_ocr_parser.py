from app.services.ocr_service import parse_medicine_candidates


def test_prescription_parser_extracts_only_visible_schedule_data():
    text = """
    Tab. Amlodipine 5mg 1+0+0 after breakfast 08:00 AM
    Cap Omeprazole 20mg 1-0-0 before breakfast
    Tab Metformin 500mg 1+0+1 after food 08:00 PM
    """
    meds = parse_medicine_candidates(text)
    assert len(meds) == 3
    assert meds[0]["name"] == "Amlodipine"
    assert meds[0]["dose"].lower() == "5mg"
    assert meds[0]["explicitTimes"] == ["08:00 AM"]
    # No clock time is invented when the prescription only gives frequency.
    assert meds[1]["explicitTimes"] == []
    assert "1-0-0" in meds[1]["scheduleHints"]
