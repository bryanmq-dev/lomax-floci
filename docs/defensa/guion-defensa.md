# Guion de defensa por etapa

Cada bloque está anclado a su fila de la tabla de Criterios de Evaluación y al reto
correspondiente de la sección "Defensa del proyecto" del enunciado. Se completa una
sección por etapa, en el mismo orden en que se implementa.

## Etapa 1 — Arquitectura (5% Arquitectura + reto "Explicar el diagrama")

- Recorrer el diagrama en el mismo orden que el flujo real de una request: usuario →
  proxy (única puerta de entrada, puerto 8090) → frontend estático o `/api` → backend.
- Señalar que RDS y DynamoDB quedan **fuera** de los Pods de Kubernetes — viven en el
  contenedor `floci`, no en el clúster de cómputo — porque el enunciado de Etapa 7
  exige persistencia externa a los Pods de la aplicación.
- Ser explícito sobre la pieza que suele generar dudas: **EKS real de AWS no se
  invoca en absoluto.** FLOCI solo expone la API de *control* de EKS (`aws eks
  list-clusters` responde vacío, no agenda cómputo). El clúster que de verdad corre
  los Pods es `kind` (Kubernetes real en Docker), llamado `lomax-eks`. Esto no es un
  atajo oculto: se dice así de frente, porque es la única forma de demostrar
  escalado y autorrecuperación *reales* que pide la Etapa 7 — FLOCI no podría
  hacerlo.
- Cerrar contrastando el diagrama contra el sistema desplegado de verdad: `kubectl
  get all -n lomax` y `floci services`, una vez que todas las etapas estén hechas
  (este contraste final se hace en la defensa oral, no antes).

## Etapa 2 — Persistencia con RDS y DynamoDB (5% Persistencia + reto "rechazo de código
duplicado, atributos variables, persistencia tras reinicio")

- Mostrar `CHECK (precio >= 0)` y `UNIQUE(codigo)` en `db/schema.sql` como la causa
  exacta del rechazo: es el motor Postgres protegiendo la integridad, no una validación
  de aplicación que se pueda saltar.
- Explicar por qué la relación RDS↔DynamoDB se verifica en la API comparando
  `producto_id` como string, y no con una *foreign key* real entre servicios: son dos
  sistemas de persistencia independientes, tal como exige el enunciado ("la relación
  entre bases se verificará desde la API").
- Después de `floci restart`, señalar que RDS y DynamoDB no perdieron datos porque el
  contenedor conserva su volumen — la persistencia no depende de que el backend (que
  todavía no existe en esta etapa) esté arriba.
- `db/seed_categorias.sql` usa `ON CONFLICT (nombre) DO NOTHING`: correrlo dos veces no
  duplica categorías, es la misma idempotencia que luego se le exige a la carga de
  productos.

<!-- Las secciones de Etapas 3-7 se agregan a medida que se implementa cada una. -->
