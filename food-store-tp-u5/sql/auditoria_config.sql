-- ============================================================
-- Food Store - TP Unidad 5 - PARTE B
-- auditoria_config.sql: activacion de la auditoria nativa
-- Motor: PostgreSQL 17
--
-- IMPORTANTE: ALTER SYSTEM no puede ejecutarse dentro de una
-- transaccion, por lo que este archivo se corre SIN BEGIN/COMMIT
-- y con varias sentencias sueltas:
--     psql -d postgres -f auditoria_config.sql
-- Los cambios se persisten en postgresql.auto.conf y se aplican
-- con pg_reload_conf() (no requiere reinicio del servidor).
-- ============================================================

-- Registra cada intento de conexion (exitosa o no) y su origen.
ALTER SYSTEM SET log_connections = 'on';

-- Registra cada desconexion y la duracion de la sesion.
ALTER SYSTEM SET log_disconnections = 'on';

-- Nivel 'mod': registra INSERT, UPDATE, DELETE, TRUNCATE, COPY y DDL.
-- No registra SELECT (por diseno; ver informe_auditoria.md).
ALTER SYSTEM SET log_statement = 'mod';

-- Prefijo con: fecha/hora, pid, usuario, base y host remoto
-- (responde quien / desde donde / cuando en cada linea).
ALTER SYSTEM SET log_line_prefix = '%m [%p] %q%u@%d %h ';

-- Aplicar sin reiniciar.
SELECT pg_reload_conf();
