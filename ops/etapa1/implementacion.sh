#!/usr/bin/env bash
# Etapa 1 - Diseno de la arquitectura (Entregable P2)
set -e
cd "$(dirname "$0")/../.."   # raiz del repo lomax-floci

source .venv/bin/activate
python3 docs/arquitectura/diagrama.py
echo "Diagrama generado: docs/arquitectura/diagrama-arquitectura.png"
