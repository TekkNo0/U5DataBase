-- ============================================================
-- Food Store - TP Unidad 5 - PARTE D
-- usuario_anon.sql: tabla anonima, sintetica y determinista.
-- Reemplaza datos personales por valores sinteticos generados de
-- forma deterministica (mismo id -> mismo valor, siempre), de modo
-- que los agregados sobre la tabla anonima coincidan con los de la
-- tabla real.
--
-- Patron de la Clase 2: se conserva el identificador subrogante
-- (id) como clave de emparejamiento y el atributo estructural
-- (activo); se reemplazan nombre, apellido, email y contrasena.
-- Ejecutar como postgres sobre foodstore_u5_tp.
-- ============================================================
BEGIN;

DROP TABLE IF EXISTS usuario_anon;

CREATE TABLE usuario_anon (
    id            INT     PRIMARY KEY,          -- subrogante, no PII
    nombre        TEXT    NOT NULL,             -- sintetico
    apellido      TEXT    NOT NULL,             -- sintetico
    email         TEXT    NOT NULL,             -- sintetico
    contrasena    TEXT    NOT NULL,             -- sintetico (hash)
    activo        BOOLEAN NOT NULL,             -- atributo estructural conservado
    rol           TEXT    NOT NULL,             -- cohorte derivada de id
    mes_alta      INT     NOT NULL              -- cohorte derivada de id (1..12)
);

INSERT INTO usuario_anon (id, nombre, apellido, email, contrasena, activo, rol, mes_alta)
SELECT
    u.id,
    (ARRAY['Ana','Bruno','Carla','Diego','Elena','Fabián'])[1 + (u.id % 6)]   AS nombre,
    (ARRAY['Gómez','Pérez','Ruiz','Sosa','Vega','Luna'])[1 + (u.id % 6)]      AS apellido,
    'anon' || u.id || '@anon.invalid'                                        AS email,
    md5('anon-' || u.id)                                                     AS contrasena,
    u.activo,
    (ARRAY['comprador','vendedor','soporte','admin'])[1 + (u.id % 4)]        AS rol,
    ((u.id % 12) + 1)                                                        AS mes_alta
FROM usuario u;

-- Tabla de uso interno: solo el administrador de datos y el auditor
-- (la anonimizacion es una herramienta de analisis, no de exposicion).
GRANT SELECT ON usuario_anon TO admin_datos, rol_auditor;

ANALYZE usuario_anon;
COMMIT;
