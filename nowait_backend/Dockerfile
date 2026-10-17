FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# --proxy-headers/--forwarded-allow-ips: Render terminates TLS in a proxy, so the real
# client IP arrives in X-Forwarded-For. Without this every user shares one IP and the
# per-IP rate limits (login, register, ...) apply to all users combined.
# Single worker on purpose: Render free tier has ~0.1 CPU / 512 MB, and the admin
# panel keeps its sessions in process memory.
# PORT: most hosts (Render, Railway, Fly...) set it; defaults to 8000.
# FORWARDED_ALLOW_IPS: "*" is right behind a managed platform proxy (Render). On your own server
# behind nginx/Caddy set it to the proxy's address (e.g. 127.0.0.1) so clients cannot fake their IP.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips=${FORWARDED_ALLOW_IPS:-*}"]
