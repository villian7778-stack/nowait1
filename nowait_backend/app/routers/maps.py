import httpx
from fastapi import APIRouter, HTTPException, Query

from app.config import settings

router = APIRouter(prefix="/maps", tags=["Maps"])

_GOOGLE_BASE = "https://maps.googleapis.com/maps/api"


def _require_key() -> str:
    if not settings.GOOGLE_MAP_KEY:
        raise HTTPException(status_code=503, detail="Maps API not configured")
    return settings.GOOGLE_MAP_KEY


@router.get("/geocode")
async def reverse_geocode(latlng: str = Query(..., description="lat,lng e.g. 18.5204,73.8567")):
    """Reverse-geocode a lat/lng pair to a human-readable address."""
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/geocode/json",
            params={"latlng": latlng, "key": key},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Geocoding request failed")
    return resp.json()


@router.get("/places/autocomplete")
async def places_autocomplete(
    input: str = Query(..., min_length=2),
    components: str = Query(default="country:in"),
    types: str = Query(default="establishment|geocode"),
):
    """Google Places Autocomplete — returns predictions for the search query."""
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/place/autocomplete/json",
            params={"input": input, "key": key, "components": components, "types": types},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Places autocomplete request failed")
    return resp.json()


@router.get("/place/details")
async def place_details(
    place_id: str = Query(...),
    fields: str = Query(default="geometry,formatted_address"),
):
    """Google Place Details — returns lat/lng and address for a place_id."""
    key = _require_key()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{_GOOGLE_BASE}/place/details/json",
            params={"place_id": place_id, "fields": fields, "key": key},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Place details request failed")
    return resp.json()
