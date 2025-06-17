#!/bin/sh
set -e

# 1) Espera a que Ollama esté listo
until curl -s http://ollama:11434/api/tags > /dev/null 2>&1; do
  echo "⏳ Esperando a Ollama..."
  sleep 3
done

echo "✅ Ollama disponible – iniciando LogWhisperer"

# 2) Ejecuta LogWhisperer en modo seguimiento (cada 3600s)
exec python3 logwhisperer.py \
  --source docker \
  --container moodle-app \
  --follow \
  --interval 3600 \
  --model phi3:mini \
  --ollama-host http://ollama:11434