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

if aws lambda get-function --function-name lomax-generar-miniatura >/dev/null 2>&1; then
  echo "lomax-generar-miniatura ya existe, actualizando codigo"
  aws lambda update-function-code --function-name lomax-generar-miniatura \
    --zip-file fileb://lambda/function.zip >/dev/null
else
  # OJO: no fijar AWS_ENDPOINT_URL aqui. FLOCI ya inyecta uno correcto y
  # alcanzable (http://localhost.floci.io:4566) en cada contenedor Lambda;
  # pisarlo con otro valor (ej. http://floci:4566) rompe la resolucion DNS
  # dentro del contenedor de ejecucion (probado: "getaddrinfo ENOTFOUND floci").
  aws lambda create-function --function-name lomax-generar-miniatura \
    --runtime nodejs20.x --handler index.handler \
    --zip-file fileb://lambda/function.zip \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment "Variables={BUCKET_MINIATURAS=lomax-miniaturas,TABLE_ATRIBUTOS=LomaxAtributos}" \
    --timeout 30 >/dev/null
fi
aws lambda wait function-active --function-name lomax-generar-miniatura

# --- Fotos de prueba (incluye el caso 1200x800 que pide el enunciado) ---
python3 scripts/gen-placeholder-images.py --out /tmp/lomax-fotos --count 1 --size 1200x800

echo "Etapa 3 (implementacion) lista."
