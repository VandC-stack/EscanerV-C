-- Script para corregir la estructura de la base de datos
-- Ejecutar este script en PostgreSQL para arreglar las tablas

-- 1. Eliminar tablas existentes si tienen estructura incorrecta
DROP TABLE IF EXISTS codigos_items CASCADE;
DROP TABLE IF EXISTS capturas CASCADE;

-- 2. Crear tabla codigos_items con estructura correcta
CREATE TABLE codigos_items (
    id SERIAL PRIMARY KEY,
    codigo_barras VARCHAR(50) NOT NULL,
    item VARCHAR(50) NOT NULL,
    resultado VARCHAR(20) DEFAULT '',
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(codigo_barras, item)
);

-- 3. Crear tabla capturas con estructura correcta
CREATE TABLE capturas (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(50) NOT NULL,
    item VARCHAR(50) NOT NULL,
    motivo VARCHAR(100) NOT NULL,
    cumple VARCHAR(20) NOT NULL,
    usuario VARCHAR(50) NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(codigo, item)
);

-- 4. Crear índices para mejorar el rendimiento
CREATE INDEX idx_codigos_items_codigo ON codigos_items(codigo_barras);
CREATE INDEX idx_codigos_items_item ON codigos_items(item);
CREATE INDEX idx_capturas_codigo ON capturas(codigo);
CREATE INDEX idx_capturas_item ON capturas(item);
CREATE INDEX idx_capturas_fecha ON capturas(fecha);

-- 5. Insertar configuración por defecto
INSERT INTO configuracion (clave, valor, descripcion) 
VALUES 
    ('auto_actualizar', 'false', 'Habilitar actualizaciones automáticas'),
    ('ruta_clp', '', 'Ruta al archivo CLP'),
    ('ruta_historico', '', 'Ruta al archivo histórico')
ON CONFLICT (clave) DO UPDATE SET 
    valor = EXCLUDED.valor,
    descripcion = EXCLUDED.descripcion;

-- 6. Verificar que las tablas se crearon correctamente
SELECT 'Tabla codigos_items creada correctamente' as mensaje;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'codigos_items' 
ORDER BY ordinal_position;

SELECT 'Tabla capturas creada correctamente' as mensaje;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'capturas' 
ORDER BY ordinal_position; 