#!/usr/bin/env bash
# Etapa 0 - Setup base (no es entregable propio, deja el entorno listo)
set -e
cd "$(dirname "$0")/.."   # raiz del repo lomax-floci

# IMPORTANTE: floci start SIN --persist usa un volumen Docker anonimo. Cualquier
# "floci restart" posterior borra TODO el estado (RDS, DynamoDB, ECR, de este
# proyecto y de cualquier otro que comparta el mismo contenedor floci). Por eso
# el contenedor se levanta (o releva) siempre con --persist apuntando a un
# directorio real del host. Detalle completo en docs/defensa/guion-defensa.md.
if floci status >/dev/null 2>&1; then
  MOUNT_SRC=$(docker inspect floci --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}')
  case "$MOUNT_SRC" in
    /home/*|/Users/*|/root/*|/mnt/*|/data/*)
      echo "floci ya esta corriendo con persistencia real ($MOUNT_SRC)." ;;
    *)
      echo "floci esta corriendo con un volumen anonimo ($MOUNT_SRC) -> sin persistencia real."
      floci stop
      floci start --persist ~/.floci/data
      ;;
  esac
else
  floci start --persist ~/.floci/data
fi
floci wait

eval "$(floci env)"                # bash; en fish usar: eval (floci env)
aws sts get-caller-identity        # smoke test contra FLOCI

python3 -m venv .venv
.venv/bin/pip install --quiet diagrams

echo "Falta instalar graphviz a nivel de sistema (una sola vez):"
echo "  sudo pacman -S --needed graphviz"
