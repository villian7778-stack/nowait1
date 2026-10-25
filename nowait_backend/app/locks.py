import threading

# One lock per key, so work on the same thing (a shop's activations, an owner's new orders, an
# owner creating their shop) runs one request at a time even when requests arrive together: a
# double tap, a retry after a slow-network timeout, or the app's verify racing Razorpay's webhook.
# In-process is enough because the Dockerfile runs a single uvicorn worker; database constraints
# back it up where it matters.
_locks: dict[str, threading.Lock] = {}
_guard = threading.Lock()


def lock_for(key: str) -> threading.Lock:
    with _guard:
        return _locks.setdefault(key, threading.Lock())
