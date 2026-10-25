from fastapi import HTTPException

from app.database import execute_one, supabase
from app.locks import lock_for


def _is_owner(shop_id: str, user_id: str) -> bool:
    r = execute_one(supabase.table("shops").select("id").eq("id", shop_id).eq("owner_id", user_id))
    return r.data is not None


def get_staff_public(shop_id: str) -> list:
    """Return active staff for a shop — visible to all authenticated users (customer info view)."""
    result = (
        supabase.table("staff_members")
        .select("id, user_id, display_name, is_owner_staff")
        .eq("shop_id", shop_id)
        .eq("is_active", True)
        .order("created_at")
        .execute()
    )
    return result.data or []


def get_staff(shop_id: str, owner_id: str) -> list:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    result = (
        supabase.table("staff_members")
        .select("*")
        .eq("shop_id", shop_id)
        .eq("is_active", True)
        .order("created_at")
        .execute()
    )
    members = result.data or []

    # Enrich with profile phone where available
    enriched = []
    for m in members:
        phone = ""
        if m.get("user_id"):
            profile = execute_one(supabase.table("profiles").select("phone").eq("id", m["user_id"]))
            phone = profile.data["phone"] if profile.data else ""
        enriched.append({**m, "phone": phone})
    return enriched


def add_staff(shop_id: str, owner_id: str, phone: str) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    user = execute_one(supabase.table("profiles").select("id, name, phone").eq("phone", phone))
    if not user.data:
        user = execute_one(supabase.table("profiles").select("id, name, phone").eq("phone", f"+91{phone}"))
    if not user.data:
        raise HTTPException(status_code=404, detail="No user found with that phone number. They must register first.")

    user_id = user.data["id"]
    if user_id == owner_id:
        raise HTTPException(status_code=400, detail="Use self-register endpoint to add yourself as staff")

    existing = execute_one(
        supabase.table("staff_members")
        .select("id, is_active")
        .eq("shop_id", shop_id)
        .eq("user_id", user_id)
    )
    if existing.data:
        if existing.data["is_active"]:
            raise HTTPException(status_code=409, detail="User is already a staff member")
        supabase.table("staff_members").update({"is_active": True}).eq("id", existing.data["id"]).execute()
        r = execute_one(supabase.table("staff_members").select("*").eq("id", existing.data["id"]))
        return {**(r.data or {}), "display_name": user.data["name"], "phone": user.data["phone"]}

    result = supabase.table("staff_members").insert({
        "shop_id": shop_id,
        "user_id": user_id,
        "added_by": owner_id,
        "display_name": user.data["name"],
        "is_owner_staff": False,
        "is_active": True,
    }).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to add staff")

    return {**result.data[0], "display_name": user.data["name"], "phone": user.data["phone"]}


def add_staff_by_name(shop_id: str, owner_id: str, display_name: str) -> dict:
    """Add a staff member by display name only — no app account required."""
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    if not display_name.strip():
        raise HTTPException(status_code=400, detail="Staff name is required")

    # Same name twice is almost always a double tap or a retry on a slow connection.
    with lock_for(f"staff:{shop_id}"):
        same = (
            supabase.table("staff_members")
            .select("id")
            .eq("shop_id", shop_id)
            .eq("is_active", True)
            .ilike("display_name", display_name.strip().replace("%", r"\%").replace("_", r"\_"))
            .limit(1)
            .execute()
        ).data
        if same:
            raise HTTPException(status_code=409, detail="A staff member with this name already exists.")

        result = supabase.table("staff_members").insert({
            "shop_id": shop_id,
            "user_id": None,
            "added_by": owner_id,
            "display_name": display_name.strip(),
            "is_owner_staff": False,
            "is_active": True,
        }).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to add staff")

    return {**result.data[0], "phone": ""}


def remove_staff(shop_id: str, owner_id: str, staff_id: str) -> dict:
    """Remove staff by staff_members.id (not user_id, since name-only staff have no user_id)."""
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    existing = execute_one(
        supabase.table("staff_members")
        .select("id, is_owner_staff")
        .eq("shop_id", shop_id)
        .eq("id", staff_id)
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Staff member not found")
    if existing.data.get("is_owner_staff"):
        raise HTTPException(status_code=400, detail="Cannot remove yourself (owner-staff)")

    supabase.table("staff_members").update({"is_active": False}).eq("id", existing.data["id"]).execute()
    return {"message": "Staff member removed", "id": staff_id}


def self_register_as_staff(owner_id: str) -> dict:
    """Owner registers themselves as a visible staff member of their own shop."""
    shop = execute_one(supabase.table("shops").select("id, name").eq("owner_id", owner_id))
    if not shop.data:
        raise HTTPException(status_code=404, detail="You don't have a shop yet")

    shop_id = shop.data["id"]
    profile = execute_one(supabase.table("profiles").select("name").eq("id", owner_id))
    display_name = profile.data["name"] if profile.data else "Owner"

    existing = execute_one(
        supabase.table("staff_members")
        .select("id, is_active")
        .eq("shop_id", shop_id)
        .eq("user_id", owner_id)
    )
    if existing.data:
        if existing.data["is_active"]:
            return {"message": "Already registered as staff", "shop_id": shop_id}
        supabase.table("staff_members").update({"is_active": True}).eq("id", existing.data["id"]).execute()
        return {"message": "Re-activated as staff", "shop_id": shop_id}

    supabase.table("staff_members").insert({
        "shop_id": shop_id,
        "user_id": owner_id,
        "added_by": owner_id,
        "display_name": display_name,
        "is_owner_staff": True,
        "is_active": True,
    }).execute()

    return {"message": "Registered as staff", "shop_id": shop_id, "display_name": display_name}


def get_my_staff_assignments(user_id: str) -> list:
    result = (
        supabase.table("staff_members")
        .select("*, shops(id, name, city, category, is_open)")
        .eq("user_id", user_id)
        .eq("is_active", True)
        .execute()
    )
    return result.data or []
