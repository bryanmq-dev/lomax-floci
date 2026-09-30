#!/usr/bin/env bash
# Etapa 2 - Verificacion E2 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"
source ops/etapa2/.env   # trae RDS_HOST, RDS_PORT, PGPASSWORD

PSQL="psql -h $RDS_HOST -p $RDS_PORT -U lomax_admin -d lomax"

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
$PSQL -c "SELECT count(*) FROM productos;"
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id": {"S": "1"}}'

echo "--- carga inicial repetible sin duplicar ---"
$PSQL -f db/seed_categorias.sql
$PSQL -c "SELECT * FROM categorias;"
