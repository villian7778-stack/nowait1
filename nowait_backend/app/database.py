from postgrest.exceptions import APIError
from supabase import Client, create_client

from app.config import settings

# Admin client uses service_role key — bypasses RLS, for server-side operations
supabase: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


class _OneResult:
    __slots__ = ("data",)

    def __init__(self, data):
        self.data = data


def execute_one(query) -> _OneResult:
    """Execute a query returning 0 or 1 rows.

    supabase-py 2.9+ may either return None or raise APIError(code=204) when no row
    is found. This wrapper normalises both cases so callers can always do result.data.
    """
    try:
        result = query.maybe_single().execute()
        return result if result is not None else _OneResult(None)
    except APIError as e:
        if str(e.code) == "204":
            return _OneResult(None)
        raise
