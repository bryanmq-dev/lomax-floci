#!/usr/bin/env bash
# Etapa 6 - Publicacion de imagenes en ECR (Entregable P7)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci
eval "$(floci env)"

REGISTRY="000000000000.dkr.ecr.us-east-1.localhost:4566"
GIT_SHA=$(git rev-parse --short HEAD)

aws ecr describe-repositories --repository-names lomax/backend >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name lomax/backend >/dev/null
aws ecr describe-repositories --repository-names lomax/frontend >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name lomax/frontend >/dev/null

aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

docker compose build backend frontend

docker tag lomax-backend:local  "$REGISTRY/lomax/backend:$GIT_SHA"
docker tag lomax-frontend:local "$REGISTRY/lomax/frontend:$GIT_SHA"

docker push "$REGISTRY/lomax/backend:$GIT_SHA"
docker push "$REGISTRY/lomax/frontend:$GIT_SHA"

echo "$GIT_SHA" > .ultima-version-ecr
echo "Etapa 6 (implementacion) lista. Version publicada: $GIT_SHA"
