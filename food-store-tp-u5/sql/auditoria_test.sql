-- ============================================================
-- Food Store - TP Unidad 5 - PARTE B
-- auditoria_test.sql: secuencia de operaciones de prueba
-- SE EJECUTA COMO app_web (rol de login de la aplicacion):
--   psql -h localhost -U app_web -d foodstore_u5_tp -f auditoria_test.sql
-- Cubre: lectura + insercion + actualizacion. El intento de
-- login fallido se dispara aparte (ver informe_auditoria.md).
-- Se usa ROLLBACK para no ensuciar los datos: el objetivo es
-- generar trazas de auditoria, no persistir cambios.
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;

-- 1) ESCRITURA - insercion de un pedido de prueba
INSERT INTO pedido (usuario_id, total, estado)
VALUES (1, 0, 'PENDIENTE');

-- 2) ESCRITURA - actualizacion del total del pedido recien creado
UPDATE pedido
SET total = 123.45
WHERE id = (SELECT max(id) FROM pedido);

-- 3) LECTURA - consulta de control
SELECT count(*) AS pedidos_del_usuario_1
FROM pedido
WHERE usuario_id = 1;

-- La operacion no se persiste; solo se buscaba dejar trazas en el log.
ROLLBACK;
