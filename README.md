# Lomax SA — Catálogo de productos (TEMI, Primera Evaluación)

Sistema de registro y consulta de productos para Lomax SA, construido sobre el
entorno local **FLOCI** (emulador AWS en `http://localhost:4566`) y un clúster
Kubernetes real local (`kind`) haciendo de EKS.

Ver el plan completo, con cada etapa detallada (diseño, comandos de implementación,
comandos de verificación/evidencia y guion de defensa) en
[`docs/`](docs/) y [`ops/`](ops/).

## Mapa de etapas

| Etapa | Entregable | Carpeta de comandos | Estado |
|---|---|---|---|
| 0 — Setup | — | `ops/etapa0-setup.sh` | ✅ |
| 1 — Arquitectura | P2 | `ops/etapa1/` | ✅ |
| 2 — RDS y DynamoDB | P3 | `ops/etapa2/` | ✅ |
| 3 — S3 y Lambda | P4 | `ops/etapa3/` | ✅ |
| 4 — Backend y endpoints | P5 | `ops/etapa4/` | ✅ |
| 5 — Frontend / dashboard | P6 | `ops/etapa5/` | ✅ |
| 6 — Imágenes en ECR | P7 | `ops/etapa6/` | ✅ |
| 7 — Despliegue en EKS | P8 | `ops/etapa7/` | pendiente |
| Portafolio | P9 | este repo | pendiente |
| GitHub | P10 | — | pendiente |

## Conceptos (Producto 1)

Tablas de síntesis conceptual (Cloud Computing, Contenedores, Kubernetes, AWS), cada
una ligada a una decisión concreta del proyecto: [`docs/CONCEPTOS.md`](docs/CONCEPTOS.md).

## Arquitectura (Producto P2)

Diagrama con íconos oficiales AWS/Kubernetes:
[`docs/arquitectura/diagrama-arquitectura.png`](docs/arquitectura/diagrama-arquitectura.png)
(generado por [`docs/arquitectura/diagrama.py`](docs/arquitectura/diagrama.py)).

## Defensa

Guion de defensa por etapa, ligado a la tabla de criterios de evaluación:
[`docs/defensa/guion-defensa.md`](docs/defensa/guion-defensa.md).

## Cómo correr cada etapa

Cada `ops/etapaN/` trae dos scripts: `implementacion.sh` (levanta el recurso/código
de esa etapa) y `verificacion.sh` (comandos de evidencia — para screenshot). Se
ejecutan en orden; no se pasa a la etapa N+1 sin cerrar la N.
