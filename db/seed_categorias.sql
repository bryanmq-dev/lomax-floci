-- Etapa 2: carga inicial idempotente (repetible sin duplicar)
INSERT INTO categorias (nombre) VALUES
  ('Teclados'),
  ('Mouses'),
  ('Pantallas')
ON CONFLICT (nombre) DO NOTHING;
