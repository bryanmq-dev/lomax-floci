#!/usr/bin/env bash
# Etapa 1 - Verificacion E1 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."

# Captura 1: el diagrama completo con iconos oficiales
xdg-open docs/arquitectura/diagrama-arquitectura.png

# Captura 2: FLOCI corriendo (contrasta el diagrama con lo realmente desplegado)
floci status

# Captura 3: los 6 servicios AWS que aparecen en el diagrama, habilitados en FLOCI
floci services | grep -E "^\s*✓\s+(rds|dynamodb|s3|lambda|ecr|eks)\b"
