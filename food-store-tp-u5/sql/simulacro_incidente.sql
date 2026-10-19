-- ============================================================
-- Food Store - TP Unidad 5 - PARTE C
-- simulacro_incidente.sql
-- Reproduce, SOLO contra la base de desarrollo propia
-- (foodstore_u5_tp), la siguiente secuencia de acceso indebido:
--   (1) varios intentos fallidos contra fn_autenticar
--   (2) un inicio de sesion exitoso
--   (3) una lectura masiva de la tabla usuario
--   (4) un intento de escalamiento: otorgar a un rol de bajo
--       privilegio (app_web) membresia en admin_datos, y una
--       operacion reservada (crear tabla).
--
-- SE EJECUTA COMO app_web (rol de bajo privilegio):
--   psql -h localhost -U app_web -d foodstore_u5_tp -f simulacro_incidente.sql
--
-- Los intentos fallidos de login a nivel motor (FATAL) se
-- disparan desde el orquestador de shell antes de esta sesion;
-- ver docs/informe_incidente.md.
-- ============================================================
\set ON_ERROR_STOP off

-- ------------------------------------------------------------
-- (1) Intentos fallidos de autenticacion contra fn_autenticar
--     (password incorrecto -> la funcion devuelve FALSE)
-- ------------------------------------------------------------
SELECT fn_autenticar('usuario1@mail.com', 'clave-incorrecta-1') AS intento_1;
SELECT fn_autenticar('usuario1@mail.com', 'clave-incorrecta-2') AS intento_2;
SELECT fn_autenticar('usuario1@mail.com', 'clave-incorrecta-3') AS intento_3;

-- ------------------------------------------------------------
-- (2) Inicio de sesion exitoso (password correcto del usuario 1)
-- ------------------------------------------------------------
SELECT fn_autenticar('usuario1@mail.com', 'seed-1') AS intento_exitoso;

-- ------------------------------------------------------------
-- (3) Lectura masiva de la tabla usuario (exfiltracion de PII)
-- ------------------------------------------------------------
SELECT count(*) AS total_usuarios FROM usuario;

SELECT id, nombre, apellido, email
FROM usuario
ORDER BY id;

-- ------------------------------------------------------------
-- (4) Intento de escalamiento de privilegios
--     (a) otorgar membresia en admin_datos a app_web  -> DEBE FALLAR
--     (b) crear un objeto en el esquema public        -> DEBE FALLAR
-- ------------------------------------------------------------
GRANT admin_datos TO app_web;

CREATE TABLE backdoor_persistencia (id INT);
