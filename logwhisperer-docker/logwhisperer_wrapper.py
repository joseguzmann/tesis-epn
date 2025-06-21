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
    
    # Obtener timestamp para el reporte
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"/reports/summary_{container_name}_{timestamp}.txt"
    
    # Método 1: Usar Docker directamente (más confiable)
    cmd = [
        "python3", "/opt/logwhisperer/logwhisperer.py",
        "--source", "docker",
        "--container", container_name,
        "--model", MODEL,
        "--ollama-host", OLLAMA_HOST,
        "--entries", "100",
        "--timeout", str(ANALYSIS_TIMEOUT)
    ]
    
    try:
        # Ejecutar desde el directorio de LogWhisperer donde está config.yaml
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            timeout=ANALYSIS_TIMEOUT + 10,
            cwd="/opt/logwhisperer"  # Ejecutar desde el directorio correcto
        )
        
        # Buscar el reporte generado
        report_pattern = f"/opt/logwhisperer/reports/log_summary_*.md"
        latest_reports = subprocess.run(
            ["bash", "-c", f"ls -t {report_pattern} 2>/dev/null | head -1"],
            capture_output=True,
            text=True
        )
        
        latest_report_path = latest_reports.stdout.strip()
        
        # Si se generó un reporte, lo movemos
        if latest_report_path and os.path.exists(latest_report_path):
            # Leer el contenido del reporte generado
            with open(latest_report_path, 'r') as f:
                report_content = f.read()
            
            # Guardar en nuestro formato
            with open(report_file, 'w') as f:
                f.write(f"=== Análisis de logs para {container_name} ===\n")
                f.write(f"Timestamp: {datetime.now().isoformat()}\n")
                f.write(f"Estado del contenedor: {get_container_status(container_name)}\n")
                f.write(f"Modelo usado: {MODEL}\n")
                f.write("=" * 50 + "\n\n")
                f.write(report_content)
            
            # Eliminar el reporte original
            os.remove(latest_report_path)
            print(f"✅ Reporte guardado: {report_file}")
            
        else:
            # Si no se generó reporte, crear uno con la salida
            logs = get_recent_logs(container_name)
            
            with open(report_file, 'w') as f:
                f.write(f"=== Análisis de logs para {container_name} ===\n")
                f.write(f"Timestamp: {datetime.now().isoformat()}\n")
                f.write(f"Estado del contenedor: {get_container_status(container_name)}\n")
                f.write(f"Modelo usado: {MODEL}\n")
                f.write("=" * 50 + "\n\n")
                
                if result.stdout and len(result.stdout) > 10:
                    f.write("=== ANÁLISIS ===\n")
                    f.write(result.stdout)
                    f.write("\n\n")
                elif result.returncode == 0:
                    f.write("=== ANÁLISIS ===\n")
                    f.write("Análisis completado pero sin salida detallada.\n\n")
                
                if result.stderr:
                    f.write("=== ERRORES ===\n")
                    f.write(result.stderr)
                    f.write("\n\n")
                
                f.write("=== LOGS ORIGINALES (últimas 50 líneas) ===\n")
                f.write("\n".join(logs.split("\n")[-50:]))
            
            print(f"📝 Reporte guardado: {report_file}")
        
    except subprocess.TimeoutExpired:
        print(f"⏱️  Timeout analizando {container_name}")
        logs = get_recent_logs(container_name)
        
        with open(report_file, 'w') as f:
            f.write(f"=== Logs de {container_name} (sin análisis - timeout) ===\n")
            f.write(f"Timestamp: {datetime.now().isoformat()}\n")
            f.write(f"Timeout después de {ANALYSIS_TIMEOUT} segundos\n\n")
            f.write(logs)
        print(f"📝 Logs guardados sin análisis: {report_file}")
        
    except Exception as e:
        print(f"❌ Error analizando {container_name}: {e}")
        # Guardar logs sin análisis
        logs = get_recent_logs(container_name)
        with open(report_file, 'w') as f:
            f.write(f"=== Error analizando {container_name} ===\n")
            f.write(f"Error: {str(e)}\n\n")
            f.write("=== LOGS ORIGINALES ===\n")
            f.write(logs)

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
    else:
        print("⚠️  config.yaml no encontrado, usando valores por defecto")
    
    # Verificar conexión a Ollama
    try:
        import requests
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        if response.status_code == 200:
            print("✅ Ollama accesible")
        else:
            print("⚠️  Ollama responde pero con error")
    except:
        print("❌ No se puede conectar a Ollama")
    
    # Verificar directorio de reportes de LogWhisperer
    os.makedirs("/opt/logwhisperer/reports", exist_ok=True)
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
    
    # Test inicial
    print("\n🧪 Probando LogWhisperer...")
    test_result = subprocess.run(
        ["python3", "/opt/logwhisperer/logwhisperer.py", "--version"],
        capture_output=True, text=True,
        cwd="/opt/logwhisperer"
    )
    if test_result.stdout:
        print(f"LogWhisperer version: {test_result.stdout.strip()}")
    
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