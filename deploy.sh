#!/bin/bash

echo "🔄 Iniciando despliegue de CRT Quant..."

# 1. Obtener los últimos cambios del repositorio
echo "📥 Descargando últimos cambios de Git..."
git pull

# 2. Detener los contenedores actuales (opcional, up -d recrea si hay cambios, pero down asegura un reinicio limpio de la red si es necesario)
# echo "🛑 Deteniendo servicios..."
# docker-compose down

# 3. Construir y levantar los contenedores en segundo plano
echo "🚀 Construyendo y levantando contenedores Docker..."
docker-compose up -d --build

# 4. Limpiar imágenes huérfanas o viejas para liberar espacio (opcional pero recomendado)
echo "🧹 Limpiando imágenes de Docker sin uso..."
docker image prune -f

echo "✅ Despliegue completado con éxito."
