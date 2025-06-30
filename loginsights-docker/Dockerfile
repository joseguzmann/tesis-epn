FROM python:3.11-slim

# 1) Dependencias básicas + docker CLI
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl \
    jq \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# 2) Instalar dependencias de Python
RUN pip install --no-cache-dir \
    docker \
    requests \
    pyyaml \
    rich

# 3) Copiar scripts
COPY entrypoint.sh /entrypoint.sh
COPY loginsights.py /loginsights.py
RUN chmod +x /entrypoint.sh

# 4) Directorio de reportes
RUN mkdir -p /reports

ENV PYTHONUNBUFFERED=1
ENV OLLAMA_HOST=http://ollama:11434
ENV LOG_LEVEL=INFO

WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
