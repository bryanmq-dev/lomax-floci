#!/usr/bin/env bash
# Etapa 2 - Persistencia con RDS y DynamoDB (Entregable P3)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci

eval "$(floci env)"   # bash; en fish: eval (floci env)

# --- RDS: instancia Postgres real dentro de FLOCI ---
aws rds create-db-instance \
  --db-instance-identifier lomax-db \
  --db-instance-class db.t3.micro \
  --engine postgres --engine-version 16.3 \
  --master-username lomax_admin --master-user-password lomax_pass_local \
  --allocated-storage 20 --db-name lomax

aws rds wait db-instance-available --db-instance-identifier lomax-db

RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
  --query 'DBInstances[0].Endpoint.Port' --output text)

# se guarda para que verificacion.sh (y las etapas siguientes) no repitan el describe-db-instances
cat > ops/etapa2/.env <<EOF
export RDS_HOST=$RDS_HOST
export RDS_PORT=$RDS_PORT
export PGPASSWORD=lomax_pass_local
EOF
echo "RDS listo en $RDS_HOST:$RDS_PORT (guardado en ops/etapa2/.env)"

PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -f db/schema.sql
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -f db/seed_categorias.sql

# --- DynamoDB: tabla de atributos variables + estado de imagen ---
aws dynamodb create-table \
  --table-name LomaxAtributos \
  --attribute-definitions AttributeName=producto_id,AttributeType=S \
  --key-schema AttributeName=producto_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "Etapa 2 (implementacion) lista."
