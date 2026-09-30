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
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
