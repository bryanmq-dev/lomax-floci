#!/usr/bin/env bash
# Etapa 2 - Verificacion E2 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"
source ops/etapa2/.env   # trae PGPASSWORD (RDS_HOST/RDS_PORT se refrescan abajo)

# FLOCI reasigna IP/puerto internos del contenedor Postgres detras de RDS en cada
# restart, asi que el endpoint NUNCA se cachea entre pasos: se relee con
# describe-db-instances cada vez que puede haber cambiado.
refresh_endpoint() {
  RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
    --query 'DBInstances[0].Endpoint.Address' --output text)
  RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
    --query 'DBInstances[0].Endpoint.Port' --output text)
  PSQL="psql -h $RDS_HOST -p $RDS_PORT -U lomax_admin -d lomax"
  echo "Endpoint RDS actual: $RDS_HOST:$RDS_PORT"
}

refresh_endpoint

echo "--- insercion valida ---"
$PSQL -c "INSERT INTO productos (codigo,nombre,precio,categoria_id) VALUES ('TEC-001','Teclado Mecanico X',35.90,1) RETURNING producto_id;"

echo "--- codigo duplicado (debe fallar) ---"
$PSQL -c "INSERT INTO productos (codigo,nombre,precio,categoria_id) VALUES ('TEC-001','Otro',10,1);" || true

echo "--- precio negativo (debe fallar) ---"
$PSQL -c "INSERT INTO productos (codigo,nombre,precio,categoria_id) VALUES ('TEC-002','Malo',-5,1);" || true

echo "--- categoria inexistente (debe fallar) ---"
$PSQL -c "INSERT INTO productos (codigo,nombre,precio,categoria_id) VALUES ('TEC-003','X',10,999);" || true

echo "--- sin registros parciales ---"
$PSQL -c "SELECT * FROM productos;"

echo "--- DynamoDB: guardar y recuperar por producto_id ---"
aws dynamodb put-item --table-name LomaxAtributos --item '{
  "producto_id": {"S": "1"},
  "atributos": {"M": {"conexion": {"S": "USB"}, "distribucion": {"S": "Espanol"}}},
  "estado_imagen": {"S": "PENDIENTE"}
}'
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id": {"S": "1"}}'

echo "--- reinicio sin borrar volumenes ---"
floci restart
floci wait
refresh_endpoint   # el endpoint puede haber cambiado tras el restart
$PSQL -c "SELECT count(*) FROM productos;"
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id": {"S": "1"}}'

echo "--- carga inicial repetible sin duplicar ---"
$PSQL -f db/seed_categorias.sql
$PSQL -c "SELECT * FROM categorias;"
