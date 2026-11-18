import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor

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
    # Keep idle connections for up to 60 s instead of httpx's 5 s: a new connection to Supabase
    # (Singapore) costs a TLS handshake, about 0.2 s. keep_warm() below stops them going idle.
    return SyncClient(
        base_url=base_url,
        headers=headers,
        timeout=timeout,
        follow_redirects=True,
        transport=_RetryingTransport(
            verify=verify, proxy=proxy,
            limits=httpx.Limits(max_connections=100, max_keepalive_connections=20, keepalive_expiry=60),
        ),
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


# ── speed: independent queries at the same time ───────────────────────────────

# Every query is a round trip to Supabase (about 0.07-0.1 s from Mumbai). A screen's independent
# queries run side by side here, so it waits for the slowest one instead of the sum. Only plain
# queries run in this pool - never something that itself calls run_parallel (that could wait on
# its own pool). The HTTP client is shared and thread-safe.
_db_pool = ThreadPoolExecutor(max_workers=24, thread_name_prefix="db")


def run_parallel(*calls):
    """Run the given no-argument functions at the same time; returns their results in order.
    An exception from any of them is raised here, like running them one after another."""
    if len(calls) <= 1:
        return [c() for c in calls]
    futures = [_db_pool.submit(c) for c in calls]
    return [f.result() for f in futures]


# ── speed: keep the connections to Supabase warm ──────────────────────────────

KEEP_WARM_SECONDS = 20
KEEP_WARM_CONNECTIONS = 6  # about as many as one screen's parallel queries use
_warm_started = False


def _ping() -> None:
    supabase.table("shops").select("id").limit(1).execute()


def keep_warm_once() -> None:
    """A few tiny queries at once, so that many pooled connections stay open and in use (the
    first request after a quiet minute used to take ~1.6 s reconnecting). Never raises."""
    try:
        run_parallel(*([_ping] * KEEP_WARM_CONNECTIONS))
    except Exception as e:
        logger.info("Supabase keep-warm ping failed (%s) - next one in %ss", type(e).__name__, KEEP_WARM_SECONDS)


def start_keep_warm() -> None:
    """Background thread, started once when the server starts (main.py)."""
    global _warm_started
    if _warm_started:
        return
    _warm_started = True

    def loop():
        while True:
            keep_warm_once()
            time.sleep(KEEP_WARM_SECONDS)

    threading.Thread(target=loop, name="supabase-keep-warm", daemon=True).start()
