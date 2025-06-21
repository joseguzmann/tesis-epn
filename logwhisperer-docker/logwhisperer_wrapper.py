#!/usr/bin/env python3
import os
import time
import subprocess
import docker
import json
from datetime import datetime
from pathlib import Path

# Configuración
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
MODEL = os.getenv("MODEL", "phi3:mini")
INTERVAL = int(os.getenv("INTERVAL", "120"))
ANALYSIS_TIMEOUT = int(os.getenv("ANALYSIS_TIMEOUT", "90"))
CONTAINERS = [c.strip() for c in os.getenv("CONTAINER_NAMES", "moodle-app").split(",")]
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Cliente Docker
try:
    client = docker.DockerClient(base_url="unix:///var/run/docker.sock")
except Exception as e:
    print(f"❌ Error conectando a Docker: {e}")
    exit(1)

def get_container_status(container_name):
    """Obtiene el estado de un contenedor"""
    try:
        container = client.containers.get(container_name)
        return container.status
    except docker.errors.NotFound:
        return "not_found"
    except Exception as e:
        print(f"⚠️  Error obteniendo estado de {container_name}: {e}")
        return "error"

def get_recent_logs(container_name, lines=100):
    """Obtiene los logs recientes de un contenedor"""
    try:
        container = client.containers.get(container_name)
        logs = container.logs(tail=lines, timestamps=True).decode('utf-8')
        return logs
    except Exception as e:
        return f"Error obteniendo logs: {e}"

def analyze_logs(container_name):
    """Analiza los logs de un contenedor"""
    print(f"📊 Analizando {container_name}...")
    
    # Primero obtenemos los logs
    logs = get_recent_logs(container_name)
    
    # Creamos archivo temporal con los logs
    temp_log_file = f"/tmp/{container_name}_logs.txt"
    with open(temp_log_file, 'w') as f:
        f.write(logs)
    
    # Ejecutamos LogWhisperer
    cmd = [
        "python3", "/opt/logwhisperer/logwhisperer.py",
        "--source", "file",
        "--file", temp_log_file,
        "--model", MODEL,
        "--ollama-host", OLLAMA_HOST,
        "--entries", "100",
        "--timeout", str(ANALYSIS_TIMEOUT),
        "--output-dir", "/reports"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=ANALYSIS_TIMEOUT + 10)
        
        # Generamos nombre de archivo para el reporte
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_file = f"/reports/summary_{container_name}_{timestamp}.txt"
        
        # Guardamos el resultado
        with open(report_file, 'w') as f:
            f.write(f"=== Análisis de logs para {container_name} ===\n")
            f.write(f"Timestamp: {datetime.now().isoformat()}\n")
            f.write(f"Estado del contenedor: {get_container_status(container_name)}\n")
            f.write(f"Modelo usado: {MODEL}\n")
            f.write("=" * 50 + "\n\n")
            
            if result.stdout:
                f.write("=== ANÁLISIS ===\n")
                f.write(result.stdout)
                f.write("\n\n")
            
            if result.stderr:
                f.write("=== ERRORES ===\n")
                f.write(result.stderr)
                f.write("\n\n")
            
            f.write("=== LOGS ORIGINALES (últimas 50 líneas) ===\n")
            f.write("\n".join(logs.split("\n")[-50:]))
        
        print(f"✅ Reporte guardado: {report_file}")
        
        # Limpiamos archivo temporal
        os.remove(temp_log_file)
        
    except subprocess.TimeoutExpired:
        print(f"⏱️  Timeout analizando {container_name}")
        # Guardamos logs sin análisis
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_file = f"/reports/summary_{container_name}_{timestamp}_timeout.txt"
        with open(report_file, 'w') as f:
            f.write(f"=== Logs de {container_name} (sin análisis - timeout) ===\n")
            f.write(f"Timestamp: {datetime.now().isoformat()}\n\n")
            f.write(logs)
        print(f"📝 Logs guardados sin análisis: {report_file}")
    except Exception as e:
        print(f"❌ Error analizando {container_name}: {e}")

def list_reports():
    """Lista los reportes generados"""
    reports_dir = Path("/reports")
    if reports_dir.exists():
        reports = sorted(reports_dir.glob("summary_*.txt"))
        if reports:
            print(f"\n📁 Reportes generados ({len(reports)}):")
            for report in reports[-10:]:  # Últimos 10
                size = report.stat().st_size / 1024  # KB
                print(f"  - {report.name} ({size:.1f} KB)")

def main():
    print(f"🎯 LogWhisperer iniciado")
    print(f"   - Contenedores: {', '.join(CONTAINERS)}")
    print(f"   - Intervalo: {INTERVAL}s")
    print(f"   - Timeout análisis: {ANALYSIS_TIMEOUT}s")
    print(f"   - Modelo: {MODEL}")
    print(f"   - Ollama: {OLLAMA_HOST}")
    
    while True:
        print(f"\n{'='*60}")
        print(f"🕐 Ciclo de análisis - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        for container_name in CONTAINERS:
            status = get_container_status(container_name)
            
            if status == "running":
                analyze_logs(container_name)
            elif status == "not_found":
                print(f"⚠️  Contenedor '{container_name}' no encontrado")
            else:
                print(f"⚠️  Contenedor '{container_name}' no está corriendo (estado: {status})")
        
        list_reports()
        
        print(f"\n💤 Esperando {INTERVAL} segundos...")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()