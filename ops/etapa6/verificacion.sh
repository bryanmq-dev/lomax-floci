#!/usr/bin/env bash
# Etapa 6 - Verificacion E6 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"

REGISTRY="000000000000.dkr.ecr.us-east-1.localhost:4566"
GIT_SHA=$(cat .ultima-version-ecr)
echo "Version verificada: $GIT_SHA"

echo "--- describe-images ---"
aws ecr describe-images --repository-name lomax/backend
aws ecr describe-images --repository-name lomax/frontend

echo "--- pull en 'entorno limpio' (borrar la copia local y volver a traerla) ---"
docker rmi "$REGISTRY/lomax/backend:$GIT_SHA" >/dev/null
docker pull "$REGISTRY/lomax/backend:$GIT_SHA"
docker rmi "$REGISTRY/lomax/frontend:$GIT_SHA" >/dev/null
docker pull "$REGISTRY/lomax/frontend:$GIT_SHA"

echo "--- ejecutar la imagen descargada y comprobar que es la app entregada ---"
bash ops/generar-env-floci.sh
source .env
docker rm -f lomax-backend-fromecr >/dev/null 2>&1 || true
docker run -d --name lomax-backend-fromecr -p 4001:4000 \
  --network bridge \
  -e AWS_ENDPOINT_URL="http://$FLOCI_IP:4566" \
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-east-1 -e AWS_REGION=us-east-1 \
  -e PGHOST="$FLOCI_IP" -e PGPORT="$RDS_PORT" \
  -e PGUSER=lomax_admin -e PGPASSWORD=lomax_pass_local -e PGDATABASE=lomax \
  -e BUCKET_ORIGINALES=lomax-originales -e BUCKET_MINIATURAS=lomax-miniaturas \
  -e TABLE_ATRIBUTOS=LomaxAtributos -e LAMBDA_FUNCTION=lomax-generar-miniatura \
  "$REGISTRY/lomax/backend:$GIT_SHA"

echo "esperando a que el contenedor recuperado responda..."
for i in $(seq 1 15); do
  curl -sf http://localhost:4001/categorias >/dev/null 2>&1 && break
  sleep 1
done
curl -s http://localhost:4001/categorias
echo
docker rm -f lomax-backend-fromecr >/dev/null
