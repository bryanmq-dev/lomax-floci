#!/usr/bin/env bash
# Resuelve los datos de red de FLOCI que los contenedores de la app necesitan
# (backend, y luego docker-compose en Etapa 5) para hablar con RDS/S3/DynamoDB/Lambda.
#
# floci corre en la red "bridge" por defecto de Docker, que NO tiene DNS por
# nombre de contenedor (comprobado: "floci" no resuelve desde otro contenedor).
# Por eso se resuelve su IP real y se pasa como variable de entorno en vez de
# depender de un hostname.
set -e
cd "$(dirname "$0")/.."
eval "$(floci env)"

FLOCI_IP=$(docker inspect floci --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db \
  --query 'DBInstances[0].Endpoint.Port' --output text)

cat > .env <<EOF
FLOCI_IP=$FLOCI_IP
RDS_PORT=$RDS_PORT
EOF
echo "FLOCI_IP=$FLOCI_IP  RDS_PORT=$RDS_PORT  (escrito en .env)"
