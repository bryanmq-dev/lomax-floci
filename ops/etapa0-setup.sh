#!/usr/bin/env bash
# Etapa 0 - Setup base (no es entregable propio, deja el entorno listo)
set -e
cd "$(dirname "$0")/.."   # raiz del repo lomax-floci

floci status                      # confirma que el contenedor FLOCI esta arriba
eval "$(floci env)"                # bash; en fish usar: eval (floci env)
aws sts get-caller-identity        # smoke test contra FLOCI

python3 -m venv .venv
.venv/bin/pip install --quiet diagrams

echo "Falta instalar graphviz a nivel de sistema (una sola vez):"
echo "  sudo pacman -S --needed graphviz"
