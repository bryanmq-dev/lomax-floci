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
- `db/seed_categorias.sql` usa `ON CONFLICT (nombre) DO NOTHING`: correrlo dos veces no
  duplica categorías, es la misma idempotencia que luego se le exige a la carga de
  productos.
- **Hallazgo de infraestructura que vale la pena mostrar en la defensa**: el comando
  `floci restart` de la CLI (v0.2.3) tiene un defecto — no reutiliza el flag
  `--persist` con el que se levantó el contenedor originalmente, así que recrea un
  volumen Docker anónimo y **pierde todo el estado** (lo comprobamos de forma
  reproducible: además de los datos de Lomax, se perdieron recursos de 5 días de
  antigüedad de otro proyecto que compartía el mismo contenedor `floci`). El
  reinicio "sin borrar volúmenes" que pide el enunciado se logra en cambio con
  `floci stop && floci start --persist ~/.floci/data`, que sí reconecta el mismo
  directorio del host. `ops/etapa2/verificacion.sh` usa ese ciclo, no `floci restart`.
  Mostrar esto en la defensa demuestra que no solo se corrieron los comandos del
  enunciado, sino que se entendió *qué* estaba persistiendo (el volumen Docker) y
  *qué* no (el registro en memoria del contenedor recreado).
- El endpoint de RDS (`Endpoint.Address`/`Endpoint.Port`) cambia en cada ciclo de
  reinicio aunque los datos sobrevivan — por eso ningún script cachea esos valores
  más allá de un solo paso; siempre se vuelven a pedir con `describe-db-instances`.

## Etapa 3 — S3 y Lambda (5% S3 y Lambda + reto "localizar/descargar miniatura,
dimensiones, reintentos sin duplicados")

- La clave de salida `miniaturas/{producto_id}.jpg` es determinista por diseño (un
  producto = una foto): invocar la misma solicitud dos veces sobreescribe el mismo
  objeto, nunca crea uno nuevo. No es un `if exists` en código, es la clave misma la
  que impide el duplicado — se demuestra con el conteo de objetos antes/después.
- `lambda/index.mjs` nunca lanza una excepción sin controlar: siempre responde
  `{ ok, ... }`. Esto es deliberado — así el llamador (el CLI en esta etapa, el
  backend en la Etapa 4) decide con el contenido del JSON, sin depender de que AWS
  marque `FunctionError`. Mostrar el campo `ok` en la salida es justamente el "no
  basta con un código exitoso de transporte" que pide el enunciado.
- La validación de formato usa `Jimp.read()` + `getMIME()` — si el buffer no es un
  JPEG/PNG real, Jimp falla al decodificarlo (no se confía en la extensión del
  archivo), y eso dispara la rama de `estado_imagen = ERROR`.
- Explicar la proporción: 1200×800 → 300×200 porque el lado limitante es el ancho
  (300/1200 = 0.25, aplicado a 800 = 200) — `scaleToFit` hace exactamente eso.
- **Hallazgo de infraestructura, buen tema para la defensa**: al desplegar la Lambda
  se le puso explícitamente `AWS_ENDPOINT_URL=http://floci:4566`, pensando que el
  contenedor de ejecución podría resolver el nombre `floci` por DNS. Falló
  (`getaddrinfo ENOTFOUND floci`) porque el contenedor de floci corre en la red
  bridge por defecto de Docker, que no da resolución DNS por nombre de contenedor.
  Se depuró inyectando una función Lambda de diagnóstico que imprimía
  `process.env`, lo que reveló que **FLOCI ya inyecta automáticamente**
  `AWS_ENDPOINT_URL=http://localhost.floci.io:4566` (alcanzable) en cada Lambda —
  el propio override lo estaba rompiendo. La lambda de Lomax simplemente no fija
  esa variable y usa la que FLOCI ya provee.

<!-- Las secciones de Etapas 4-7 se agregan a medida que se implementa cada una. -->
