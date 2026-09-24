from slowapi import Limiter
from slowapi.util import get_remote_address

# Shared limiter instance — imported by main.py (to register the handler) and by
# any router that needs to rate-limit a specific endpoint (auth, admin login).
limiter = Limiter(key_func=get_remote_address)
