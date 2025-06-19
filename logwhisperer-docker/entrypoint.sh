#!/usr/bin/env bash
set -e

echo "🚀 Iniciando LogWhisperer..."

: "${OLLAMA_HOST:=http://ollama:11434}"
: "${MODEL:=phi3:mini}"
: "${CONTAINER_NAMES:=moodle-app}"
: "${INTERVAL:=60}"

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
       -d "{\"name\":\"${name}\"}"
}

ensure_model() {
  local name="$1"
  if ! model_exists "$name"; then
    pull_model "$name"
    sleep 5
    model_exists "$name" || { echo "❌ Falló la descarga de $name"; return 1; }
  fi
  echo "✅ Modelo ${name} listo"
}

check_docker_daemon() {
python3 - <<'PY'
import sys, docker, os
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

# ---------- 4) Generar wrapper dinámico ----------
cat >/run_logwhisperer.py <<'PY'
#!/usr/bin/env python3
import os, time, subprocess, docker
from datetime import datetime

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
MODEL        = os.getenv("MODEL", "phi3:mini")
INTERVAL     = int(os.getenv("INTERVAL", "60"))
CONTAINERS   = [c.strip() for c in os.getenv("CONTAINER_NAMES","moodle-app").split(",")]

client = docker.DockerClient(base_url="unix:///var/run/docker.sock")

def running(container_name):
    try:
        return client.containers.get(container_name).status == "running"
    except docker.errors.NotFound:
        return False

def analyse(container_name):
    cmd = [
        "python3", "/opt/logwhisperer/logwhisperer.py",
        "--source", "docker",
        "--container", container_name,
        "--model", MODEL,
        "--ollama-host", OLLAMA_HOST,
        "--entries", "100",
        "--timeout", "30",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    outfile = f"/reports/summary_{container_name}_{ts}.txt"
    with open(outfile, "w") as f:
        f.write(result.stdout)
        if result.stderr:
            f.write("\n--- STDERR ---\n")
            f.write(result.stderr)
    print(f"📝 {outfile} generado")

def main():
    print(f"🎯 Monitoreando contenedores: {', '.join(CONTAINERS)} cada {INTERVAL}s")
    while True:
        for name in CONTAINERS:
            if running(name):
                print(f"📊 Analizando {name} ...")
                analyse(name)
            else:
                print(f"⚠️  {name} no está en ejecución")
        print(f"💤 Esperando {INTERVAL}s…")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
PY

chmod +x /run_logwhisperer.py

echo "✅ Configuración terminada, arrancando LogWhisperer..."
exec python3 /run_logwhisperer.py
