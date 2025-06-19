FROM python:3.11-slim

# 1) Dependencias básicas
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      curl \
      jq  \
 && rm -rf /var/lib/apt/lists/*

# 2) Clonar proyecto LogWhisperer
RUN git clone --depth 1 https://github.com/binary-knight/logwhisperer /opt/logwhisperer

# 3) Instalar dependencias de Python
RUN pip install --no-cache-dir \
      ollama \
      docker \
      requests \
      pyyaml \
      rich

# 4) Copiar y dar permisos al entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 5) Crear directorio para los reportes
RUN mkdir -p /reports

WORKDIR /opt/logwhisperer

ENV PYTHONUNBUFFERED=1
ENV OLLAMA_HOST=http://ollama:11434
ENV LOG_LEVEL=INFO

ENTRYPOINT ["/entrypoint.sh"]
