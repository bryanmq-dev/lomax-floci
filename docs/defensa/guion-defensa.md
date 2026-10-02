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
- **Hallazgo de infraestructura, con tres vueltas — buen tema para la defensa
  porque muestra depuración iterativa, no una respuesta memorizada**:
  1. Primer intento: se fijó `AWS_ENDPOINT_URL=http://floci:4566` a mano. Falló con
     `getaddrinfo ENOTFOUND floci`. Con una Lambda de diagnóstico que imprimía
     `process.env` se descubrió que FLOCI auto-inyecta su propio
     `AWS_ENDPOINT_URL=http://localhost.floci.io:4566` en cada Lambda — la
     solución en ese momento fue no fijar la variable y dejar la de FLOCI.
  2. Semanas después (tras varios `floci stop`/`start` durante las etapas de RDS y
     ECR), ese mismo `localhost.floci.io` dejó de resolver — el sintoma cambió a
     `ECONNREFUSED 127.0.0.1:4566` y hasta un timeout intentando resolver el
     nombre por DNS, probablemente porque esa resolución depende de DNS externo
     y algo en los reinicios lo rompió. Se confirmó revisando
     `AWS_LAMBDA_RUNTIME_API` en el entorno de la Lambda (cae en el rango de la
     red docker `floci-net`, `10.0.16.0/24`) y comparando contra
     `docker inspect floci`: el contenedor floci sí está en `floci-net` **y
     tiene ahí el nombre `floci` registrado en el DNS interno** (a diferencia de
     la red `bridge`, donde no resuelve nada). Con esa evidencia, fijar
     `AWS_ENDPOINT_URL=http://floci:4566` explícitamente pasó de "roto" a
     "correcto" — el primer intento no estaba mal en la idea, estaba probado en
     la red equivocada.
  3. Tercer episodio (tras un reinicio del sistema, no de floci): la red
     `floci-net` había desaparecido por completo — `docker inspect floci` ya no
     la listaba — así que `http://floci:4566` volvió a dar
     `getaddrinfo ENOTFOUND floci`, esta vez porque los contenedores de Lambda
     habían vuelto a caer en `bridge` (confirmado otra vez con
     `AWS_LAMBDA_RUNTIME_API`). Dos hostnames distintos ya habían demostrado
     romperse según qué red tocara en cada arranque. La solución definitiva:
     dejar de apostar a un hostname y usar la **IP real** de `floci` en su red
     `bridge` (`docker inspect floci --format
     '{{.NetworkSettings.Networks.bridge.IPAddress}}'`), que no depende de
     ningún DNS y se recalcula en cada corrida de
     `ops/etapa3/implementacion.sh`.
  4. Moraleja para la defensa: nunca se asumió que un fix anterior seguía
     vigente sin volver a probarlo — un hostname que "ya se había arreglado"
     se rompió dos veces más por razones distintas. La solución robusta no fue
     memorizar el valor correcto, fue dejar de depender de uno fijo.

## Etapa 4 — Backend y endpoints (5% Backend + reto "ejecutar endpoints, interpretar
respuestas, completar pendiente sin crear otro producto")

- Explicar el flujo PENDIENTE→PUBLICADO como una máquina de estados de dos pasos:
  `POST /productos` crea el registro base; `POST /productos/:id/imagen` es el
  **único** camino que publica, y solo lo hace tras confirmar que la Lambda devolvió
  `ok:true` (Etapa 3) y que DynamoDB tiene el ítem con atributos. Así ningún producto
  llega al catálogo sin fotografía, que era justo el problema original de Lomax.
- `reprocesar` nunca crea un `producto_id` nuevo: reusa `imagen_original_key` ya
  guardado en DynamoDB (Etapa 3) y vuelve a invocar la misma Lambda con esa clave —
  por eso la miniatura resultante tampoco duplica objetos en S3 (misma clave
  determinista de Etapa 3).
- Cada 502/503 devuelve `{"error", "paso_fallido": "s3"|"lambda"|"dynamodb"}` — es la
  "respuesta que identifica el paso fallido" que pide el enunciado, sin necesidad de
  revisar logs para saber qué componente falló.
- El 413 lo produce `multer` solo (limite de 5MB en `memoryStorage`), no un chequeo
  manual del tamaño del buffer — Express/multer ya resuelven eso.
- **Dos bugs reales encontrados al probar el backend en su propio contenedor (no en
  el host), buen contraste para la defensa entre "funciona en mi máquina" y
  "funciona en un contenedor aislado"**:
  1. El cliente AWS SDK fallaba con `Region is missing` porque solo se pasó
     `AWS_ENDPOINT_URL` al contenedor, sin `AWS_ACCESS_KEY_ID` /
     `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` — variables que en el host las pone
     `eval $(floci env)`, pero que un contenedor nuevo no hereda solo.
  2. Igual que con la Lambda en Etapa 3: el contenedor del backend vive en su propia
     red de Docker, y FLOCI corre en la red `bridge` por defecto (sin DNS por
     nombre). Se resolvió conectando el contenedor a esa misma red y usando la IP
     real de `floci` (`ops/generar-env-floci.sh`), en vez de un hostname que nunca
     iba a resolver.

## Etapa 5 — Frontend y dashboard (5% Frontend + reto "registrar y consultar desde el
dashboard, demostrar que los datos provienen de los servicios")

- Las tres vistas son HTML/JS planos sin build step: `catalogo.html` y
  `detalle.html` hacen `fetch('/api/...')` en el `<script>` de la propia página, así
  que cualquiera puede abrir las herramientas de desarrollador y ver la llamada real
  — no hay datos incrustados en el HTML.
- Refrescar el navegador repite el `fetch`, por eso "conservar la información al
  actualizar" no necesitó código propio: el estado siempre viene del servidor
  (RDS/DynamoDB/S3 vía el backend), nunca de `localStorage` ni de estado de un
  framework.
- El panel de reintento en `registrar.html` (`POST /productos/:id/imagen` o
  `POST /productos/:id/reprocesar`) reusa el `producto_id` que ya devolvió la API —
  es la misma garantía de "no duplicar" que se probó por CLI en la Etapa 4, ahora
  expuesta en la interfaz.
- **Otro bug de red real, en la misma familia que el de la Lambda (Etapa 3) y el
  backend aislado (Etapa 4)**: al conectar el backend a la red `bridge` de floci
  *desde* `docker-compose.yml`, Docker Compose lo rechazó
  (`network-scoped aliases are only supported for user-defined networks`) — Compose
  siempre intenta asignarle un alias de red al servicio, y la red `bridge` por
  defecto no admite alias. La solución fue no declarar esa red en compose y
  conectarla aparte con `docker network connect bridge <contenedor>` justo después
  de `docker compose up` (ver `ops/etapa5/implementacion.sh`). Buen ejemplo para la
  defensa de que "conectividad con FLOCI" no es un detalle trivial: cada pieza nueva
  (Lambda, backend suelto, backend en compose, y más adelante los Pods de Etapa 7)
  tuvo que resolver el mismo problema de red de una forma distinta.
- **Bug de configuración (no de red) encontrado despues de entregar la etapa**: un
  archivo de ~2Mb (bien por debajo del límite de 5Mb que exige el backend) se
  rechazaba con 413 igual. La causa no era `multer` (su límite sí es 5Mb): era
  `proxy/nginx.conf`, que nunca fijó `client_max_body_size` — nginx trae por
  defecto **1Mb**, y cortaba la subida antes de que llegara al backend. Se agregó
  `client_max_body_size 6m;` a nivel de `server` (un poco por encima de los 5Mb
  reales para no clipear el overhead del multipart). Buen recordatorio para la
  defensa: un límite "de la aplicación" puede estar duplicado, sin querer, en la
  capa de proxy — hay que probar el límite real de punta a punta, no solo el
  código del backend.

## Etapa 6 — Imágenes en ECR (5% ECR + reto "push, digest remoto, pull, ejecución")

- Cada imagen se etiqueta con `$(git rev-parse --short HEAD)`, no `latest` — vincula
  la imagen publicada con el commit exacto de entrega, como pide el enunciado.
- El `imageDigest` que devuelve `describe-images` es el que trae de vuelta el
  `docker pull` posterior: se borra la copia local antes de traerla de nuevo,
  así que no hay manera de que el pull esté usando una copia en caché.
- La imagen recuperada se corre de verdad (no solo se descarga) y se le pega un
  `curl` real, para demostrar que es la aplicación entregada y no un contenedor vacío.
- **El hallazgo de infraestructura más grande del proyecto, buen cierre para la
  defensa de este bloque**: `docker login`/`push`/`pull` contra el registro ECR de
  FLOCI fallaban con `503 Service Unavailable`, aunque la API de control
  (`create-repository`, `describe-repositories`, `GetAuthorizationToken`) funcionaba
  perfecto. La causa: FLOCI corre el *registry* real de Docker que respalda a ECR en
  un contenedor aparte (`floci-ecr-registry`), enlazado al contenedor principal
  `floci` mediante una tercera red docker (`floci-net`, con DNS interno) que el
  contenedor principal **no tenía conectada** después de los reinicios de la Etapa
  2. La API de control no pasa por esa red (por eso funcionaba), pero el tráfico
  real de push/pull sí. Se diagnosticó comparando las redes de ambos contenedores
  (`docker inspect ... NetworkSettings.Networks`) y se corrigió con
  `docker network connect floci-net floci` — ahora ese chequeo vive en
  `ops/etapa0-setup.sh` para que no vuelva a pasar. Es el tercer bug de
  conectividad de FLOCI que aparece en el proyecto (Lambda en Etapa 3, backend en
  Etapas 4 y 5, ahora ECR): cada servicio nuevo de FLOCI resultó tener su propia
  forma de enrutar el tráfico real, distinta de la API de control.

## Etapa 7 — Despliegue en EKS (5% EKS + reto "relacionar imágenes con ECR, escalar,
reemplazo sin pérdida")

- `kubectl get pods -o jsonpath='...image'` muestra literalmente la URI de ECR con
  el tag del commit (Etapa 6) en el campo `image:` de cada Pod. No es casualidad:
  `kind load docker-image` cargó ese digest exacto directo a los nodos, así que el
  Pod corre el mismo binario que quedó publicado en ECR, sin volver a construirlo.
- El header `X-Instancia` (agregado en el backend desde la Etapa 4, `server.mjs`) es
  literalmente el `HOSTNAME` del Pod — en Kubernetes eso es el nombre del Pod. Seis
  `curl` seguidos contra el mismo Service reparten las respuestas entre los 3 Pods:
  esa es la evidencia de que el Service realmente balancea, no solo que "hay 3
  Pods Ready".
- Al borrar un Pod, el nuevo tiene un UID distinto (Kubernetes nunca reutiliza UID)
  y el catálogo nunca deja de responder — porque el Deployment ya tenía 2 réplicas
  sanas cubriendo mientras se agenda el reemplazo.
- El producto registrado desde EKS sobrevive a borrar **todos** los Pods del
  backend a la vez: la prueba definitiva de que el estado vive en RDS/DynamoDB/S3
  (FLOCI), no en el Pod. Esto es autorrecuperación real, no solo "el número de
  réplicas volvió a 3".
- **El cuarto y último bug de conectividad de FLOCI del proyecto (mismo patrón que
  Lambda, backend suelto, backend en compose y ECR)**: el nodo de kind vive en su
  propia red docker (`kind`), separada de la red de FLOCI (`bridge`). Se probó
  primero con un Pod de diagnóstico (`kubectl run test-conn ...`) que confirmó
  `UNREACHABLE` hacia `10.0.7.2:4566`; la solución fue la misma que en la Etapa 5:
  `docker network connect bridge lomax-eks-control-plane`. Una vez el *nodo* tiene
  la ruta, los Pods la heredan vía el NAT que kindnet ya configura para salir del
  clúster — no hizo falta tocar el CNI.
- Nota honesta para la defensa: `aws eks create-cluster` en FLOCI **nunca se llama**
  — solo devolvería metadata falsa (`aws eks list-clusters` demostrado vacío en la
  Etapa 1). El clúster real es `kind`, y eso se explica así de directo, no se
  esconde.

## Cierre transversal (útil para "las respuestas conceptuales deben relacionarse
con las decisiones implementadas")

El proyecto encontró **cuatro bugs de conectividad de FLOCI**, todos con la misma
forma: la API de *control* (crear recursos, listar, autenticar) funciona siempre;
el tráfico de *datos* real (ejecutar la Lambda, conectar Postgres, hacer push/pull
de ECR, o que un Pod llegue a RDS) necesita que quien lo genera esté en la red
docker correcta. Cada etapa lo resolvió con la misma idea (conectar la red que
falta, o usar la IP real en vez de un hostname que no resuelve), aplicada al
contexto de esa etapa. Es el hilo conductor de la defensa técnica de las 7 etapas.
