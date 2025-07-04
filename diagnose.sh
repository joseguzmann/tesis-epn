#!/usr/bin/env bash
echo "=== DIAGNÓSTICO DE LOGINSIGHTS ==="
echo

echo "1. Contenedores y su estado:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep -E "(moodle|ollama|loginsights|db)"
echo

echo "2. Verificando volumen de reportes:"
docker exec loginsights ls -la /reports 2>/dev/null || echo "No se puede acceder a /reports"
echo

echo "3. Reportes generados:"
ls -la ./log_reports/ 2>/dev/null || echo "No hay reportes en ./log_reports/"
echo

echo "4. Verificando conexión a Ollama:"
docker exec loginsights curl -s http://ollama:11434/api/tags | jq '.models[].name' 2>/dev/null || echo "No se puede conectar a Ollama"
echo

echo "5. Últimos logs de loginsights (30 líneas):"
docker logs loginsights --tail 30 2>&1
echo

echo "6. Estado de la base de datos:"
docker logs moodle-db --tail 20 2>&1 | grep -E "(ready|error|started)" || echo "No hay logs relevantes"
echo

echo "7. Verificando permisos del socket Docker:"
docker exec loginsights ls -la /var/run/docker.sock 2>/dev/null || echo "No se puede acceder al socket"
echo

echo "8. Verificando script de LogInsights:"
docker exec loginsights python3 -c "import loginsights; print('LogInsights módulo cargado correctamente')" 2>/dev/null || echo "No se puede verificar el script"
echo

echo "9. Probando análisis con Ollama directamente:"
docker exec loginsights curl -s -X POST http://ollama:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"tinyllama:1.1b","prompt":"Test: Say hello","stream":false}' | jq -r '.response // "No response"' 2>/dev/null || echo "No se puede conectar a Ollama"
echo

echo "10. Mostrando un reporte reciente completo:"
LATEST_REPORT=$(docker exec loginsights find /reports -name "summary_*.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
if [ -n "$LATEST_REPORT" ]; then
    echo "Reporte más reciente: $(basename $LATEST_REPORT)"
    echo "---"
    docker exec loginsights head -50 "$LATEST_REPORT" 2>/dev/null
    echo "---"
else
    echo "No hay reportes disponibles"
fi
