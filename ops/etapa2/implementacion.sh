#!/usr/bin/env bash
# Etapa 2 - Persistencia con RDS y DynamoDB (Entregable P3)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci

eval "$(floci env)"   # bash; en fish: eval (floci env)

# IMPORTANTE: si floci esta corriendo con un volumen anonimo (no --persist),
# cualquier "floci restart" borra TODO el estado (no solo el de este proyecto).
# Ver ops/etapa0-setup.sh y docs/defensa/guion-defensa.md (Etapa 2) para el detalle.
MOUNT_SRC=$(docker inspect floci --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}')
case "$MOUNT_SRC" in
  /home/*|/Users/*|/root/*|/mnt/*|/data/*) : ;;  # bind mount a un directorio real, ok
  *)
    echo "AVISO: floci no esta montando un directorio persistente real (mount: $MOUNT_SRC)."
    echo "       Corre: floci stop && floci start --persist ~/.floci/data"
    echo "       antes de seguir, o un reinicio futuro puede perder todo el estado."
    ;;
esac

# --- RDS: instancia Postgres real dentro de FLOCI (idempotente) ---
if aws rds describe-db-instances --db-instance-identifier lomax-db >/dev/null 2>&1; then
  echo "lomax-db ya existe, se omite create-db-instance"
else
  aws rds create-db-instance \
    --db-instance-identifier lomax-db \
    --db-instance-class db.t3.micro \
    --engine postgres --engine-version 16.3 \
    --master-username lomax_admin --master-user-password lomax_pass_local \
    --allocated-storage 20 --db-name lomax
fi

aws rds wait db-instance-available --db-instance-identifier lomax-db

RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
  --query 'DBInstances[0].Endpoint.Port' --output text)

# Solo se guarda la contraseña: el host/puerto de RDS lo reasigna FLOCI en cada
# restart, asi que los scripts siguientes lo vuelven a pedir con describe-db-instances
# en lugar de confiar en un valor cacheado.
cat > ops/etapa2/.env <<EOF
export PGPASSWORD=lomax_pass_local
EOF
echo "RDS listo en $RDS_HOST:$RDS_PORT"

PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -f db/schema.sql
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax -f db/seed_categorias.sql

# --- DynamoDB: tabla de atributos variables + estado de imagen (idempotente) ---
if aws dynamodb describe-table --table-name LomaxAtributos >/dev/null 2>&1; then
  echo "LomaxAtributos ya existe, se omite create-table"
else
  aws dynamodb create-table \
    --table-name LomaxAtributos \
    --attribute-definitions AttributeName=producto_id,AttributeType=S \
    --key-schema AttributeName=producto_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
fi

echo "Etapa 2 (implementacion) lista."
