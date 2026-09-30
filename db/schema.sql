-- Etapa 2: modelo relacional (RDS Postgres, instancia lomax-db)
CREATE TABLE IF NOT EXISTS categorias (
  categoria_id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS productos (
  producto_id SERIAL PRIMARY KEY,
  codigo TEXT NOT NULL UNIQUE,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
  categoria_id INT NOT NULL REFERENCES categorias(categoria_id),
  fecha_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE', 'PUBLICADO'))
);
