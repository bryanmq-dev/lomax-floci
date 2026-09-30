#!/usr/bin/env bash
# Etapa 5 - Frontend con dashboard del catalogo (Entregable P6)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci

bash ops/generar-env-floci.sh   # escribe .env con FLOCI_IP y RDS_PORT

docker rm -f lomax-backend-test >/dev/null 2>&1 || true   # liberar :4000/:5432 de la Etapa 4

docker compose build
docker compose up -d

# El backend tambien necesita la red de floci ("bridge", sin DNS por nombre de
# contenedor). No se puede declarar en docker-compose.yml: esa red no admite
# los alias que compose intenta asignar. Se conecta aparte, una vez arriba.
docker network connect bridge "$(docker compose ps -q backend)" 2>/dev/null || true
docker compose ps

echo "esperando a que el proxy responda..."
for i in $(seq 1 20); do
  curl -sf http://localhost:8090/api/categorias >/dev/null 2>&1 && break
  sleep 1
done
curl -s http://localhost:8090/api/categorias
echo

python3 scripts/gen-placeholder-images.py --out /tmp/lomax-fotos --count 20
node scripts/seed-productos.mjs --base-url http://localhost:8090/api --fotos /tmp/lomax-fotos

echo "Etapa 5 (implementacion) lista. App en http://localhost:8090"
