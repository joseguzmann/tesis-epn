#!/usr/bin/env python3
"""
LogInsights - Sistema de análisis inteligente de logs con LLM
- Recolecta logs de contenedores Docker
- Analiza con modelos de lenguaje usando Ollama
- Genera reportes estructurados en /reports
"""
import os
import time
from datetime import datetime
from pathlib import Path

import docker
import requests

# ─────────────────────────  Configuración  ──────────────────────────
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
MODEL        = os.getenv("MODEL", "phi3:mini")
INTERVAL     = int(os.getenv("INTERVAL", "120"))
ANAL_TIMEOUT = int(os.getenv("ANALYSIS_TIMEOUT", "180"))
CONTAINERS   = [c.strip() for c in os.getenv("CONTAINER_NAMES", "moodle-app").split(",")]
LOG_LEVEL    = os.getenv("LOG_LEVEL", "INFO")

# ─────────────────────────  Cliente Docker  ─────────────────────────
try:
    docker_client = docker.DockerClient(base_url="unix:///var/run/docker.sock")
    docker_client.ping()
except Exception as exc:
    print(f"❌ Error conectando a Docker: {exc}")
    exit(1)


# ────────────────────────  Funciones auxiliares ─────────────────────
def get_container_status(name: str) -> str:
    try:
        return docker_client.containers.get(name).status
    except docker.errors.NotFound:
        return "not_found"
    except Exception as exc:
        print(f"⚠️  Estado de {name}: {exc}")
        return "error"


def get_recent_logs(name: str, lines: int = 100) -> str:
    try:
        cont = docker_client.containers.get(name)
        return cont.logs(tail=lines, timestamps=True).decode("utf-8")
    except Exception as exc:
        return f"Error obteniendo logs: {exc}"


def analyze_with_ollama(text: str, container: str) -> str:
    """
    Llama a /api/generate de Ollama para análisis inteligente de logs
    """
    prompt = f"""Analiza los siguientes logs del contenedor **{container}** y genera un resumen:

1. Mensajes más relevantes
2. Errores o advertencias críticas
3. Estado general del servicio
4. Acciones recomendadas

Responde en español de forma breve y estructurada.

Logs:
{text[:4000]}"""  # se limita para no saturar al modelo

    try:
        resp = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={
                "model": MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.4,
                    "num_predict": 512
                },
            },
            timeout=ANAL_TIMEOUT,
        )
        if resp.status_code == 200:
            return resp.json().get("response", "Respuesta vacía")
        return f"Error {resp.status_code}: {resp.text}"
    except requests.exceptions.Timeout:
        return "⏱️ Timeout alcanzado durante la llamada a Ollama"
    except Exception as exc:
        return f"❌ Error llamando a Ollama: {exc}"


def save_report(container: str, analysis: str, logs: str) -> None:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = Path(f"/reports/summary_{container}_{ts}.txt")
    with path.open("w") as f:
        f.write(f"=== LogInsights - Análisis de logs para {container} ===\n")
        f.write(f"Timestamp: {datetime.now().isoformat()}\n")
        f.write(f"Estado del contenedor: {get_container_status(container)}\n")
        f.write(f"Modelo usado: {MODEL}\n")
        f.write("=" * 50 + "\n\n")

        f.write("=== ANÁLISIS ===\n")
        f.write(analysis + "\n\n")

        f.write("=== LOGS ORIGINALES (últimas 50 líneas) ===\n")
        for line in logs.splitlines()[-50:]:
            f.write(line + "\n")
    print(f"✅ Reporte guardado: {path}")


def list_last_reports() -> None:
    rep_dir = Path("/reports")
    if not rep_dir.exists():
        return
    reports = sorted(rep_dir.glob("summary_*.txt"))[-10:]
    if reports:
        print("\n📁 Últimos reportes:")
        for rep in reports:
            print(f"  • {rep.name} ({rep.stat().st_size/1024:.1f} KB)")


# ─────────────────────────────  Main loop  ──────────────────────────
if __name__ == "__main__":
    print("🎯 LogInsights - Sistema de análisis inteligente de logs")
    print(f"   Contenedores: {', '.join(CONTAINERS)}")
    print(f"   Modelo: {MODEL} / Timeout por request: {ANAL_TIMEOUT}s\n")

    Path("/reports").mkdir(exist_ok=True)

    # Pequeña espera inicial
    time.sleep(10)

    while True:
        print(f"\n🕐 {datetime.now():%Y-%m-%d %H:%M:%S} → nuevo ciclo")
        for cont in CONTAINERS:
            if get_container_status(cont) == "running":
                logs = get_recent_logs(cont, 100)
                result = analyze_with_ollama(logs, cont)
                save_report(cont, result, logs)
            else:
                print(f"⚠️  {cont} no está en estado running")

        list_last_reports()
        print(f"\n💤 Esperando {INTERVAL}s…")
        time.sleep(INTERVAL)
