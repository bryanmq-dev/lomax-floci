# Producto 1 — Síntesis conceptual (SABER CONOCER)

Cada definición cierra con **→ Lomax:** la decisión concreta del proyecto que ese
concepto justifica, para poder defenderlo sin recitar teoría suelta.

## Cloud Computing

| Concepto | Definición |
|---|---|
| Características del Cloud Computing | Autoservicio bajo demanda, acceso amplio por red, *pooling* de recursos entre varios consumidores, elasticidad rápida y medición del servicio (pago/consumo por uso). → Lomax: FLOCI expone RDS/DynamoDB/S3/Lambda/ECR/EKS como servicios que se piden por API, sin aprovisionar servidores a mano. |
| Escalabilidad vertical y horizontal | Vertical: dar más CPU/RAM a una misma instancia (techo físico, requiere reinicio). Horizontal: agregar más instancias idénticas detrás de un balanceador (sin techo práctico, tolera fallos). → Lomax: el backend escala horizontal en Etapa 7 (`kubectl scale deployment/backend --replicas=3`), no se le agrandan recursos a un único Pod. |
| Virtualización | Abstracción de hardware físico en máquinas/entornos lógicos independientes (VMs, o contenedores como virtualización a nivel de SO) que comparten el mismo host físico. → Lomax: cada servicio (frontend, backend, proxy) corre en su propio contenedor Docker sobre el mismo host, aislados entre sí. |
| IaaS, PaaS y SaaS | IaaS: se gestiona infraestructura cruda (cómputo, red, storage), el proveedor da el hardware. PaaS: el proveedor gestiona el runtime/SO, uno solo despliega código. SaaS: software completo listo para usar. → Lomax: RDS/DynamoDB/S3/Lambda son PaaS (no administramos SO ni parches del motor de base de datos); EKS/kind es más cercano a IaaS orquestado (administramos Pods, pero no el kernel del nodo). |
| Tipos de nube | Pública (proveedor comparte infraestructura entre clientes), privada (infraestructura dedicada a una organización), híbrida (combinación) y comunitaria. → Lomax: FLOCI es una nube privada/local — simula la nube pública de AWS pero corre 100% en la máquina del equipo, sin costo ni dependencia de internet para los servicios emulados. |
| Ventajas y limitaciones de los servicios cloud | Ventajas: elasticidad, pago por uso, menor carga operativa, alta disponibilidad gestionada. Limitaciones: dependencia del proveedor (*vendor lock-in*), costos variables difíciles de predecir, latencia de red, superficie de seguridad compartida. → Lomax: se aprovechan las ventajas (no administrar el motor de Postgres) asumiendo la limitación de que, en FLOCI, la "alta disponibilidad" es simulada, no real. |

## Contenedores

| Concepto | Definición |
|---|---|
| Concepto de contenedor | Unidad de software que empaqueta código y sus dependencias, ejecutándose aislada mediante *namespaces* y *cgroups* del kernel, compartiendo el mismo kernel del host (a diferencia de una VM). → Lomax: backend, frontend y proxy son 3 contenedores independientes, livianos y reproducibles. |
| Imagen y contenedor | La imagen es el artefacto inmutable (capas de filesystem + metadata) construido una vez; el contenedor es una instancia en ejecución de esa imagen, con su propio estado efímero. → Lomax: `lomax-backend:local` es la imagen; cada `docker run`/Pod que la usa es un contenedor distinto. |
| Dockerfile | Receta declarativa de pasos (`FROM`, `COPY`, `RUN`, `CMD`) para construir una imagen de forma reproducible. → Lomax: `backend/Dockerfile` y `frontend/Dockerfile` fijan exactamente qué corre en ECR y en EKS, sin pasos manuales. |
| Redes | Docker crea redes virtuales (bridge por defecto) que permiten a los contenedores resolverse por nombre de servicio y aislarse del resto del host. → Lomax: `docker-compose.yml` pone proxy/frontend/backend en la misma red bridge; para llegar a FLOCI (fuera de esa red) se usa `host.docker.internal`. |
| Volúmenes | Mecanismo para persistir o compartir datos fuera del ciclo de vida efímero de un contenedor. → Lomax: la persistencia real vive en RDS/DynamoDB/S3 (FLOCI), no en volúmenes de los contenedores de aplicación — por eso un contenedor se puede recrear sin perder productos. |
| Docker compose | Herramienta declarativa (YAML) para levantar varios contenedores relacionados (servicios, redes, variables) con un solo comando. → Lomax: `docker compose up -d` levanta proxy+frontend+backend integrados para la Etapa 5. |
| Ventajas y limitaciones de Docker | Ventajas: reproducibilidad ("funciona igual en mi máquina y en producción"), arranque rápido, densidad alta por host. Limitaciones: comparte kernel con el host (aislamiento menor que una VM), gestión de estado/persistencia requiere diseño explícito. → Lomax: se aprovecha la reproducibilidad para que el mismo `Dockerfile` corra igual en local, en ECR y en EKS. |

## Kubernetes

| Concepto | Definición |
|---|---|
| Arquitectura básica | Un *control plane* (API server, scheduler, controller manager, etcd) decide y guarda el estado deseado; los *nodos* worker ejecutan los Pods mediante el *kubelet* y el *container runtime*. → Lomax: kind crea ambos roles (control-plane + worker) como contenedores Docker, simulando el clúster EKS. |
| Cluster | Conjunto de nodos (control plane + workers) administrados como una sola unidad por Kubernetes. → Lomax: el clúster se llama `lomax-eks` (kind), namespace `lomax`. |
| Pod | Unidad mínima desplegable: uno o más contenedores que comparten red y almacenamiento, agendados juntos en un nodo. → Lomax: cada réplica del backend es un Pod con un único contenedor `lomax-backend`. |
| Deployment | Controlador declarativo que mantiene N réplicas de un Pod, gestiona *rollouts* y reemplaza Pods que fallan. → Lomax: `backend-deployment.yaml` define `replicas` y la imagen de ECR a correr. |
| Service | Abstracción de red estable (IP/DNS interno) que balancea tráfico entre los Pods que cumplen un `selector`, desacoplando al cliente de qué Pod concreto responde. → Lomax: `backend-service.yaml` es el punto fijo que usa el proxy para llegar a cualquiera de las 3 réplicas. |
| Escalamiento | Cambiar el número de réplicas de un Deployment (manual vía `kubectl scale` o automático vía HPA) para absorber más carga. → Lomax: Etapa 7 escala el backend de 1 a 3 réplicas y lo demuestra con solicitudes atendidas por Pods distintos. |
| Autorecuperación | El controlador del Deployment detecta un Pod caído/eliminado y agenda uno nuevo automáticamente para volver al número deseado de réplicas. → Lomax: al borrar un Pod del backend, Kubernetes crea un reemplazo con nuevo UID sin intervención manual y sin perder datos (que viven fuera del Pod). |

## AWS (servicios usados, vía FLOCI)

| Concepto | Definición |
|---|---|
| RDS | Servicio gestionado de bases de datos relacionales (Postgres/MySQL/etc.): provisión, parches y networking gestionados por el proveedor. → Lomax: `lomax-db` (Postgres 16) guarda `categorias` y `productos`, con las restricciones (`UNIQUE`, `CHECK`, `FOREIGN KEY`) que Lomax necesita para rechazar datos inválidos a nivel de motor. |
| DynamoDB | Base de datos NoSQL clave-valor/documento, sin esquema fijo entre ítems, pensada para acceso de baja latencia por clave. → Lomax: `LomaxAtributos` guarda atributos variables por categoría (un teclado y una pantalla no comparten forma) y el estado de la imagen, usando `producto_id` como clave de partición. |
| S3 | Almacenamiento de objetos, direccionado por *bucket* + *key*, sin jerarquía real de carpetas (los prefijos la simulan). → Lomax: `lomax-originales` y `lomax-miniaturas` separan la foto subida de la miniatura generada, con clave determinista `{producto_id}.jpg`. |
| Lambda | Cómputo *serverless*: código que se ejecuta bajo demanda (invocación síncrona o por evento), sin administrar servidores, facturado por invocación/duración. → Lomax: `lomax-generar-miniatura` reduce la foto a 300×300 cuando se invoca, sin un servidor de procesamiento de imágenes corriendo 24/7. |
| ECR | Registro de imágenes Docker privado, integrado con IAM, para versionar y distribuir las imágenes propias. → Lomax: `lomax/backend` y `lomax/frontend` publican las imágenes que luego correrán en EKS, etiquetadas con el commit de entrega. |
| EKS | Servicio gestionado de Kubernetes: el proveedor administra el control plane, el equipo administra las cargas de trabajo (Pods, Deployments, Services). → Lomax: en este entorno académico, FLOCI solo simula la API de control de EKS; el clúster de cómputo real que ejecuta los Pods es `kind`, explicado así abiertamente en la defensa. |
