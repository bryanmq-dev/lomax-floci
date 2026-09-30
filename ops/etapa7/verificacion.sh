#!/usr/bin/env bash
# Etapa 7 - Verificacion E7 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"
BASE=http://localhost:8091/api

echo "--- pods actuales ---"
kubectl -n lomax get pods -o wide

echo "--- imagenes de los pods (deben ser las de ECR, Etapa 6) ---"
kubectl -n lomax get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  ->  "}{.spec.containers[0].image}{"\n"}{end}'

echo "--- escalar backend 1 -> 3 ---"
kubectl -n lomax scale deployment/backend --replicas=3
kubectl -n lomax rollout status deployment/backend
kubectl -n lomax get pods -l app=backend

echo "--- solicitudes atendidas por Pods distintos (header X-Instancia = HOSTNAME del Pod) ---"
for i in 1 2 3 4 5 6; do
  curl -s -D - -o /dev/null $BASE/categorias | grep -i x-instancia
done

echo "--- eliminar un pod y ver el reemplazo ---"
POD=$(kubectl -n lomax get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
UID_ANTES=$(kubectl -n lomax get pod "$POD" -o jsonpath='{.metadata.uid}')
echo "pod eliminado: $POD  uid_antes=$UID_ANTES"
kubectl -n lomax delete pod "$POD"
kubectl -n lomax rollout status deployment/backend
kubectl -n lomax get pods -l app=backend
# el pod nuevo es el mas reciente por fecha de creacion (el filtro "!= nombre
# borrado" no sirve aqui: el pod borrado ya no esta en la lista, asi que
# "coincide" con los 3 restantes, no solo con el reemplazo)
NUEVO_POD=$(kubectl -n lomax get pods -l app=backend --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
UID_DESPUES=$(kubectl -n lomax get pod "$NUEVO_POD" -o jsonpath='{.metadata.uid}')
echo "pod nuevo: $NUEVO_POD  uid_despues=$UID_DESPUES (debe ser distinto de $UID_ANTES)"
curl -s -o /dev/null -w "catalogo sigue respondiendo: HTTP %{http_code}\n" http://localhost:8091/catalogo.html

echo "--- registrar un producto nuevo desde EKS ---"
# deja el script re-corrible: limpia el codigo de prueba de una corrida anterior
RDS_HOST0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT0=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST0" -p "$RDS_PORT0" -U lomax_admin -d lomax -c \
  "DELETE FROM productos WHERE codigo = 'TEC-E7';" >/dev/null

curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"TEC-E7","nombre":"Teclado desde EKS","precio":22.5,"categoria_id":1,
  "atributos":{"conexion":"USB","distribucion":"Español"}}' | tee /tmp/e7-post.json | jq
ID=$(jq -r .producto_id /tmp/e7-post.json)
curl -s -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/lomax-fotos/producto_1.jpg" | jq

RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -c "SELECT producto_id, codigo, estado FROM productos WHERE producto_id=$ID;"
aws dynamodb get-item --table-name LomaxAtributos --key "{\"producto_id\": {\"S\": \"$ID\"}}"
aws s3 cp s3://lomax-miniaturas/miniaturas/$ID.jpg /tmp/e7-miniatura.jpg

echo "--- recrear TODOS los pods del backend y repetir la consulta ---"
kubectl -n lomax delete pod -l app=backend
kubectl -n lomax rollout status deployment/backend
curl -s $BASE/productos/$ID | jq   # el producto sigue disponible: los datos viven en FLOCI, no en el Pod
curl -s $BASE/productos | jq --arg id "$ID" '[.[] | select((.producto_id|tostring) == $id)] | length'   # 1: aparece en el catalogo
