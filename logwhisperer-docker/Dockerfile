FROM python:3.11-slim

# Instalar dependencias del sistema
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      docker.io \
      curl \
      jq \
 && rm -rf /var/lib/apt/lists/*

# Clonar LogWhisperer y instalar dependencias
RUN git clone --depth 1 https://github.com/binary-knight/logwhisperer /opt/logwhisperer \
 && pip install --no-cache-dir -r /opt/logwhisperer/requirements.txt

# Copiar script de entrada mejorado
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Crear directorio para reportes
RUN mkdir -p /reports

WORKDIR /opt/logwhisperer

# Variables de entorno por defecto
ENV OLLAMA_HOST=http://ollama:11434
ENV LOG_LEVEL=INFO

ENTRYPOINT ["/entrypoint.sh"]