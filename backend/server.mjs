// Etapa 4: API de Lomax. Ver docs/CONCEPTOS.md y el guion de defensa para el
// porque de cada decision (idempotencia, codigos de error, maquina de estados).
import express from "express";
import multer from "multer";
import pg from "pg";
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";

const {
  PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE,
  AWS_ENDPOINT_URL,
  BUCKET_ORIGINALES = "lomax-originales",
  BUCKET_MINIATURAS = "lomax-miniaturas",
  TABLE_ATRIBUTOS = "LomaxAtributos",
  LAMBDA_FUNCTION = "lomax-generar-miniatura",
  PORT = 4000,
} = process.env;

const pool = new pg.Pool({ host: PGHOST, port: PGPORT, user: PGUSER, password: PGPASSWORD, database: PGDATABASE });
const s3 = new S3Client({ endpoint: AWS_ENDPOINT_URL, forcePathStyle: true });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ endpoint: AWS_ENDPOINT_URL }));
const lambda = new LambdaClient({ endpoint: AWS_ENDPOINT_URL });

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });
const INSTANCIA = process.env.HOSTNAME || "local";

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  res.set("X-Instancia", INSTANCIA); // Etapa 7: identificar que Pod respondio
  next();
});

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function invocarLambda(producto_id, key_original) {
  const respuesta = await lambda.send(
    new InvokeCommand({
      FunctionName: LAMBDA_FUNCTION,
      InvocationType: "RequestResponse",
      Payload: Buffer.from(JSON.stringify({ producto_id, bucket_original: BUCKET_ORIGINALES, key_original })),
    })
  );
  return JSON.parse(Buffer.from(respuesta.Payload).toString());
}

// GET /categorias
app.get("/categorias", async (req, res, next) => {
  try {
    const { rows } = await pool.query("SELECT categoria_id, nombre FROM categorias ORDER BY categoria_id");
    res.json(rows);
  } catch (err) {
    next(err);
  }
});

// POST /productos
app.post("/productos", async (req, res, next) => {
  const { codigo, nombre, descripcion, precio, categoria_id, atributos } = req.body || {};
  if (!codigo || !nombre || typeof precio !== "number" || !categoria_id) {
    return res.status(400).json({ error: "faltan o son invalidos: codigo, nombre, precio, categoria_id" });
  }

  let producto_id;
  try {
    const { rows } = await pool.query(
      "INSERT INTO productos (codigo, nombre, descripcion, precio, categoria_id) VALUES ($1,$2,$3,$4,$5) RETURNING producto_id",
      [codigo, nombre, descripcion || null, precio, categoria_id]
    );
    producto_id = rows[0].producto_id;
  } catch (err) {
    if (err.code === "23505") return res.status(409).json({ error: "codigo de producto duplicado" });
    if (err.code === "23503") return res.status(400).json({ error: "categoria_id inexistente" });
    if (err.code === "23514") return res.status(400).json({ error: "precio invalido (debe ser >= 0)" });
    return next(err);
  }

  try {
    await ddb.send(
      new PutCommand({
        TableName: TABLE_ATRIBUTOS,
        Item: { producto_id: String(producto_id), atributos: atributos || {}, estado_imagen: "PENDIENTE" },
      })
    );
  } catch (err) {
    return res.status(502).json({ error: "producto creado pero fallo guardar atributos", paso_fallido: "dynamodb", producto_id });
  }

  res.status(201).json({ producto_id, estado: "PENDIENTE" });
});

// POST /productos/:id/imagen
app.post("/productos/:id/imagen", upload.single("imagen"), async (req, res, next) => {
  const producto_id = req.params.id;
  try {
    if (!req.file) return res.status(400).json({ error: "falta el archivo imagen" });
    if (!["image/jpeg", "image/png"].includes(req.file.mimetype)) {
      return res.status(415).json({ error: "formato no permitido, use JPEG o PNG" });
    }

    const { rows } = await pool.query("SELECT producto_id FROM productos WHERE producto_id=$1", [producto_id]);
    if (rows.length === 0) return res.status(404).json({ error: "producto no encontrado" });

    const ext = req.file.mimetype === "image/png" ? "png" : "jpg";
    const key_original = `originales/${producto_id}.${ext}`;

    try {
      await s3.send(new PutObjectCommand({ Bucket: BUCKET_ORIGINALES, Key: key_original, Body: req.file.buffer, ContentType: req.file.mimetype }));
    } catch (err) {
      return res.status(502).json({ error: "no se pudo guardar la imagen original", paso_fallido: "s3" });
    }

    let resultado;
    try {
      resultado = await invocarLambda(producto_id, key_original);
    } catch (err) {
      return res.status(503).json({ error: "no se pudo invocar la funcion de miniaturas", paso_fallido: "lambda" });
    }
    if (!resultado.ok) {
      return res.status(502).json({ error: resultado.motivo || "no se pudo generar la miniatura", paso_fallido: "lambda" });
    }

    let item;
    try {
      const get = await ddb.send(new GetCommand({ TableName: TABLE_ATRIBUTOS, Key: { producto_id: String(producto_id) } }));
      item = get.Item;
    } catch (err) {
      return res.status(502).json({ error: "no se pudo confirmar atributos", paso_fallido: "dynamodb" });
    }
    if (!item || resultado.estado_imagen !== "LISTA") {
      return res.status(502).json({ error: "faltan atributos o miniatura para publicar", paso_fallido: "dynamodb" });
    }

    await pool.query("UPDATE productos SET estado='PUBLICADO' WHERE producto_id=$1", [producto_id]);
    res.json({ producto_id, estado: "PUBLICADO", miniatura_key: resultado.miniatura_key });
  } catch (err) {
    next(err);
  }
});

// POST /productos/:id/reprocesar
app.post("/productos/:id/reprocesar", async (req, res, next) => {
  const producto_id = req.params.id;
  try {
    const { rows } = await pool.query("SELECT producto_id FROM productos WHERE producto_id=$1", [producto_id]);
    if (rows.length === 0) return res.status(404).json({ error: "producto no encontrado" });

    const get = await ddb.send(new GetCommand({ TableName: TABLE_ATRIBUTOS, Key: { producto_id: String(producto_id) } }));
    const item = get.Item;
    if (!item || !item.imagen_original_key) {
      return res.status(409).json({ error: "no hay imagen original guardada para reprocesar" });
    }

    let resultado;
    try {
      resultado = await invocarLambda(producto_id, item.imagen_original_key);
    } catch (err) {
      return res.status(503).json({ error: "no se pudo invocar la funcion de miniaturas", paso_fallido: "lambda" });
    }
    if (!resultado.ok) {
      return res.status(502).json({ error: resultado.motivo || "no se pudo generar la miniatura", paso_fallido: "lambda" });
    }

    await pool.query("UPDATE productos SET estado='PUBLICADO' WHERE producto_id=$1", [producto_id]);
    res.json({ producto_id, estado: "PUBLICADO", miniatura_key: resultado.miniatura_key });
  } catch (err) {
    next(err);
  }
});

// GET /productos (solo PUBLICADOS)
app.get("/productos", async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.producto_id, p.codigo, p.nombre, p.precio, p.categoria_id, c.nombre AS categoria
       FROM productos p JOIN categorias c ON c.categoria_id = p.categoria_id
       WHERE p.estado = 'PUBLICADO' ORDER BY p.producto_id`
    );
    const productos = await Promise.all(
      rows.map(async (p) => {
        const get = await ddb.send(new GetCommand({ TableName: TABLE_ATRIBUTOS, Key: { producto_id: String(p.producto_id) } }));
        return { ...p, atributos: get.Item?.atributos || {}, miniatura_key: get.Item?.miniatura_key || null };
      })
    );
    res.json(productos);
  } catch (err) {
    next(err);
  }
});

// GET /productos/:id
app.get("/productos/:id", async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.*, c.nombre AS categoria FROM productos p JOIN categorias c ON c.categoria_id = p.categoria_id WHERE p.producto_id = $1`,
      [req.params.id]
    );
    if (rows.length === 0) return res.status(404).json({ error: "producto no encontrado" });
    const get = await ddb.send(new GetCommand({ TableName: TABLE_ATRIBUTOS, Key: { producto_id: String(req.params.id) } }));
    res.json({
      ...rows[0],
      atributos: get.Item?.atributos || {},
      estado_imagen: get.Item?.estado_imagen || null,
      miniatura_key: get.Item?.miniatura_key || null,
    });
  } catch (err) {
    next(err);
  }
});

// GET /productos/:id/imagen
app.get("/productos/:id/imagen", async (req, res, next) => {
  try {
    const get = await ddb.send(new GetCommand({ TableName: TABLE_ATRIBUTOS, Key: { producto_id: String(req.params.id) } }));
    const key = get.Item?.miniatura_key;
    if (!key || get.Item.estado_imagen !== "LISTA") return res.status(404).json({ error: "miniatura no disponible" });
    const obj = await s3.send(new GetObjectCommand({ Bucket: BUCKET_MINIATURAS, Key: key }));
    res.set("Content-Type", obj.ContentType || "image/jpeg");
    res.send(await streamToBuffer(obj.Body));
  } catch (err) {
    if (err.name === "NoSuchKey") return res.status(404).json({ error: "miniatura no disponible" });
    next(err);
  }
});

// Errores de multer (ej. archivo > 5MB) y cualquier otro error no manejado
app.use((err, req, res, next) => {
  if (err && err.code === "LIMIT_FILE_SIZE") {
    return res.status(413).json({ error: "archivo mayor a 5 Mb" });
  }
  console.error(err);
  res.status(500).json({ error: "error interno" });
});

app.listen(PORT, () => console.log(`Lomax backend (${INSTANCIA}) escuchando en :${PORT}`));
