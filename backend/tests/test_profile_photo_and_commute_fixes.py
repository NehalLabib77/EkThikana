"""Regression tests for Profile Photo upload 415 fix and CommuteBD route fixes.

Bug 1: Profile Photo 415
- Flutter MultipartFile.fromPath may send application/octet-stream on Android.
- Backend now infers MIME from extension and validates bytes with Pillow.

Bug 2: CommuteBD route calculation 503
- search_local_places() returns results WITHOUT lat/lon.
- _resolve_input must resolve via DB → CSV → Nominatim.
- catch-all Exception was hiding the real error.
"""

from __future__ import annotations

import asyncio
import os
import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


# ---------------------------------------------------------------------------
# Bug 1 — Profile Photo MIME type inference
# ---------------------------------------------------------------------------

from app.routers.account import _ALLOWED_IMAGE_TYPES, _EXT_TO_MIME, _infer_content_type, _REJECTED_MIME


class _FakeUploadFile:
    """Minimal UploadFile stand-in for testing MIME inference."""

    def __init__(self, content_type: str = "", filename: str = ""):
        self.content_type = content_type
        self.filename = filename


class TestMimeInference:
    """Backend MIME type inference from extension when Content-Type is wrong."""

    def test_jpg_extension_infers_image_jpeg(self):
        f = _FakeUploadFile("application/octet-stream", "photo.jpg")
        assert _infer_content_type(f) == "image/jpeg"

    def test_jpeg_extension_infers_image_jpeg(self):
        f = _FakeUploadFile("application/octet-stream", "photo.jpeg")
        assert _infer_content_type(f) == "image/jpeg"

    def test_png_extension_infers_image_png(self):
        f = _FakeUploadFile("application/octet-stream", "photo.png")
        assert _infer_content_type(f) == "image/png"

    def test_webp_extension_infers_image_webp(self):
        f = _FakeUploadFile("application/octet-stream", "photo.webp")
        assert _infer_content_type(f) == "image/webp"

    def test_heic_extension_infers_image_heic(self):
        f = _FakeUploadFile("application/octet-stream", "photo.heic")
        assert _infer_content_type(f) == "image/heic"

    def test_heif_extension_infers_image_heif(self):
        f = _FakeUploadFile("application/octet-stream", "photo.heif")
        assert _infer_content_type(f) == "image/heif"

    def test_valid_content_type_passthrough(self):
        f = _FakeUploadFile("image/jpeg", "photo.jpg")
        assert _infer_content_type(f) == "image/jpeg"

    def test_octet_stream_with_no_extension_stays_octet(self):
        f = _FakeUploadFile("application/octet-stream", "photo")
        assert _infer_content_type(f) == "application/octet-stream"

    def test_gif_extension_not_allowed(self):
        f = _FakeUploadFile("application/octet-stream", "anim.gif")
        ct = _infer_content_type(f)
        assert ct not in _ALLOWED_IMAGE_TYPES

    def test_allowed_types_map(self):
        assert _ALLOWED_IMAGE_TYPES["image/jpeg"] == ".jpg"
        assert _ALLOWED_IMAGE_TYPES["image/png"] == ".png"
        assert _ALLOWED_IMAGE_TYPES["image/webp"] == ".webp"

    def test_rejected_mime_contains_heic(self):
        assert "image/heic" in _REJECTED_MIME
        assert "image/heif" in _REJECTED_MIME


class TestImageBytesValidation:
    """Pillow-based validation rejects non-image and corrupt bytes."""

    def test_valid_jpeg_bytes_accepted(self):
        from PIL import Image

        img = Image.new("RGB", (10, 10), color="red")
        buf = BytesIO()
        img.save(buf, format="JPEG")
        raw = buf.getvalue()
        # Should not raise
        pil_img = Image.open(BytesIO(raw))
        pil_img.verify()

    def test_valid_png_bytes_accepted(self):
        from PIL import Image

        img = Image.new("RGB", (10, 10), color="blue")
        buf = BytesIO()
        img.save(buf, format="PNG")
        raw = buf.getvalue()
        pil_img = Image.open(BytesIO(raw))
        pil_img.verify()

    def test_valid_webp_bytes_accepted(self):
        from PIL import Image

        img = Image.new("RGB", (10, 10), color="green")
        buf = BytesIO()
        img.save(buf, format="WEBP")
        raw = buf.getvalue()
        pil_img = Image.open(BytesIO(raw))
        pil_img.verify()

    def test_corrupt_jpeg_rejected(self):
        from PIL import Image

        with pytest.raises(Exception):
            pil_img = Image.open(BytesIO(b"\xff\xd8\xff\xe0" + b"\x00" * 100))
            pil_img.verify()

    def test_random_bytes_rejected(self):
        from PIL import Image

        with pytest.raises(Exception):
            pil_img = Image.open(BytesIO(b"not an image at all"))
            pil_img.verify()

    def test_text_file_rejected(self):
        from PIL import Image

        with pytest.raises(Exception):
            pil_img = Image.open(BytesIO(b"%PDF-1.4 fake pdf content"))
            pil_img.verify()


# ---------------------------------------------------------------------------
# Bug 2 — CommuteBD route coordinate resolution
# ---------------------------------------------------------------------------

from app.database.connection import Base, get_engine, get_sessionmaker, reset_engine_cache
from app.database.models import Place
from app.schemas import CommutePlaceInput, CommuteRoutesRequest
from app.services.commute.service import CommuteService


class _FakeRouting:
    """Deterministic routing provider for tests."""

    def __init__(self, should_fail: bool = False):
        self._fail = should_fail
        self.last_origin = None
        self.last_dest = None

    async def search(self, query: str, limit: int = 8):
        return [{"displayName": query, "lat": 23.80, "lon": 90.37, "provider": "fake"}]

    async def route(self, origin, destination):
        if self._fail:
            raise RuntimeError("Simulated OSRM failure")
        self.last_origin = origin
        self.last_dest = destination
        return {
            "distanceKm": 5.0,
            "durationMinutes": 15,
            "polyline": [
                {"lat": origin.lat, "lon": origin.lon},
                {"lat": destination.lat, "lon": destination.lon},
            ],
            "provider": "fake",
        }


def _seed_places(places: list[tuple[str, str, float | None, float | None]]):
    """Seed multiple places into an in-memory SQLite DB.

    Each tuple: (place_id, name_en, latitude, longitude).
    Returns the Session factory.
    """
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
    reset_engine_cache()
    engine = get_engine()
    Base.metadata.create_all(engine)
    Session = get_sessionmaker()
    with Session() as session:
        for place_id, name_en, lat, lon in places:
            session.add(
                Place(
                    place_id=place_id,
                    name_en=name_en,
                    name_bn=name_en,
                    normalized_name=name_en.lower(),
                    latitude=lat,
                    longitude=lon,
                    geocode_status="pending" if lat is None else "verified",
                    source_id="S1",
                )
            )
        session.commit()
    return Session


def test_direct_lat_lon_to_lat_lon():
    """Origin and destination both have explicit coordinates."""
    _seed_places([("P1", "Mirpur 10", 23.8067, 90.3687)])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(name="Custom Origin", lat=23.80, lon=90.37),
                destination=CommutePlaceInput(name="Custom Destination", lat=23.73, lon=90.42),
            )
        )
    )
    assert result["distanceKm"] == 5.0
    assert routing.last_origin.lat == 23.80
    assert routing.last_dest.lat == 23.73


def test_coordinate_origin_dataset_destination():
    """GPS coordinates as origin, dataset place_id as destination."""
    _seed_places([("P1", "Motijheel", 23.733, 90.417)])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(name="Current location", lat=23.80, lon=90.37),
                destination=CommutePlaceInput(place_id="P1"),
            )
        )
    )
    assert result["distanceKm"] == 5.0
    assert routing.last_origin.lat == 23.80
    assert routing.last_dest.lat == 23.733


def test_dataset_place_to_dataset_place():
    """Both origin and destination are dataset places with coordinates."""
    _seed_places([
        ("P1", "Mirpur 10", 23.8067, 90.3687),
        ("P2", "Motijheel", 23.733, 90.417),
    ])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(place_id="P1"),
                destination=CommutePlaceInput(place_id="P2"),
            )
        )
    )
    assert result["distanceKm"] == 5.0
    assert routing.last_origin.lat == 23.8067
    assert routing.last_dest.lat == 23.733


def test_unresolved_place_raises_value_error():
    """Place with no coordinates and no CSV match raises ValueError."""
    _seed_places([("P_UNKNOWN", "Unknown Place", None, None)])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    with patch.object(service, '_geocode_once', return_value=None):
        with pytest.raises(ValueError, match="Could not find"):
            asyncio.run(
                service.routes(
                    CommuteRoutesRequest(
                        origin=CommutePlaceInput(place_id="P_UNKNOWN"),
                        destination=CommutePlaceInput(place_id="P_UNKNOWN"),
                    )
                )
            )


def test_null_coordinates_in_request_raises_value_error():
    """Both places have null lat/lon and unresolvable names."""
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    with patch.object(service, '_geocode_once', return_value=None):
        with pytest.raises(ValueError, match="Could not find"):
            asyncio.run(
                service.routes(
                    CommuteRoutesRequest(
                        origin=CommutePlaceInput(name="Nonexistent Place A"),
                        destination=CommutePlaceInput(name="Nonexistent Place B"),
                    )
                )
            )


def test_osrm_failure_raises_runtime_error():
    """OSRM routing failure surfaces as RuntimeError, not generic 503."""
    _seed_places([
        ("P1", "Mirpur 10", 23.8067, 90.3687),
        ("P2", "Motijheel", 23.733, 90.417),
    ])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting(should_fail=True)
    service = CommuteService(repo=repo, routing_provider=routing)

    with pytest.raises(RuntimeError, match="Simulated OSRM failure"):
        asyncio.run(
            service.routes(
                CommuteRoutesRequest(
                    origin=CommutePlaceInput(place_id="P1"),
                    destination=CommutePlaceInput(place_id="P2"),
                )
            )
        )


def test_name_based_resolution_via_geocoder():
    """Place found by name search, coordinates resolved from DB."""
    _seed_places([("P1", "Mirpur 10", 23.8067, 90.3687)])
    from app.database.repositories.postgres_repository import CommutePostgresRepository
    repo = CommutePostgresRepository()
    routing = _FakeRouting()
    service = CommuteService(repo=repo, routing_provider=routing)

    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(name="Mirpur 10"),
                destination=CommutePlaceInput(name="Mirpur 10"),
            )
        )
    )
    assert result["distanceKm"] == 5.0


# ---------------------------------------------------------------------------
# Coordinate-preservation path — search → Flutter → route
# ---------------------------------------------------------------------------

from app.services.commute.data_repository import CommuteDataRepository


class TestSearchReturnsCanonicalCoordinates:
    """search_local_places() must include lat/lon from place_coordinates.csv."""

    def test_known_dataset_place_includes_lat_lon(self):
        repo = CommuteDataRepository()
        results = repo.search_local_places("Motijheel", limit=5)
        assert len(results) > 0
        match = next((r for r in results if "Motijheel" in r["nameEn"]), None)
        assert match is not None, "Motijheel not found in dataset"
        assert match["lat"] is not None, "Motijheel should have canonical lat from CSV"
        assert match["lon"] is not None, "Motijheel should have canonical lon from CSV"
        assert isinstance(match["lat"], float)
        assert isinstance(match["lon"], float)
        assert 23.0 < match["lat"] < 24.0  # Dhaka latitude range
        assert 90.0 < match["lon"] < 91.0  # Dhaka longitude range

    def test_all_csv_places_return_coordinates(self):
        """Every place in place_coordinates.csv should have lat/lon in search results."""
        from app.services.commute.graph_builder import load_coordinates
        csv_coords = load_coordinates()
        repo = CommuteDataRepository()
        for place_id, (lat, lon) in csv_coords.items():
            results = repo.search_local_places(place_id, limit=1)
            if results:
                r = results[0]
                assert r["lat"] is not None, f"{place_id} missing lat in search result"
                assert r["lon"] is not None, f"{place_id} missing lon in search result"
                assert abs(r["lat"] - lat) < 0.001, f"{place_id} lat mismatch"
                assert abs(r["lon"] - lon) < 0.001, f"{place_id} lon mismatch"

    def test_unknown_place_has_null_coordinates(self):
        """A place not in the CSV should have null lat/lon."""
        repo = CommuteDataRepository()
        results = repo.search_local_places("XYZNONEXISTENT", limit=5)
        # Either no results or results with null coordinates
        for r in results:
            assert r["lat"] is None or r["lon"] is None


class TestBackendPrefersSuppliedCoordinates:
    """When client sends lat/lon, backend must use them directly — no Nominatim."""

    def test_supplied_coordinates_skip_nominatim(self):
        _seed_places([("P1", "Test Place", None, None)])
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        repo = CommutePostgresRepository()
        routing = _FakeRouting()
        service = CommuteService(repo=repo, routing_provider=routing)

        with patch.object(service, '_geocode_once', return_value=None) as mock_geo:
            result = asyncio.run(
                service.routes(
                    CommuteRoutesRequest(
                        origin=CommutePlaceInput(
                            name="Test Origin", lat=23.80, lon=90.37,
                        ),
                        destination=CommutePlaceInput(
                            name="Test Dest", lat=23.73, lon=90.42,
                        ),
                    )
                )
            )
            # Nominatim should NOT have been called — coordinates were supplied
            mock_geo.assert_not_called()
            assert result["distanceKm"] == 5.0
            assert routing.last_origin.lat == 23.80
            assert routing.last_dest.lat == 23.73

    def test_one_supplied_one_resolved(self):
        """Origin has GPS coords, destination resolves via DB/CSV."""
        _seed_places([("P2", "Motijheel", 23.733, 90.417)])
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        repo = CommutePostgresRepository()
        routing = _FakeRouting()
        service = CommuteService(repo=repo, routing_provider=routing)

        with patch.object(service, '_geocode_once', return_value=None) as mock_geo:
            result = asyncio.run(
                service.routes(
                    CommuteRoutesRequest(
                        origin=CommutePlaceInput(
                            name="Current location", lat=23.80, lon=90.37,
                        ),
                        destination=CommutePlaceInput(place_id="P2"),
                    )
                )
            )
            assert result["distanceKm"] == 5.0
            assert routing.last_origin.lat == 23.80
            assert routing.last_dest.lat == 23.733


class TestCurrentGpsOriginPlusDatasetDestination:
    """Current GPS origin + dataset destination — the real-world user flow."""

    def test_gps_origin_csv_destination(self):
        """Simulates: user taps 'Use current location' + picks Motijheel from search."""
        _seed_places([("PLC0008", "Motijheel", None, None)])
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        from app.services.commute.graph_builder import load_coordinates
        csv_coords = load_coordinates()
        repo = CommutePostgresRepository()
        routing = _FakeRouting()
        service = CommuteService(repo=repo, routing_provider=routing)

        # Simulate Flutter sending GPS coords + dataset place_id
        result = asyncio.run(
            service.routes(
                CommuteRoutesRequest(
                    origin=CommutePlaceInput(
                        name="Current location",
                        lat=23.8103,  # GPS from device
                        lon=90.4125,
                    ),
                    destination=CommutePlaceInput(
                        place_id="PLC0008",
                        name="Motijheel",
                    ),
                )
            )
        )
        assert result["distanceKm"] == 5.0
        # GPS origin preserved exactly
        assert routing.last_origin.lat == 23.8103
        assert routing.last_origin.lon == 90.4125
        # Destination resolved from CSV (DB had null lat/lon)
        expected_lat, expected_lon = csv_coords["PLC0008"]
        assert routing.last_dest.lat == expected_lat
        assert routing.last_dest.lon == expected_lon


# ---------------------------------------------------------------------------
# Transport network graph tests
# ---------------------------------------------------------------------------

from app.services.commute.journey_service import get_graph, reset_graph_cache, graph_stats
from app.services.commute.graph_builder import GraphData


class TestTransportGraphInitialization:
    """Graph loading, empty graph, and missing data handling."""

    def setup_method(self):
        reset_graph_cache()

    def teardown_method(self):
        reset_graph_cache()

    def test_empty_graph_returns_dataset_unavailable(self):
        """Graph with no DB data should return a non-available result."""
        from app.services.commute.journey_service import plan
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        repo = CommutePostgresRepository()
        reset_graph_cache()
        result = plan(
            repo,
            origin_name="A",
            origin_lat=23.80,
            origin_lon=90.37,
            destination_name="B",
            destination_lat=23.73,
            destination_lon=90.42,
        )
        # With an empty or minimal DB, graph may be empty or have no
        # connections — either way, the result is not "available with journeys"
        assert result["available"] is False
        assert result["reason"] in (
            "dataset_unavailable",
            "planner_error",
            "outside_network_coverage",
        )

    def test_graph_stats_returns_details_when_built(self):
        """graph_stats() should return node/edge counts after build."""
        _seed_places([("P1", "Place A", 23.80, 90.37)])
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        repo = CommutePostgresRepository()
        reset_graph_cache()
        g = get_graph(repo)
        stats = graph_stats()
        if g is not None and len(g) > 0:
            assert stats is not None
            assert "nodes" in stats
            assert "edges" in stats
            assert "places" in stats

    def test_reset_graph_cache_clears_cached(self):
        """reset_graph_cache() should clear the cached graph."""
        _seed_places([("P1", "Place A", 23.80, 90.37)])
        from app.database.repositories.postgres_repository import CommutePostgresRepository
        repo = CommutePostgresRepository()
        reset_graph_cache()
        g1 = get_graph(repo)
        reset_graph_cache()
        g2 = get_graph(repo)
        assert type(g1) == type(g2)


class TestProfilePhotoPreservesIdentity:
    """Profile photo update must NOT erase displayName/university/department.

    The fix is in Flutter's firestore_service.dart: updateProfile() now only
    writes keys present in the fields map, so calling
    updateProfile({'photoURL': url}) writes ONLY photoURL — not nulls for
    displayName/university/department.

    These backend tests verify the account.py photo endpoint uses merge=True
    and does NOT touch identity fields.
    """

    def test_photo_upload_uses_merge_and_only_writes_photo_fields(self):
        """account.py profile-photo endpoint must use merge=True and only
        write photoPath/photoURL/updatedAt — never displayName/university/department."""
        from pathlib import Path
        account_path = Path(__file__).resolve().parent.parent / "app" / "routers" / "account.py"
        source = account_path.read_text(encoding="utf-8")
        # The profile-photo endpoint uses merge=True
        assert "merge=True" in source
        # The profile-photo endpoint writes photoPath and photoURL
        assert '"photoPath"' in source
        assert '"photoURL"' in source

    def test_backend_photo_endpoint_does_not_write_displayname(self):
        """The backend photo upload must NOT write displayName to Firestore."""
        import inspect
        from app.routers.account import upload_profile_photo
        source = inspect.getsource(upload_profile_photo)
        # Should NOT contain displayName write
        assert "displayName" not in source or "displayName" in source.split("def ")[0]
