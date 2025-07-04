#!/usr/bin/env bash
set -e

echo "🚀 Iniciando LogInsights..."

: "${OLLAMA_HOST:=http://ollama:11434}"
: "${MODEL:=tinyllama:1.1b}"
: "${CONTAINER_NAMES:=moodle-app}"
: "${INTERVAL:=120}"
: "${ANALYSIS_TIMEOUT:=90}"

MAX_RETRIES=30
COUNT=0

# ---------- Funciones auxiliares ----------
check_ollama() { curl -s -f "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; }

model_exists() {
  local name="$1"
  curl -s "${OLLAMA_HOST}/api/tags" | jq -r '.models[].name' | grep -q "^${name}$"
}

pull_model() {
  local name="$1"
  echo "📦 Descargando modelo ${name}..."
  curl -s -X POST "${OLLAMA_HOST}/api/pull" \
       -H "Content-Type: application/json" \
       -d "{\"name\":\"${name}\"}" | while read -r line; do
    echo "$line" | jq -r '.status // empty' 2>/dev/null || echo "$line"
  done
}

ensure_model() {
  local name="$1"
  if ! model_exists "$name"; then
    pull_model "$name"
    sleep 5
    if ! model_exists "$name"; then
      echo "❌ Falló la descarga de $name"
      return 1
    fi
  fi
  echo "✅ Modelo ${name} listo"
}

check_docker_daemon() {
python3 - <<'PY'
import sys, docker
try:
    client = docker.DockerClient(base_url='unix:///var/run/docker.sock')
    client.ping()
    print("✅ Docker accesible desde el contenedor")
except Exception as e:
    print(f"❌ No se pudo acceder al daemon de Docker: {e}")
    sys.exit(1)
PY
}

# ---------- 1) Esperar Ollama ----------
echo "⏳ Esperando a Ollama..."
until check_ollama || [ "$COUNT" -eq "$MAX_RETRIES" ]; do
  COUNT=$((COUNT+1))
  echo "  → Intento ${COUNT}/${MAX_RETRIES}"
  sleep 3
done
[ "$COUNT" -eq "$MAX_RETRIES" ] && { echo "❌ Ollama no responde"; exit 1; }

# ---------- 2) Asegurar modelo ----------
ensure_model "$MODEL" || { echo "⚠️  Probando con llama3.2:1b"; MODEL="llama3.2:1b"; ensure_model "$MODEL" || exit 1; }

# ---------- 3) Verificar acceso a Docker ----------
check_docker_daemon

# ---------- 4) Ejecutar LogInsights ----------
echo "✅ Configuración terminada, arrancando LogInsights..."
exec python3 /loginsights.py
