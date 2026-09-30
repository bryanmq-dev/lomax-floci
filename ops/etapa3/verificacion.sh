#!/usr/bin/env bash
# Etapa 3 - Verificacion E3 (evidencia fotografica)
set -e
cd "$(dirname "$0")/../.."
eval "$(floci env)"

echo "--- subir original de prueba (1200x800) para producto_id=1 ---"
aws s3 cp /tmp/lomax-fotos/producto_1.jpg s3://lomax-originales/originales/1.jpg

echo "--- invocar Lambda y GUARDAR la salida (no basta el 200 de transporte) ---"
aws lambda invoke --function-name lomax-generar-miniatura \
  --payload '{"producto_id":"1","bucket_original":"lomax-originales","key_original":"originales/1.jpg"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-out-1.json
cat /tmp/lambda-out-1.json
echo
echo "campo ok (debe ser true):"
jq -r '.ok' /tmp/lambda-out-1.json

echo "--- listar ambos prefijos ---"
aws s3 ls s3://lomax-originales/originales/
aws s3 ls s3://lomax-miniaturas/miniaturas/

echo "--- recuperar y comparar dimensiones ---"
aws s3 cp s3://lomax-miniaturas/miniaturas/1.jpg /tmp/miniatura-1.jpg
python3 -c "
from PIL import Image
orig = Image.open('/tmp/lomax-fotos/producto_1.jpg').size
mini = Image.open('/tmp/miniatura-1.jpg').size
print('original:', orig, ' miniatura:', mini)
assert mini == (300, 200), f'esperaba (300, 200), obtuve {mini}'
print('dimensiones OK')
"

echo "--- get-item y comparar referencia ---"
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id": {"S": "1"}}'

echo "--- repetir invocacion: NO debe crear objetos extra ---"
ANTES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
aws lambda invoke --function-name lomax-generar-miniatura \
  --payload '{"producto_id":"1","bucket_original":"lomax-originales","key_original":"originales/1.jpg"}' \
  --cli-binary-format raw-in-base64-out /tmp/lambda-out-1b.json
DESPUES=$(aws s3 ls s3://lomax-miniaturas/miniaturas/ | wc -l)
echo "objetos antes=$ANTES despues=$DESPUES (deben ser iguales)"
test "$ANTES" = "$DESPUES"

echo "--- archivo invalido -> estado ERROR, sin miniatura valida ---"
echo "esto no es una imagen" > /tmp/invalido.txt
aws s3 cp /tmp/invalido.txt s3://lomax-originales/originales/999.jpg
aws lambda invoke --function-name lomax-generar-miniatura \
  --payload '{"producto_id":"999","bucket_original":"lomax-originales","key_original":"originales/999.jpg"}' \
  --cli-binary-format raw-in-base64-out /tmp/lambda-out-invalido.json
cat /tmp/lambda-out-invalido.json
echo
echo "campo ok (debe ser false):"
jq -r '.ok' /tmp/lambda-out-invalido.json
aws dynamodb get-item --table-name LomaxAtributos --key '{"producto_id": {"S": "999"}}'   # estado_imagen = ERROR
echo "no debe listar 999.jpg:"
aws s3 ls s3://lomax-miniaturas/miniaturas/ | grep 999 && echo "FALLO: no deberia existir" || echo "OK: no existe"
