#!/usr/bin/env python3
import os
import time
import subprocess
import docker
import json
import requests
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

def analyze_with_ollama(logs_text, container_name):
    """Analiza logs directamente con Ollama API"""
    try:
        prompt = f"""Analiza los siguientes logs del contenedor {container_name} y proporciona un resumen conciso:

1. Identifica los mensajes más importantes
2. Detecta errores o advertencias críticas
3. Resume el estado general del servicio
4. Sugiere acciones si hay problemas

Logs:
{logs_text[:4000]}  # Limitar para no sobrecargar el modelo

Proporciona un resumen en español, estructurado y claro."""

        # Llamar a Ollama API directamente
        response = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={
                "model": MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.5,
                    "max_tokens": 500
                }
            },
            timeout=ANALYSIS_TIMEOUT
        )
        
        if response.status_code == 200:
            result = response.json()
            return result.get("response", "No se pudo obtener análisis")
        else:
            return f"Error al analizar con Ollama: {response.status_code}"
            
    except requests.exceptions.Timeout:
        return "Timeout al analizar con Ollama"
    except Exception as e:
        return f"Error: {str(e)}"

def analyze_logs(container_name):
    """Analiza los logs de un contenedor"""
    print(f"📊 Analizando {container_name}...")
    
    # Obtener timestamp para el reporte
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"/reports/summary_{container_name}_{timestamp}.txt"
    
    # Obtener logs
    logs = get_recent_logs(container_name, lines=100)
    
    # Intentar análisis con Ollama
    analysis = analyze_with_ollama(logs, container_name)
    
    # Guardar reporte
    with open(report_file, 'w') as f:
        f.write(f"=== Análisis de logs para {container_name} ===\n")
        f.write(f"Timestamp: {datetime.now().isoformat()}\n")
        f.write(f"Estado del contenedor: {get_container_status(container_name)}\n")
        f.write(f"Modelo usado: {MODEL}\n")
        f.write("=" * 50 + "\n\n")
        
        f.write("=== ANÁLISIS ===\n")
        f.write(analysis)
        f.write("\n\n")
        
        f.write("=== LOGS ORIGINALES (últimas 50 líneas) ===\n")
        log_lines = logs.split("\n")
        for line in log_lines[-50:]:
            f.write(line + "\n")
    
    print(f"✅ Reporte guardado: {report_file}")

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

def verify_setup():
    """Verifica que todo esté configurado correctamente"""
    print("🔍 Verificando configuración...")
    
    # Verificar que config.yaml existe
    if os.path.exists("/opt/logwhisperer/config.yaml"):
        print("✅ config.yaml encontrado")
        with open("/opt/logwhisperer/config.yaml", 'r') as f:
            print(f"   Contenido: {f.read()}")
    else:
        print("⚠️  config.yaml no encontrado, usando valores por defecto")
    
    # Verificar conexión a Ollama
    try:
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        if response.status_code == 200:
            print("✅ Ollama accesible")
            models = response.json().get('models', [])
            print(f"   Modelos disponibles: {[m['name'] for m in models]}")
        else:
            print("⚠️  Ollama responde pero con error")
    except Exception as e:
        print(f"❌ No se puede conectar a Ollama: {e}")
    
    # Verificar directorio de reportes
    os.makedirs("/reports", exist_ok=True)
    print("✅ Directorio de reportes creado")

def main():
    print(f"🎯 LogWhisperer Wrapper iniciado")
    print(f"   - Contenedores: {', '.join(CONTAINERS)}")
    print(f"   - Intervalo: {INTERVAL}s")
    print(f"   - Timeout análisis: {ANALYSIS_TIMEOUT}s")
    print(f"   - Modelo: {MODEL}")
    print(f"   - Ollama: {OLLAMA_HOST}")
    
    # Verificar configuración
    verify_setup()
    
    # Esperar un poco para que todos los servicios estén listos
    print("\n⏳ Esperando 10 segundos para que los servicios se estabilicen...")
    time.sleep(10)
    
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