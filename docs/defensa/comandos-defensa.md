# Comandos para la defensa (los 6 retos)

Todo asume `eval $(floci env)` ya corrido (sin `--region`/`--endpoint-url`, FLOCI
sigue en el puerto 4566). Los IDs de ejemplo (`producto_id=26`, versión ECR
`a807c18`) son datos reales que ya existen en el sistema — al momento de defender,
cualquier `producto_id` publicado sirve igual.

---

## 1. Localizar y descargar la miniatura desde S3, comprobar dimensiones, repetir
   la invocación de Lambda sin duplicados

```bash
# localizar: la clave es determinista, {producto_id}.jpg en cada bucket
aws s3 ls s3://lomax-originales/originales/ | grep 26
aws s3 ls s3://lomax-miniaturas/miniaturas/ | grep 26

# descargar ambas y comparar dimensiones
aws s3 cp s3://lomax-originales/originales/26.jpg /tmp/original-26.jpg
aws s3 cp s3://lomax-miniaturas/miniaturas/26.jpg /tmp/miniatura-26.jpg
python3 -c "
from PIL import Image
print('original :', Image.open('/tmp/original-26.jpg').size)
print('miniatura:', Image.open('/tmp/miniatura-26.jpg').size)
"

# repetir la invocacion de Lambda con el MISMO producto_id/clave
ANTES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
aws lambda invoke --function-name lomax-generar-miniatura \
  --payload '{"producto_id":"26","bucket_original":"lomax-originales","key_original":"originales/26.jpg"}' \
  --cli-binary-format raw-in-base64-out /tmp/lambda-out.json
cat /tmp/lambda-out.json   # campo "ok":true confirma exito real, no solo transporte
DESPUES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
echo "objetos antes=$ANTES despues=$DESPUES"   # deben ser iguales

# confirmar que DynamoDB apunta exactamente a lo que se acaba de descargar
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id":{"S":"26"}}'
```

**Qué explicar:** la clave `miniaturas/{producto_id}.jpg` es el mecanismo de
idempotencia — no hay un `if exists` en código, la clave misma impide el
duplicado. El campo `"ok":true` del JSON de salida es la prueba de que la Lambda
ejecutó bien de verdad, no solo que el transporte HTTP fue 200.

---

## 2. Ejecutar endpoints con datos válidos e inválidos, interpretar respuestas,
   completar un pendiente sin crear otro producto

```bash
BASE=http://localhost:8090/api   # o :8091 si se demuestra desde EKS

# valido
curl -s -X POST $BASE/productos -H 'Content-Type: application/json' -d '{
  "codigo":"DEF-001","nombre":"Producto defensa","precio":12.5,"categoria_id":1,
  "atributos":{"conexion":"USB","distribucion":"Español"}}' | tee /tmp/d1.json | jq
ID=$(jq -r .producto_id /tmp/d1.json)

# invalido: campo obligatorio faltante -> 400
curl -s -o /dev/null -w "400 esperado -> HTTP %{http_code}\n" -X POST $BASE/productos \
  -H 'Content-Type: application/json' -d '{"nombre":"sin codigo"}'

# invalido: codigo duplicado -> 409
curl -s -o /dev/null -w "409 esperado -> HTTP %{http_code}\n" -X POST $BASE/productos \
  -H 'Content-Type: application/json' -d '{"codigo":"DEF-001","nombre":"x","precio":1,"categoria_id":1}'

# invalido: archivo >5Mb -> 413
head -c 6000000 /dev/urandom > /tmp/grande.jpg
curl -s -o /dev/null -w "413 esperado -> HTTP %{http_code}\n" -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/grande.jpg"

# invalido: formato no permitido -> 415
echo "no es imagen" > /tmp/invalido.txt
curl -s -o /dev/null -w "415 esperado -> HTTP %{http_code}\n" -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/invalido.txt"

# ahora si: publica el MISMO producto_id (no crea uno nuevo)
curl -s -X POST $BASE/productos/$ID/imagen -F "imagen=@/tmp/lomax-fotos/producto_1.jpg" | jq

# "completar un pendiente sin crear otro producto": reprocesar reusa producto_id
curl -s -X POST $BASE/productos/$ID/reprocesar | jq   # mismo producto_id en la respuesta

curl -s $BASE/productos/$ID | jq        # detalle + estado
curl -s -o /dev/null -w "404 esperado -> HTTP %{http_code}\n" $BASE/productos/999999
```

**Qué explicar:** cada código de error mapea a una causa exacta (400 validación,
409 UNIQUE de Postgres, 413 límite de multer, 415 MIME no permitido). `reprocesar`
nunca genera un `producto_id` nuevo — opera sobre la clave ya guardada en S3.

---

## 3. Registrar y consultar un producto desde el dashboard, demostrar que los
   datos provienen de los servicios

Esto se hace en el navegador (`http://localhost:8090/registrar.html`), pero la
*demostración* de que no son datos falsos es con AWS CLI, contra el
`producto_id` que acabás de crear en pantalla:

```bash
ID=<el producto_id que mostro el formulario>

# RDS: la fila existe con el mismo codigo/precio que se tipeo
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text)
PGPASSWORD=lomax_pass_local psql -h "$RDS_HOST" -p "$RDS_PORT" -U lomax_admin -d lomax \
  -c "SELECT * FROM productos WHERE producto_id=$ID;"

# DynamoDB: los atributos que se tipearon en el form
aws dynamodb get-item --table-name LomaxAtributos --key "{\"producto_id\":{\"S\":\"$ID\"}}"

# S3: la miniatura que el catalogo esta mostrando es este objeto, no un placeholder
aws s3 cp s3://lomax-miniaturas/miniaturas/$ID.jpg /tmp/verif-dashboard.jpg
# comparar contra lo que devuelve el propio endpoint que usa el frontend:
curl -s -o /tmp/verif-endpoint.jpg http://localhost:8090/api/productos/$ID/imagen
diff /tmp/verif-dashboard.jpg /tmp/verif-endpoint.jpg && echo "identicos: el frontend sirve el objeto real de S3"
```

**Qué explicar:** refrescar el navegador repite el `fetch`, no hay estado
guardado en el cliente — por eso los datos sobreviven a un refresh: siempre
vienen de RDS/DynamoDB/S3 vía la API, nunca de `localStorage`.

---

## 4. Mostrar push, digest remoto, pull y ejecución de una imagen recuperada
   desde ECR

```bash
REGISTRY="000000000000.dkr.ecr.us-east-1.localhost:4566"
GIT_SHA=$(cat ~/lomax-floci/.ultima-version-ecr)   # version realmente publicada
echo "version: $GIT_SHA"

# push (ya hecho, mostrar el resultado/logs si se repite)
docker push "$REGISTRY/lomax/backend:$GIT_SHA"

# digest remoto
aws ecr describe-images --repository-name lomax/backend \
  --query "imageDetails[?imageTags[0]=='$GIT_SHA'].imageDigest" --output text

# pull "limpio": borrar la copia local y traerla de nuevo
docker rmi "$REGISTRY/lomax/backend:$GIT_SHA"
docker pull "$REGISTRY/lomax/backend:$GIT_SHA"
docker inspect "$REGISTRY/lomax/backend:$GIT_SHA" --format '{{index .RepoDigests 0}}'
# el digest debe coincidir con el que devolvio describe-images arriba

# ejecucion real de la imagen recuperada
docker run -d --name demo-ecr -p 4099:4000 --network bridge \
  -e AWS_ENDPOINT_URL=http://floci:4566 -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-east-1 -e AWS_REGION=us-east-1 \
  -e PGHOST=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Address' --output text) \
  -e PGPORT=$(aws rds describe-db-instances --db-instance-identifier lomax-db --query 'DBInstances[0].Endpoint.Port' --output text) \
  -e PGUSER=lomax_admin -e PGPASSWORD=lomax_pass_local -e PGDATABASE=lomax \
  -e BUCKET_ORIGINALES=lomax-originales -e BUCKET_MINIATURAS=lomax-miniaturas \
  -e TABLE_ATRIBUTOS=LomaxAtributos -e LAMBDA_FUNCTION=lomax-generar-miniatura \
  "$REGISTRY/lomax/backend:$GIT_SHA"
curl -s http://localhost:4099/categorias   # responde con datos reales -> es la app entregada
docker rm -f demo-ecr
```

**Qué explicar:** el tag es el commit exacto (`git rev-parse --short HEAD`), no
`latest` — trazabilidad directa entre lo publicado y el código entregado. El
`docker rmi` antes del `pull` es lo que prueba que no se está reusando cache local.

---

## 5. Relacionar las imágenes de los Pods con ECR, escalar a 3 réplicas,
   reemplazo de un Pod sin pérdida de productos

```bash
# relacion Pod <-> ECR: el campo image: es literalmente la URI publicada
kubectl -n lomax get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  ->  "}{.spec.containers[0].image}{"\n"}{end}'

# cruzar el digest del Pod contra el de ECR (deben coincidir: es el mismo binario)
aws ecr describe-images --repository-name lomax/backend --query 'imageDetails[0].imageDigest' --output text

# escalar 1 -> 3
kubectl -n lomax scale deployment/backend --replicas=3
kubectl -n lomax rollout status deployment/backend
kubectl -n lomax get pods -l app=backend

# balanceo real: header X-Instancia = nombre del Pod que respondio
for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null http://localhost:8091/api/categorias | grep -i x-instancia; done

# reemplazo de un Pod sin perder productos
curl -s http://localhost:8091/api/productos | jq 'length'          # contar ANTES
POD=$(kubectl -n lomax get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
UID_ANTES=$(kubectl -n lomax get pod "$POD" -o jsonpath='{.metadata.uid}')
kubectl -n lomax delete pod "$POD"
kubectl -n lomax rollout status deployment/backend
NUEVO=$(kubectl -n lomax get pods -l app=backend --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n lomax get pod "$NUEVO" -o jsonpath='{.metadata.uid}'    # distinto de $UID_ANTES
curl -s http://localhost:8091/api/productos | jq 'length'          # cuenta DESPUES: igual que antes
```

**Qué explicar:** `kind load docker-image` cargó el mismo digest publicado en
ECR directo a los nodos — por eso el campo `image:` del Pod y el digest de ECR
coinciden exactamente, sin volver a construir nada. El conteo de productos
antes/después de borrar un Pod es la prueba de que el estado vive en
RDS/DynamoDB/S3 (FLOCI), no en el Pod — es autorrecuperación real, no solo
"volvió a haber 3 Pods".

---

## Hilo conductor si preguntan por decisiones conceptuales

Cada uno de los 6 retos toca la misma idea de fondo: la API de *control* de FLOCI
(crear, listar, autenticar) siempre funcionó; el tráfico de *datos* real
necesitó, en cada etapa, resolver a qué red docker conectarse o qué IP/hostname
usar (ver `docs/defensa/guion-defensa.md`, sección "Cierre transversal"). Es el
argumento que conecta Fundamentación (P1) con cada entregable técnico.
