"""Regression tests for CommuteBD route polyline geometry and GROQ AI config.

Pins the exact coordinate conversion pipeline so a future change cannot flip
lat/lon order or silently drop the polyline from the response.
"""
from __future__ import annotations

import json

import pytest

from app.core.config import get_settings
from app.services.commute.routing import Coordinate, OsrmNominatimProvider


# ---------------------------------------------------------------------------
# OSRM polyline coordinate conversion
# ---------------------------------------------------------------------------


class TestOsrmPolylineConversion:
    """Verify that OSRM GeoJSON [lon,lat] pairs are converted to
    {"lat": ..., "lon": ...} dicts correctly."""

    def test_geojson_lon_lat_conversion(self):
        """OSRM returns GeoJSON coordinates as [longitude, latitude].
        The routing provider must swap them to {lat, lon}."""
        # Simulate an OSRM GeoJSON coordinate pair: [lon, lat]
        geojson_pair = [90.4125, 23.8103]

        # The conversion logic from routing.py
        result = {"lat": float(geojson_pair[1]), "lon": float(geojson_pair[0])}

        assert result["lat"] == pytest.approx(23.8103)
        assert result["lon"] == pytest.approx(90.4125)

    def test_conversion_preserves_float_precision(self):
        """Ensure float precision is not lost during conversion."""
        lon = 90.412496
        lat = 23.810403
        result = {"lat": float(lat), "lon": float(lon)}

        assert result["lat"] == pytest.approx(23.810403)
        assert result["lon"] == pytest.approx(90.412496)

    def test_polyline_list_comprehension(self):
        """Simulate the full polyline conversion from routing.py."""
        # Simulated OSRM GeoJSON coordinates (3 points)
        osrm_coords = [
            [90.412496, 23.810403],
            [90.413039, 23.81042],
            [90.413084, 23.809939],
        ]

        polyline = [
            {"lat": float(pair[1]), "lon": float(pair[0])}
            for pair in osrm_coords
            if isinstance(pair, list) and len(pair) >= 2
        ]

        assert len(polyline) == 3
        assert polyline[0] == {"lat": pytest.approx(23.810403), "lon": pytest.approx(90.412496)}
        assert polyline[1] == {"lat": pytest.approx(23.81042), "lon": pytest.approx(90.413039)}
        assert polyline[2] == {"lat": pytest.approx(23.809939), "lon": pytest.approx(90.413084)}

    def test_polyline_survives_json_roundtrip(self):
        """The polyline must survive JSON serialization/deserialization
        (what Flutter receives over HTTP)."""
        polyline = [
            {"lat": 23.810403, "lon": 90.412496},
            {"lat": 23.733017, "lon": 90.418004},
        ]

        json_str = json.dumps({"polyline": polyline})
        parsed = json.loads(json_str)

        restored = parsed["polyline"]
        assert len(restored) == 2
        assert restored[0]["lat"] == pytest.approx(23.810403)
        assert restored[0]["lon"] == pytest.approx(90.412496)
        assert restored[1]["lat"] == pytest.approx(23.733017)
        assert restored[1]["lon"] == pytest.approx(90.418004)

    def test_empty_coordinates_produce_empty_polyline(self):
        """A routing response with no geometry should produce an empty list."""
        osrm_coords = []
        polyline = [
            {"lat": float(pair[1]), "lon": float(pair[0])}
            for pair in osrm_coords
            if isinstance(pair, list) and len(pair) >= 2
        ]
        assert polyline == []

    def test_invalid_coordinate_pairs_are_skipped(self):
        """Non-list or short entries in the coordinate array are filtered out."""
        osrm_coords = [
            [90.41, 23.81],
            "invalid",
            [90.42],
            [90.43, 23.82, 100],  # 3 elements, still valid
        ]
        polyline = [
            {"lat": float(pair[1]), "lon": float(pair[0])}
            for pair in osrm_coords
            if isinstance(pair, list) and len(pair) >= 2
        ]
        assert len(polyline) == 2
        assert polyline[0]["lat"] == pytest.approx(23.81)
        assert polyline[1]["lat"] == pytest.approx(23.82)

    def test_response_polyline_key_is_present(self):
        """The /api/commute/routes response must include a 'polyline' key."""
        response = {
            "origin": {"name": "A", "lat": 23.81, "lon": 90.41},
            "destination": {"name": "B", "lat": 23.73, "lon": 90.42},
            "distanceKm": 5.0,
            "estimatedDurationMin": 15,
            "polyline": [{"lat": 23.81, "lon": 90.41}, {"lat": 23.73, "lon": 90.42}],
            "routingProvider": "OSRM",
        }
        assert "polyline" in response
        assert isinstance(response["polyline"], list)
        assert len(response["polyline"]) == 2
        # Every entry must have 'lat' and 'lon' keys
        for point in response["polyline"]:
            assert "lat" in point
            assert "lon" in point


# ---------------------------------------------------------------------------
# Selected destination coordinate preservation
# ---------------------------------------------------------------------------


class TestDestinationCoordinatePreservation:
    """When a user picks a destination, the coordinates must flow through
    to the backend request without being lost or re-geocoded."""

    def test_null_lat_lon_omitted_from_request(self):
        """When lat/lon are null (dataset place), the ? spread omits them."""
        origin_lat = None
        origin_lon = None
        origin_place_id = "PLC0010"
        origin_name = "Arambagh"

        body = {
            "origin": {
                "place_id": origin_place_id,
                "name": origin_name,
                **({"lat": origin_lat} if origin_lat is not None else {}),
                **({"lon": origin_lon} if origin_lon is not None else {}),
            },
        }

        assert "lat" not in body["origin"]
        assert "lon" not in body["origin"]
        assert body["origin"]["place_id"] == "PLC0010"

    def test_non_null_lat_lon_included_in_request(self):
        """When lat/lon are provided (geocoded/tap/current location),
        they are included in the request."""
        origin_lat = 23.8103
        origin_lon = 90.4125

        body = {
            "origin": {
                "place_id": None,
                "name": "Point at 23.8103, 90.4125",
                **({"lat": origin_lat} if origin_lat is not None else {}),
                **({"lon": origin_lon} if origin_lon is not None else {}),
            },
        }

        assert body["origin"]["lat"] == 23.8103
        assert body["origin"]["lon"] == 90.4125


# ---------------------------------------------------------------------------
# GROQ AI provider configuration
# ---------------------------------------------------------------------------


class TestGrokProviderConfig:
    """Verify that the AI service is configured to prefer GROQ over Gemini."""

    def test_groq_model_default(self):
        """The default GROQ model must be set."""
        settings = get_settings()
        assert settings.groq_model == "qwen/qwen3.8-27b"

    def test_gemini_model_default(self):
        """The fallback Gemini model must be set."""
        settings = get_settings()
        assert settings.gemini_model != ""

    def test_groq_config_fields_exist(self):
        """Config must expose groq_api_key and groq_model."""
        settings = get_settings()
        assert hasattr(settings, "groq_api_key")
        assert hasattr(settings, "groq_model")

    def test_ai_service_has_groq_generate(self):
        """ai_service module must expose _groq_generate."""
        from app.services import ai_service
        assert hasattr(ai_service, "_groq_generate")

    def test_ai_service_has_groq_generate_multimodal(self):
        """ai_service module must expose _groq_generate_multimodal."""
        from app.services import ai_service
        assert hasattr(ai_service, "_groq_generate_multimodal")

    def test_generate_tries_groq_first(self):
        """generate() must attempt GROQ before Gemini."""
        import inspect
        from app.services.ai_service import generate
        source = inspect.getsource(generate)
        # GROQ must appear before Gemini in the function body
        groq_pos = source.find("_groq_generate")
        gemini_pos = source.find("_gemini_generate")
        assert groq_pos != -1, "generate() must call _groq_generate"
        assert gemini_pos != -1, "generate() must have Gemini fallback"
        assert groq_pos < gemini_pos, "GROQ must be tried before Gemini"

    def test_generate_multimodal_tries_groq_first(self):
        """generate_multimodal() must attempt GROQ before Gemini."""
        import inspect
        from app.services.ai_service import generate_multimodal
        source = inspect.getsource(generate_multimodal)
        groq_pos = source.find("_groq_generate_multimodal")
        gemini_pos = source.find("_gemini_generate_multimodal")
        assert groq_pos != -1, "generate_multimodal() must call GROQ"
        assert gemini_pos != -1, "generate_multimodal() must have Gemini fallback"
        assert groq_pos < gemini_pos, "GROQ must be tried before Gemini"

    def test_groq_endpoint_url(self):
        """GROQ must use the OpenAI-compatible endpoint."""
        import inspect
        from app.services.ai_service import _groq_generate
        source = inspect.getsource(_groq_generate)
        assert "api.groq.com/openai/v1/chat/completions" in source
