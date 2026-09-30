// Etapa 3: genera la miniatura de un producto (<=300x300, proporcion conservada).
// Invocada sincronicamente. Nunca lanza una excepcion sin controlar: siempre
// responde { ok, ... } para que quien invoque (CLI en Etapa 3, backend en Etapa 4)
// pueda decidir sin depender de FunctionError.
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import Jimp from "jimp";

const endpoint = process.env.AWS_ENDPOINT_URL;
const s3 = new S3Client({ endpoint, forcePathStyle: true });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ endpoint }));

const BUCKET_MINIATURAS = process.env.BUCKET_MINIATURAS || "lomax-miniaturas";
const TABLE_ATRIBUTOS = process.env.TABLE_ATRIBUTOS || "LomaxAtributos";
const LADO_MAXIMO = 300;

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function marcarEstado(producto_id, estado_imagen, extra = {}) {
  const nombres = { "#estado": "estado_imagen" };
  const valores = { ":estado": estado_imagen };
  let expresion = "SET #estado = :estado";
  for (const [clave, valor] of Object.entries(extra)) {
    nombres[`#${clave}`] = clave;
    valores[`:${clave}`] = valor;
    expresion += `, #${clave} = :${clave}`;
  }
  await ddb.send(
    new UpdateCommand({
      TableName: TABLE_ATRIBUTOS,
      Key: { producto_id: String(producto_id) },
      UpdateExpression: expresion,
      ExpressionAttributeNames: nombres,
      ExpressionAttributeValues: valores,
    })
  );
}

export const handler = async (event) => {
  const { producto_id, bucket_original, key_original } = event || {};

  if (!producto_id || !bucket_original || !key_original) {
    return { ok: false, motivo: "faltan producto_id/bucket_original/key_original" };
  }

  let buffer;
  try {
    const objeto = await s3.send(
      new GetObjectCommand({ Bucket: bucket_original, Key: key_original })
    );
    buffer = await streamToBuffer(objeto.Body);
  } catch (err) {
    await marcarEstado(producto_id, "ERROR", { imagen_original_key: key_original });
    return { ok: false, motivo: `no se pudo leer el original: ${err.message}` };
  }

  let imagen;
  try {
    imagen = await Jimp.read(buffer);
    const mime = imagen.getMIME();
    if (mime !== Jimp.MIME_JPEG && mime !== Jimp.MIME_PNG) {
      throw new Error(`formato no permitido: ${mime}`);
    }
  } catch (err) {
    await marcarEstado(producto_id, "ERROR", { imagen_original_key: key_original });
    return { ok: false, motivo: `imagen invalida: ${err.message}` };
  }

  imagen.scaleToFit(LADO_MAXIMO, LADO_MAXIMO);
  const miniaturaBuffer = await imagen.getBufferAsync(Jimp.MIME_JPEG);
  const miniatura_key = `miniaturas/${producto_id}.jpg`;

  try {
    await s3.send(
      new PutObjectCommand({
        Bucket: BUCKET_MINIATURAS,
        Key: miniatura_key,
        Body: miniaturaBuffer,
        ContentType: "image/jpeg",
      })
    );
  } catch (err) {
    await marcarEstado(producto_id, "ERROR", { imagen_original_key: key_original });
    return { ok: false, motivo: `no se pudo guardar la miniatura: ${err.message}` };
  }

  await marcarEstado(producto_id, "LISTA", {
    imagen_original_key: key_original,
    miniatura_key,
  });

  return {
    ok: true,
    estado_imagen: "LISTA",
    miniatura_key,
    ancho: imagen.bitmap.width,
    alto: imagen.bitmap.height,
  };
};
