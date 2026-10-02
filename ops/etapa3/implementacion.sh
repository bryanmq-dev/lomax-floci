#!/usr/bin/env bash
# Etapa 3 - AWS con S3 y Lambda (Entregable P4)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci
eval "$(floci env)"

# --- Buckets (idempotente: mb falla si ya existe, se ignora ese caso) ---
aws s3 mb s3://lomax-originales 2>/dev/null || echo "lomax-originales ya existe"
aws s3 mb s3://lomax-miniaturas 2>/dev/null || echo "lomax-miniaturas ya existe"

# --- Empaquetar y desplegar la Lambda ---
bash lambda/build.sh

# A que red docker quedan los contenedores de ejecucion de Lambda (bridge o
# floci-net) depende de como arranco floci esa sesion, y cambia solo con un
# reinicio del sistema o un floci stop/start -- ya se vio romperse por un
# hostname fijo DOS VECES ("floci" sin resolver en bridge, y luego
# "localhost.floci.io" sin resolver tras perder floci-net). En vez de apostar
# a un hostname, se usa la IP real de floci en su red "bridge" (siempre
# presente, a diferencia de floci-net), resuelta en cada run -- nunca depende
# de DNS. Ver docs/defensa/guion-defensa.md (Etapa 3).
FLOCI_IP=$(docker inspect floci --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')
LAMBDA_ENV="Variables={AWS_ENDPOINT_URL=http://$FLOCI_IP:4566,BUCKET_MINIATURAS=lomax-miniaturas,TABLE_ATRIBUTOS=LomaxAtributos}"

if aws lambda get-function --function-name lomax-generar-miniatura >/dev/null 2>&1; then
  echo "lomax-generar-miniatura ya existe, actualizando codigo y variables"
  aws lambda update-function-code --function-name lomax-generar-miniatura \
    --zip-file fileb://lambda/function.zip >/dev/null
  aws lambda wait function-updated --function-name lomax-generar-miniatura
  aws lambda update-function-configuration --function-name lomax-generar-miniatura \
    --environment "$LAMBDA_ENV" >/dev/null
else
  aws lambda create-function --function-name lomax-generar-miniatura \
    --runtime nodejs20.x --handler index.handler \
    --zip-file fileb://lambda/function.zip \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment "$LAMBDA_ENV" \
    --timeout 30 >/dev/null
fi
aws lambda wait function-active --function-name lomax-generar-miniatura
aws lambda wait function-updated --function-name lomax-generar-miniatura

# --- Fotos de prueba (incluye el caso 1200x800 que pide el enunciado) ---
python3 scripts/gen-placeholder-images.py --out /tmp/lomax-fotos --count 1 --size 1200x800

echo "Etapa 3 (implementacion) lista."
