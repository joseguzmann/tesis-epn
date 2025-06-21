#!/usr/bin/env bash
echo "=== DIAGNÓSTICO DE LOGWHISPERER ==="
echo

echo "1. Contenedores y su estado:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep -E "(moodle|ollama|logwhisperer|db)"
echo

echo "2. Verificando volumen de reportes:"
docker exec logwhisperer ls -la /reports 2>/dev/null || echo "No se puede acceder a /reports"
echo

echo "3. Reportes generados:"
ls -la ./log_reports/ 2>/dev/null || echo "No hay reportes en ./log_reports/"
echo

echo "4. Verificando conexión a Ollama:"
docker exec logwhisperer curl -s http://ollama:11434/api/tags | jq '.models[].name' 2>/dev/null || echo "No se puede conectar a Ollama"
echo

echo "5. Últimos logs de logwhisperer (30 líneas):"
docker logs logwhisperer --tail 30 2>&1
echo

echo "6. Estado de la base de datos:"
docker logs moodle-db --tail 20 2>&1 | grep -E "(ready|error|started)" || echo "No hay logs relevantes"
echo

echo "7. Verificando permisos del socket Docker:"
docker exec logwhisperer ls -la /var/run/docker.sock 2>/dev/null || echo "No se puede acceder al socket"
echo

echo "8. Verificando configuración de LogWhisperer:"
docker exec logwhisperer cat /opt/logwhisperer/config.yaml 2>/dev/null || echo "No se puede leer config.yaml"
echo

echo "9. Probando análisis con Ollama directamente:"
docker exec logwhisperer curl -s -X POST http://ollama:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"phi3:mini","prompt":"Test: Say hello","stream":false}' | jq -r '.response // "No response"' 2>/dev/null || echo "No se puede conectar a Ollama"
echo

echo "10. Mostrando un reporte reciente completo:"
LATEST_REPORT=$(docker exec logwhisperer find /reports -name "summary_*.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
if [ -n "$LATEST_REPORT" ]; then
    echo "Reporte más reciente: $(basename $LATEST_REPORT)"
    echo "---"
    docker exec logwhisperer head -50 "$LATEST_REPORT" 2>/dev/null
    echo "---"
else
    echo "No hay reportes disponibles"
fi