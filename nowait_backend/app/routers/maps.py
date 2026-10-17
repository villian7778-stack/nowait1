"""Google Maps proxy for the owner's shop-location picker.

Every call here is billed to our GOOGLE_MAP_KEY, so the endpoints are only for signed-in shop
owners (the only users of the map picker), are rate-limited per owner, and send Google a fixed
set of fields/types - the caller cannot ask for more expensive data.
"""
import re

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from app.config import settings
from app.dependencies import get_current_owner
from app.rate_limit import per_owner_limit

router = APIRouter(prefix="/maps", tags=["Maps"])

_GOOGLE_BASE = "https://maps.googleapis.com/maps/api"
_LATLNG = re.compile(r"^\s*(-?\d{1,2}(?:\.\d{1,10})?)\s*,\s*(-?\d{1,3}(?:\.\d{1,10})?)\s*$")
_PLACE_ID = re.compile(r"^[A-Za-z0-9_-]{10,300}$")
_ALLOWED_TYPES = {"geocode", "establishment", "address", "(cities)", "(regions)", "establishment|geocode"}
_DETAIL_FIELDS = "geometry,formatted_address"  # the only fields the app uses (and the cheapest)

_owner_only = [Depends(get_current_owner), Depends(per_owner_limit("maps", 60))]


def _require_key() -> str:
    if not settings.GOOGLE_MAP_KEY:
        raise HTTPException(status_code=503, detail="Maps API not configured")
    return settings.GOOGLE_MAP_KEY


@router.get("/geocode", dependencies=_owner_only)
async def reverse_geocode(latlng: str = Query(..., max_length=60, description="lat,lng e.g. 18.5204,73.8567")):
    """Reverse-geocode a lat/lng pair to a human-readable address."""
    m = _LATLNG.match(latlng)
    if not m or abs(float(m.group(1))) > 90 or abs(float(m.group(2))) > 180:
        raise HTTPException(status_code=422, detail="latlng must look like 20.70,77.00")
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/geocode/json",
            params={"latlng": f"{m.group(1)},{m.group(2)}", "key": key},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Geocoding request failed")
    return resp.json()


@router.get("/places/autocomplete", dependencies=_owner_only)
async def places_autocomplete(
    input: str = Query(..., min_length=2, max_length=100),
    components: str = Query(default="country:in"),
    types: str = Query(default="geocode"),
):
    """Google Places Autocomplete — returns predictions for the search query (India only)."""
    if not re.fullmatch(r"country:[a-zA-Z]{2}", components):
        components = "country:in"
    if types not in _ALLOWED_TYPES:
        types = "geocode"
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/place/autocomplete/json",
            params={"input": input, "key": key, "components": components, "types": types},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Places autocomplete request failed")
    return resp.json()


@router.get("/place/details", dependencies=_owner_only)
async def place_details(place_id: str = Query(..., max_length=300)):
    """Google Place Details — returns lat/lng and address for a place_id. Any `fields` the caller
    sends are ignored: only location and address are ever requested (billing)."""
    if not _PLACE_ID.match(place_id):
        raise HTTPException(status_code=422, detail="Invalid place_id")
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/place/details/json",
            params={"place_id": place_id, "fields": _DETAIL_FIELDS, "key": key},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Place details request failed")
    return resp.json()
