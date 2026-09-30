#!/usr/bin/env bash
# Etapa 5 - Verificacion E5 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"
BASE=http://localhost:8090/api

echo "--- abrir el formulario y registrar 1 producto nuevo a mano (captura de pantalla) ---"
xdg-open http://localhost:8090/registrar.html

echo "--- equivalente por API, para tener producto_id + request/response documentados ---"
# deja el script re-corrible
RDS_HOST0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST0" -p "$RDS_PORT0" -U lomax_admin -d lomax -c \
  "DELETE FROM productos WHERE codigo IN ('TEC-999','TEC-998');" >/dev/null

curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"TEC-999","nombre":"Teclado Verificacion E5","precio":19.99,"categoria_id":1,
  "atributos":{"conexion":"USB","distribucion":"Español"}}' | tee /tmp/e5-post.json | jq
ID=$(jq -r .producto_id /tmp/e5-post.json)
curl -s -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/lomax-fotos/producto_1.jpg" | jq

echo "--- abrir el detalle del producto recien creado (captura de pantalla) ---"
xdg-open "http://localhost:8090/detalle.html?id=$ID"

echo "--- confirmar en RDS, DynamoDB y S3 ---"
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -c "SELECT producto_id, codigo, estado FROM productos WHERE producto_id=$ID;"
aws dynamodb get-item --table-name LomaxAtributos --key "{\"producto_id\": {\"S\": \"$ID\"}}"
aws s3 cp s3://lomax-miniaturas/miniaturas/$ID.jpg /tmp/e5-miniatura.jpg

echo "--- codigo duplicado: la interfaz debe mostrar el error (repetir en registrar.html con codigo TEC-999) ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos -H 'Content-Type: application/json' \
  -d '{"codigo":"TEC-999","nombre":"otro","precio":1,"categoria_id":1}'

echo "--- archivo invalido: no debe aparecer en el catalogo ---"
echo "no es una imagen" > /tmp/invalido.txt
curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"TEC-998","nombre":"Teclado archivo invalido","precio":9.99,"categoria_id":1}' | tee /tmp/e5-post2.json | jq
ID2=$(jq -r .producto_id /tmp/e5-post2.json)
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $BASE/productos/$ID2/imagen -F "imagen=@/tmp/invalido.txt"
curl -s $BASE/productos | jq --arg id "$ID2" '[.[] | select((.producto_id|tostring) == $id)] | length'   # debe ser 0

echo "--- catalogo completo (captura de pantalla) ---"
xdg-open http://localhost:8090/catalogo.html
curl -s $BASE/productos | jq 'length'
