#!/usr/bin/env bash
# Etapa 4 - Verificacion E4 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"
BASE=http://localhost:4000

echo "--- GET /categorias ---"
curl -s $BASE/categorias | jq

echo "--- POST /productos (valido) ---"
# deja el script re-corrible: limpia los codigos de prueba de una corrida anterior
RDS_HOST0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST0" -p "$RDS_PORT0" -U lomax_admin -d lomax -c \
  "DELETE FROM productos WHERE codigo IN ('MOU-100','MOU-101');" >/dev/null

curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"MOU-100","nombre":"Mouse Inalambrico Verificacion","precio":15.5,"categoria_id":2,
  "atributos":{"conexion":"Bluetooth","dpi":1600}}' | tee /tmp/resp-post.json | jq
ID=$(jq -r .producto_id /tmp/resp-post.json)
echo "producto_id=$ID"

echo "--- confirmar en RDS y DynamoDB ---"
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -c "SELECT producto_id, codigo, estado FROM productos WHERE producto_id=$ID;"
aws dynamodb get-item --table-name LomaxAtributos --key "{\"producto_id\": {\"S\": \"$ID\"}}"

echo "--- POST /productos/:id/imagen (publica) ---"
curl -s -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/lomax-fotos/producto_1.jpg" | tee /tmp/resp-img.json | jq
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -c "SELECT estado FROM productos WHERE producto_id=$ID;"

echo "--- GET /productos/:id/imagen vs objeto en S3 (deben coincidir) ---"
curl -s -o /tmp/miniatura-endpoint.jpg $BASE/productos/$ID/imagen
aws s3 cp s3://lomax-miniaturas/miniaturas/$ID.jpg /tmp/miniatura-s3.jpg
diff /tmp/miniatura-endpoint.jpg /tmp/miniatura-s3.jpg && echo "coinciden"

echo "--- codigo duplicado -> 409 ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos -H 'Content-Type: application/json' \
  -d '{"codigo":"MOU-100","nombre":"otro","precio":1,"categoria_id":2}'

echo "--- archivo > 5MB -> 413 ---"
head -c 6000000 /dev/urandom > /tmp/grande.jpg
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/grande.jpg"

echo "--- formato invalido -> 415 ---"
echo "no es una imagen" > /tmp/invalido.txt
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/invalido.txt"

echo "--- POST /productos/:id/reprocesar (no debe duplicar objetos) ---"
ANTES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
curl -s -X POST $BASE/productos/$ID/reprocesar | jq
DESPUES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
echo "objetos antes=$ANTES despues=$DESPUES (deben ser iguales)"

echo "--- reprocesar sobre producto existente SIN original -> 409 ---"
curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"MOU-101","nombre":"Mouse sin foto","precio":9.9,"categoria_id":2}' | tee /tmp/resp-post2.json | jq
ID2=$(jq -r .producto_id /tmp/resp-post2.json)
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos/$ID2/reprocesar

echo "--- GET /productos/:id inexistente -> 404 ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" $BASE/productos/999999

echo "--- GET /productos (solo publicados) ---"
curl -s $BASE/productos | jq
