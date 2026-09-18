# Server antrian (main.py) untuk VM. Cuma server-nya: listener tetap di
# laptop, karena TikFinity Desktop cuma bisa dibaca dari mesin yang sama.
#
# Dependency ditulis di sini, bukan dari requirements.txt: file itu juga
# memuat TikTokLive dan lupa (listener dan tes), yang tidak dipakai server
# dan cuma memperbesar image.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

RUN pip install --no-cache-dir "fastapi>=0.110" "uvicorn>=0.27" "httpx>=0.27" "python-dotenv>=1.0.0"

COPY main.py roblox_ssl.py ./

EXPOSE 8000
# Satu worker, sengaja: antriannya ada di memori proses. Dua worker berarti
# dua antrian terpisah, dan Roblox mengambil dari yang mana saja.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
