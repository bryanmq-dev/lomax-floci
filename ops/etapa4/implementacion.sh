#!/usr/bin/env bash
# Etapa 4 - Backend con API y endpoints (Entregable P5)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci

bash ops/generar-env-floci.sh
source .env

docker build -t lomax-backend:local ./backend

docker rm -f lomax-backend-test >/dev/null 2>&1 || true
docker run -d --name lomax-backend-test -p 4000:4000 \
  --network bridge \
  -e AWS_ENDPOINT_URL="http://$FLOCI_IP:4566" \
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-east-1 -e AWS_REGION=us-east-1 \
  -e PGHOST="$FLOCI_IP" -e PGPORT="$RDS_PORT" \
  -e PGUSER=lomax_admin -e PGPASSWORD=lomax_pass_local -e PGDATABASE=lomax \
  -e BUCKET_ORIGINALES=lomax-originales -e BUCKET_MINIATURAS=lomax-miniaturas \
  -e TABLE_ATRIBUTOS=LomaxAtributos -e LAMBDA_FUNCTION=lomax-generar-miniatura \
  lomax-backend:local

echo "esperando a que el backend responda..."
for i in $(seq 1 15); do
  curl -sf http://localhost:4000/categorias >/dev/null 2>&1 && break
  sleep 1
done
curl -s http://localhost:4000/categorias
echo
echo "Etapa 4 (implementacion) lista. Backend en http://localhost:4000"
