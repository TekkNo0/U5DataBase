-- ============================================================
-- Food Store - TP Unidad 5 - PARTE A
-- roles.sql: esquema de roles y permisos de minimo privilegio
-- Motor: PostgreSQL 17
-- Base de trabajo: foodstore_u5_tp (copia de foodstore_u4)
-- Deriva de: docs/kiro_roles_spec/{requirements,design}.md
--
-- Ejecutar SIEMPRE como superusuario (postgres), conectado a la
-- base de trabajo:  psql -d foodstore_u5_tp -f roles.sql
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 0. Limpieza idempotente (permite re-ejecutar el script)
--    - revoca membresias en cualquier direccion
--    - libera privilegios/objetos con DROP OWNED BY
--    - elimina los roles en orden inverso de dependencia
-- ------------------------------------------------------------
DO $$
DECLARE
    target text;
    m      record;
BEGIN
    FOREACH target IN ARRAY ARRAY[
        'app_web','admin_datos','auditor_sec',
        'rol_app_escritura','rol_soporte','rol_reportes','rol_auditor','rol_app_lectura'
    ] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = target) THEN
            FOR m IN
                SELECT r.rolname AS member_role, g.rolname AS group_role
                FROM pg_auth_members am
                JOIN pg_roles r ON r.oid = am.member
                JOIN pg_roles g ON g.oid = am.roleid
                WHERE r.rolname = target OR g.rolname = target
            LOOP
                EXECUTE format('REVOKE %I FROM %I', m.group_role, m.member_role);
            END LOOP;
            EXECUTE format('DROP OWNED BY %I', target);
        END IF;
    END LOOP;
END$$;

DROP ROLE IF EXISTS app_web;
DROP ROLE IF EXISTS admin_datos;
DROP ROLE IF EXISTS auditor_sec;
DROP ROLE IF EXISTS rol_app_escritura;
DROP ROLE IF EXISTS rol_soporte;
DROP ROLE IF EXISTS rol_reportes;
DROP ROLE IF EXISTS rol_auditor;
DROP ROLE IF EXISTS rol_app_lectura;

-- ------------------------------------------------------------
-- 1. Roles de grupo (NOLOGIN): solo agrupan privilegios
-- ------------------------------------------------------------
CREATE ROLE rol_app_lectura  NOLOGIN;
CREATE ROLE rol_app_escritura NOLOGIN;
CREATE ROLE rol_soporte      NOLOGIN;
CREATE ROLE rol_reportes     NOLOGIN;
CREATE ROLE rol_auditor      NOLOGIN;   -- rol adicional (justificado en la spec)

-- ------------------------------------------------------------
-- 2. Roles de login (LOGIN): identidades que se autentican
-- ------------------------------------------------------------
CREATE ROLE app_web     LOGIN PASSWORD 'AppWeb#2026'     NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE admin_datos LOGIN PASSWORD 'AdminDatos#2026' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE auditor_sec LOGIN PASSWORD 'AuditSec#2026'   NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- ------------------------------------------------------------
-- 3. Membresias (grafo de herencia)
-- ------------------------------------------------------------
GRANT rol_app_lectura   TO rol_app_escritura;   -- escritura implica lectura
GRANT rol_app_escritura TO app_web;             -- unico cliente transaccional
GRANT rol_auditor       TO auditor_sec;         -- analista de seguridad

-- ------------------------------------------------------------
-- 4. Privilegios de objeto
-- ------------------------------------------------------------

-- 4.1 rol_app_lectura : lectura del negocio, SIN contrasena
GRANT SELECT ON categoria, producto, pedido, detalle_pedido, deposito, lote
    TO rol_app_lectura;
-- privilegio A NIVEL DE COLUMNA: se listan todas las columnas menos contrasena
GRANT SELECT (id, nombre, apellido, email, activo) ON usuario TO rol_app_lectura;

-- 4.2 rol_app_escritura : DML transaccional (hereda la lectura)
GRANT INSERT, UPDATE, DELETE ON pedido, detalle_pedido TO rol_app_escritura;
GRANT INSERT, UPDATE          ON usuario              TO rol_app_escritura;
GRANT USAGE ON SEQUENCE usuario_id_seq, pedido_id_seq, detalle_pedido_id_seq
    TO rol_app_escritura;

-- 4.3 rol_soporte : lectura amplia + UPDATE a nivel de columna
GRANT SELECT ON categoria, producto, pedido, detalle_pedido, deposito, lote,
                deposito_responsable, control_lote_responsable,
                control_lote_almacen_compat, venta_categoria_diaria
    TO rol_soporte;
GRANT SELECT (id, nombre, apellido, email, activo) ON usuario TO rol_soporte;
GRANT UPDATE (estado) ON pedido  TO rol_soporte;   -- solo el estado
GRANT UPDATE (activo) ON producto TO rol_soporte;  -- solo la vigencia

-- 4.4 rol_reportes : solo vistas y agregados (nunca PII cruda)
GRANT SELECT ON v_productos_vigentes, v_pedidos_usuario,
                v_detalle_pedido_producto, v_usuarios_sin_contrasena,
                venta_categoria_diaria
    TO rol_reportes;

-- 4.5 rol_auditor : lectura forense sin contrasena
GRANT SELECT ON v_productos_vigentes, v_pedidos_usuario,
                v_detalle_pedido_producto, v_usuarios_sin_contrasena,
                pedido, detalle_pedido
    TO rol_auditor;
GRANT SELECT (id, nombre, apellido, email, activo) ON usuario TO rol_auditor;

-- 4.6 admin_datos : amplio sobre el negocio, NO superusuario
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO admin_datos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_datos;

-- ------------------------------------------------------------
-- 5. REVOKE explicitos (endurecimiento)
-- ------------------------------------------------------------
-- Ningun rol publico puede crear objetos en el esquema public.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- Se retira el privilegio TEMPORARY que PostgreSQL otorga a PUBLIC por defecto.
REVOKE TEMPORARY ON DATABASE foodstore_u5_tp FROM PUBLIC;
-- Defensivo: asegura que ningun rol de aplicacion reciba la columna sensible
-- por un GRANT a nivel de tabla colado a futuro.
REVOKE SELECT (contrasena) ON usuario FROM PUBLIC;
-- CRITICO: PostgreSQL otorga EXECUTE sobre funciones a PUBLIC por defecto.
-- Sin este REVOKE, cualquier identidad con LOGIN podria ejecutar las funciones
-- SECURITY DEFINER fn_autenticar / fn_resetear_password y tomar control de una
-- cuenta (account takeover), anulando la proteccion de minimo privilegio.
REVOKE EXECUTE ON ALL FUNCTIONS  IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;

-- ------------------------------------------------------------
-- 6. ALTER DEFAULT PRIVILEGES : politica para objetos FUTUROS
-- ------------------------------------------------------------
-- Funciones futuras: retirar el EXECUTE que PUBLIC recibe por defecto.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Tablas futuras creadas por postgres: lectura para los roles analiticos de
-- datos crudos. rol_reportes NO se incluye a proposito: solo debe recibir
-- vistas/agregados por GRANT explicito (nunca PII cruda), ver spec R6.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_app_lectura, rol_soporte, rol_auditor;
-- admin_datos debe alcanzar tambien las tablas futuras (coherencia con 4.6).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO admin_datos;
-- Secuencias futuras: uso para quien escribe.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO rol_app_escritura, admin_datos;

COMMIT;
