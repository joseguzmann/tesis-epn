#!/bin/bash
set -e

echo "🚀 Iniciando LogWhisperer..."

# Variables de configuración
OLLAMA_HOST=${OLLAMA_HOST:-"http://ollama:11434"}
MAX_RETRIES=30
RETRY_COUNT=0

# Función para verificar si Ollama está disponible
check_ollama() {
    curl -s -f "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1
}

# Función para verificar si el modelo existe
check_model() {
    local model_name="$1"
    curl -s "${OLLAMA_HOST}/api/tags" | jq -r '.models[].name' | grep -q "^${model_name}$"
}

# Función para descargar modelo si no existe
ensure_model() {
    local model_name="$1"
    if ! check_model "$model_name"; then
        echo "📦 Descargando modelo $model_name (esto puede tomar varios minutos)..."
        
        # Usar ollama directamente en lugar de curl para mejor manejo
        docker exec ollama ollama pull "$model_name" || {
            echo "❌ Error al descargar el modelo $model_name con ollama"
            echo "🔄 Intentando con curl..."
            
            # Fallback a curl con timeout más largo
            timeout 1800 curl -X POST "${OLLAMA_HOST}/api/pull" \
                 -H "Content-Type: application/json" \
                 -d "{\"name\": \"$model_name\"}" \
                 --silent --show-error || {
                echo "❌ Error al descargar el modelo $model_name"
                return 1
            }
        }
        
        # Verificar que el modelo se descargó correctamente
        sleep 5
        if check_model "$model_name"; then
            echo "✅ Modelo $model_name descargado y verificado correctamente"
        else
            echo "❌ Error: El modelo $model_name no se encuentra disponible después de la descarga"
            return 1
        fi
    else
        echo "✅ Modelo $model_name ya disponible"
    fi
}

# 1) Esperar a que Ollama esté disponible
echo "⏳ Esperando a que Ollama esté disponible en $OLLAMA_HOST..."
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if check_ollama; then
        echo "✅ Ollama está disponible"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "⏳ Intento $RETRY_COUNT/$MAX_RETRIES - Esperando a Ollama..."
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Error: No se pudo conectar a Ollama después de $MAX_RETRIES intentos"
    exit 1
fi

# 2) Asegurar que el modelo esté disponible
MODEL_NAME="phi3:mini"
echo "🤖 Verificando modelo $MODEL_NAME..."
ensure_model "$MODEL_NAME" || {
    echo "⚠️  Error con phi3:mini, probando con modelo más pequeño..."
    MODEL_NAME="phi3:3.8b"
    ensure_model "$MODEL_NAME" || {
        echo "⚠️  Usando modelo base más pequeño..."
        MODEL_NAME="llama3.2:1b"
        ensure_model "$MODEL_NAME" || {
            echo "❌ No se pudo descargar ningún modelo compatible"
            exit 1
        }
    }
}

# 3) Verificar que el contenedor objetivo existe
echo "🔍 Verificando contenedor moodle-app..."
if ! docker ps --format "table {{.Names}}" | grep -q "moodle-app"; then
    echo "⚠️  Contenedor moodle-app no encontrado, esperando..."
    sleep 10
fi

# 4) Ejecutar LogWhisperer con configuración mejorada
echo "🎯 Iniciando LogWhisperer para monitorear moodle-app con modelo $MODEL_NAME..."

# Crear directorio de reportes si no existe
mkdir -p /reports

# Verificar que podemos leer logs del contenedor
echo "🔍 Verificando acceso a logs..."
if docker logs moodle-app --tail 5 >/dev/null 2>&1; then
    echo "✅ Acceso a logs de moodle-app confirmado"
else
    echo "⚠️  Problema accediendo a logs de moodle-app"
fi

# Ejecutar LogWhisperer con configuración optimizada
echo "🚀 Ejecutando LogWhisperer..."
exec python3 logwhisperer.py \
  --source docker \
  --container moodle-app \
  --follow \
  --interval 10 \
  --model "$MODEL_NAME" \
  --ollama-host "$OLLAMA_HOST" \
  --entries 50 \
  --timeout 30 2>&1 | tee /reports/logwhisperer.log