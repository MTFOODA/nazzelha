FROM node:24-bookworm-slim AS node
FROM python:3.11-slim-bookworm
ENV PYTHONUNBUFFERED=1 PYTHONUTF8=1 NAZZELHA_PUBLIC_SERVER=1 \
    NAZZELHA_STORAGE=/tmp/nazzelha NAZZELHA_MAX_FILE_BYTES=268435456
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
WORKDIR /app
COPY python_backend/requirements-server.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY python_backend/*.py ./
RUN useradd --create-home --uid 10001 nazzelha
USER nazzelha
EXPOSE 8000
CMD ["python", "public_api.py"]
