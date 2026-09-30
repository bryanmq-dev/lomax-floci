#!/usr/bin/env bash
# Etapa 7 - Despliegue y validacion en EKS (Entregable P8)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci
eval "$(floci env)"

REGISTRY="000000000000.dkr.ecr.us-east-1.localhost:4566"
GIT_SHA=$(cat .ultima-version-ecr 2>/dev/null || git rev-parse --short HEAD)

# --- clúster (idempotente) ---
if ! kind get clusters | grep -qx lomax-eks; then
  kind create cluster --name lomax-eks --config k8s/kind-config.yaml
fi
kubectl config use-context kind-lomax-eks
kubectl apply -f k8s/namespace.yaml

# El nodo de kind vive en la red docker "kind", distinta de la red "bridge" donde
# esta floci (mismo problema que en Etapas 3/4/5/6, solucion identica: unir las
# dos redes). Sin esto los Pods no llegan a RDS/S3/DynamoDB/Lambda.
docker network connect bridge lomax-eks-control-plane 2>/dev/null || true

# --- conectividad a FLOCI (IP real, no hostname: ver ops/generar-env-floci.sh) ---
bash ops/generar-env-floci.sh
source .env

kubectl -n lomax create configmap lomax-config \
  --from-literal=AWS_ENDPOINT_URL="http://$FLOCI_IP:4566" \
  --from-literal=PGHOST="$FLOCI_IP" \
  --from-literal=PGPORT="$RDS_PORT" \
  --from-literal=PGDATABASE=lomax \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n lomax create secret generic lomax-secret \
  --from-literal=PGUSER=lomax_admin \
  --from-literal=PGPASSWORD=lomax_pass_local \
  --dry-run=client -o yaml | kubectl apply -f -

# --- cargar en el clúster exactamente las imagenes publicadas en ECR (Etapa 6) ---
# kind load copia el mismo digest directo a containerd, sin depender de que los
# nodos resuelvan el hostname *.localhost:4566 simulado de FLOCI (ver guion de
# defensa, Etapa 7).
docker compose build proxy >/dev/null
kind load docker-image "$REGISTRY/lomax/backend:$GIT_SHA" --name lomax-eks
kind load docker-image "$REGISTRY/lomax/frontend:$GIT_SHA" --name lomax-eks
kind load docker-image lomax-proxy:local --name lomax-eks

sed "s|__BACKEND_IMAGE__|$REGISTRY/lomax/backend:$GIT_SHA|" k8s/backend-deployment.yaml | kubectl apply -f -
sed "s|__FRONTEND_IMAGE__|$REGISTRY/lomax/frontend:$GIT_SHA|" k8s/frontend-deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/backend-service.yaml -f k8s/frontend-service.yaml
kubectl apply -f k8s/proxy-deployment.yaml -f k8s/proxy-service.yaml

kubectl -n lomax rollout status deployment/backend
kubectl -n lomax rollout status deployment/frontend
kubectl -n lomax rollout status deployment/proxy

echo "esperando a que el proxy responda..."
for i in $(seq 1 20); do
  curl -sf http://localhost:8091/api/categorias >/dev/null 2>&1 && break
  sleep 1
done
curl -s http://localhost:8091/api/categorias
echo
echo "Etapa 7 (implementacion) lista. App en http://localhost:8091"
