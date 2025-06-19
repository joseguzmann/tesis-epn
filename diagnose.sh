#!/usr/bin/env bash
echo "=== DIAGNÓSTICO DE LOGWHISPERER ==="
echo

echo "1. Contenedores relevantes:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(moodle|ollama|logwhisperer)"
echo

echo "2. Reportes generados:"
ls -1 ./log_reports || true
echo

echo "3. Últimos logs de logwhisperer:"
docker logs logwhisperer --tail 30
