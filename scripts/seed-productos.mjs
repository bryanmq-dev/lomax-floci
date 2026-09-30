// Etapa 5: siembra 20 productos PUBLICADOS via la API real (no INSERT directo),
// para probar el mismo camino que usara un usuario real.
// Uso: node scripts/seed-productos.mjs --base-url http://localhost:8090/api --fotos /tmp/lomax-fotos
import { readFile } from "node:fs/promises";

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, arg, i, arr) => {
    if (arg.startsWith("--")) acc.push([arg.slice(2), arr[i + 1]]);
    return acc;
  }, [])
);
const BASE = args["base-url"] || "http://localhost:8090/api";
const FOTOS_DIR = args["fotos"] || "/tmp/lomax-fotos";

const PRODUCTOS = [
  { codigo: "TEC-101", nombre: "Teclado Mecanico RGB", precio: 42.9, categoria: "Teclados", atributos: { conexion: "USB", distribucion: "Español" } },
  { codigo: "TEC-102", nombre: "Teclado Membrana Compacto", precio: 15.5, categoria: "Teclados", atributos: { conexion: "USB", distribucion: "Ingles" } },
  { codigo: "TEC-103", nombre: "Teclado Inalambrico Slim", precio: 28.0, categoria: "Teclados", atributos: { conexion: "Bluetooth", distribucion: "Español" } },
  { codigo: "TEC-104", nombre: "Teclado Gamer TKL", precio: 55.0, categoria: "Teclados", atributos: { conexion: "USB", distribucion: "Ingles" } },
  { codigo: "TEC-105", nombre: "Teclado Ergonomico", precio: 38.75, categoria: "Teclados", atributos: { conexion: "USB", distribucion: "Español" } },
  { codigo: "TEC-106", nombre: "Teclado Retroiluminado", precio: 33.2, categoria: "Teclados", atributos: { conexion: "Bluetooth", distribucion: "Ingles" } },
  { codigo: "TEC-107", nombre: "Teclado Oficina Basico", precio: 9.99, categoria: "Teclados", atributos: { conexion: "USB", distribucion: "Español" } },

  { codigo: "MOU-201", nombre: "Mouse Optico Basico", precio: 6.5, categoria: "Mouses", atributos: { conexion: "USB", dpi: 1000 } },
  { codigo: "MOU-202", nombre: "Mouse Inalambrico Silencioso", precio: 14.0, categoria: "Mouses", atributos: { conexion: "Bluetooth", dpi: 1600 } },
  { codigo: "MOU-203", nombre: "Mouse Gamer RGB", precio: 24.9, categoria: "Mouses", atributos: { conexion: "USB", dpi: 6400 } },
  { codigo: "MOU-204", nombre: "Mouse Ergonomico Vertical", precio: 19.5, categoria: "Mouses", atributos: { conexion: "Bluetooth", dpi: 1200 } },
  { codigo: "MOU-205", nombre: "Mouse Compacto Viaje", precio: 8.9, categoria: "Mouses", atributos: { conexion: "USB", dpi: 800 } },
  { codigo: "MOU-206", nombre: "Mouse Profesional CAD", precio: 32.0, categoria: "Mouses", atributos: { conexion: "USB", dpi: 8000 } },
  { codigo: "MOU-207", nombre: "Mouse Silencioso Oficina", precio: 11.25, categoria: "Mouses", atributos: { conexion: "Bluetooth", dpi: 1000 } },

  { codigo: "PAN-301", nombre: "Pantalla 24 pulgadas Full HD", precio: 129.0, categoria: "Pantallas", atributos: { pulgadas: 24, resolucion: "1920x1080" } },
  { codigo: "PAN-302", nombre: "Pantalla 27 pulgadas QHD", precio: 189.0, categoria: "Pantallas", atributos: { pulgadas: 27, resolucion: "2560x1440" } },
  { codigo: "PAN-303", nombre: "Pantalla 21 pulgadas HD", precio: 89.0, categoria: "Pantallas", atributos: { pulgadas: 21, resolucion: "1600x900" } },
  { codigo: "PAN-304", nombre: "Pantalla Curva 29 pulgadas", precio: 249.0, categoria: "Pantallas", atributos: { pulgadas: 29, resolucion: "2560x1080" } },
  { codigo: "PAN-305", nombre: "Pantalla 32 pulgadas 4K", precio: 349.0, categoria: "Pantallas", atributos: { pulgadas: 32, resolucion: "3840x2160" } },
  { codigo: "PAN-306", nombre: "Pantalla 19 pulgadas Basica", precio: 69.0, categoria: "Pantallas", atributos: { pulgadas: 19, resolucion: "1366x768" } },
];

async function apiPostJSON(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: res.status, data: await res.json().catch(() => ({})) };
}

async function apiPostImagen(producto_id, buffer, nombreArchivo) {
  const formData = new FormData();
  formData.append("imagen", new Blob([buffer], { type: "image/jpeg" }), nombreArchivo);
  const res = await fetch(`${BASE}/productos/${producto_id}/imagen`, { method: "POST", body: formData });
  return { status: res.status, data: await res.json().catch(() => ({})) };
}

async function main() {
  const catRes = await fetch(`${BASE}/categorias`);
  const categoriasReales = await catRes.json();
  const idPorNombre = Object.fromEntries(categoriasReales.map((c) => [c.nombre, c.categoria_id]));

  let publicados = 0;
  for (let i = 0; i < PRODUCTOS.length; i++) {
    const p = PRODUCTOS[i];
    const categoria_id = idPorNombre[p.categoria];
    if (!categoria_id) {
      console.error(`categoria desconocida: ${p.categoria}`);
      continue;
    }

    const creado = await apiPostJSON("/productos", {
      codigo: p.codigo,
      nombre: p.nombre,
      descripcion: `${p.nombre} — catalogo Lomax SA`,
      precio: p.precio,
      categoria_id,
      atributos: p.atributos,
    });

    if (creado.status !== 201) {
      console.log(`[omitido] ${p.codigo}: ${creado.data.error || creado.status}`);
      continue;
    }

    const producto_id = creado.data.producto_id;
    const archivoFoto = `${FOTOS_DIR}/producto_${(i % 20) + 1}.jpg`;
    const buffer = await readFile(archivoFoto);
    const publicado = await apiPostImagen(producto_id, buffer, `${p.codigo}.jpg`);

    if (publicado.status === 200) {
      publicados++;
      console.log(`[ok] ${p.codigo} -> producto_id=${producto_id} PUBLICADO`);
    } else {
      console.log(`[pendiente] ${p.codigo} -> producto_id=${producto_id}: ${publicado.data.error}`);
    }
  }

  console.log(`\n${publicados}/${PRODUCTOS.length} productos publicados.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
