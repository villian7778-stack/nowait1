import logging

import httpx
from postgrest._sync.client import SyncPostgrestClient
from postgrest.exceptions import APIError
from postgrest.utils import SyncClient
from supabase import Client, create_client

from app.config import settings

logger = logging.getLogger(__name__)


class _RetryingTransport(httpx.HTTPTransport):
    """Supabase drops idle keep-alive connections; the next request on one fails with
    "Server disconnected" before the server ever processes it. Retry those on a fresh
    connection instead of failing the request (this was breaking payment verify, which
    runs after the owner has spent a minute in the Razorpay checkout)."""

    _RETRYABLE = (httpx.RemoteProtocolError, httpx.ReadError, httpx.WriteError, httpx.ConnectError)

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        for attempt in range(3):
            try:
                return super().handle_request(request)
            except self._RETRYABLE as e:
                if attempt == 2:
                    raise
                logger.warning("Supabase connection dropped (%s: %s) on %s %s — retrying",
                               type(e).__name__, e, request.method, request.url.path)
        raise RuntimeError("unreachable")


def _create_session(self, base_url, headers, timeout, verify=True, proxy=None) -> SyncClient:
    # HTTP/1.1 instead of the library's HTTP/2: one dead HTTP/2 connection fails every
    # request multiplexed on it, and idle HTTP/2 connections are what Supabase keeps closing.
    return SyncClient(
        base_url=base_url,
        headers=headers,
        timeout=timeout,
        follow_redirects=True,
        transport=_RetryingTransport(verify=verify, proxy=proxy),
    )


# Patched on the class (not the instance) because supabase-py rebuilds its postgrest client
# on auth events, which would silently drop an instance-level fix.
SyncPostgrestClient.create_session = _create_session

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
