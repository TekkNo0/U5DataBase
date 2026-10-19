-- Verificacion de la Parte A: \du + information_schema + pruebas negativas.

\echo '============================================================'
\echo ' 1. ROLES Y MEMBRESIAS (\\du)'
\echo '============================================================'
\du app_web
\du admin_datos
\du auditor_sec
\du rol_app_lectura
\du rol_app_escritura
\du rol_soporte
\du rol_reportes
\du rol_auditor

\echo '============================================================'
\echo ' 1b. MEMBRESIAS (pg_auth_members)'
\echo '============================================================'
SELECT g.rolname AS rol_grupo, m.rolname AS miembro
FROM pg_auth_members am
JOIN pg_roles g ON g.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE g.rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                    'rol_reportes','rol_auditor','admin_datos','app_web','auditor_sec')
   OR m.rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                    'rol_reportes','rol_auditor','admin_datos','app_web','auditor_sec')
ORDER BY g.rolname, m.rolname;

\echo '============================================================'
\echo ' 2. GRANTS POR TABLA/VISTA (information_schema.role_table_grants)'
\echo '============================================================'
SELECT grantee, table_name,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                  'rol_reportes','rol_auditor','admin_datos','app_web','auditor_sec')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

\echo '============================================================'
\echo ' 3. PRIVILEGIOS A NIVEL DE COLUMNA SOBRE usuario'
\echo '    (nadie salvo admin_datos debe ver contrasena)'
\echo '============================================================'
SELECT grantee, column_name,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.column_privileges
WHERE table_name = 'usuario'
  AND grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                  'rol_reportes','rol_auditor','app_web','auditor_sec','admin_datos')
GROUP BY grantee, column_name
ORDER BY grantee, column_name;

\echo '============================================================'
\echo ' 3b. SONDEO DECLARATIVO: has_column_privilege sobre usuario'
\echo '     (f = no puede, t = puede)'
\echo '============================================================'
SELECT rol,
       has_column_privilege(rol,'usuario','contrasena','SELECT') AS puede_select_contrasena,
       has_column_privilege(rol,'usuario','email','SELECT')      AS puede_select_email,
       has_column_privilege(rol,'usuario','contrasena','UPDATE') AS puede_update_contrasena
FROM (VALUES ('app_web'),('admin_datos'),('auditor_sec'),
             ('rol_app_lectura'),('rol_app_escritura'),('rol_soporte'),
             ('rol_reportes'),('rol_auditor')) AS r(rol)
ORDER BY rol;

\echo '============================================================'
\echo ' 4. PRUEBA NEGATIVA - app_web NO puede leer usuario.contrasena'
\echo '    (se espera: ERROR de permisos, tabla/columna denegada)'
\echo '============================================================'
SET ROLE app_web;
SELECT contrasena FROM usuario LIMIT 1;
RESET ROLE;

\echo '============================================================'
\echo ' 5. PRUEBA NEGATIVA - app_web NO puede autoescalar a admin_datos'
\echo '    (se espera: ERROR must have admin option on role admin_datos)'
\echo '============================================================'
SET ROLE app_web;
GRANT admin_datos TO app_web;
RESET ROLE;

\echo '============================================================'
\echo ' 6. PRUEBA POSITIVA - app_web SI puede leer las columnas permitidas'
\echo '============================================================'
SET ROLE app_web;
SELECT id, nombre, email FROM usuario ORDER BY id LIMIT 3;
RESET ROLE;

\echo '============================================================'
\echo ' 7. PRUEBA NEGATIVA - auditor_sec NO puede ejecutar fn_resetear_password'
\echo '    (PUBLIC no debe tener EXECUTE sobre las funciones SECURITY DEFINER)'
\echo '============================================================'
SELECT p.proname AS funcion,
       has_function_privilege('public', p.oid, 'EXECUTE')       AS public_ejecuta,
       has_function_privilege('app_web', p.oid, 'EXECUTE')      AS app_web_ejecuta,
       has_function_privilege('auditor_sec', p.oid, 'EXECUTE')  AS auditor_ejecuta
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_autenticar','fn_resetear_password')
ORDER BY p.proname;

\echo '--- intento real como auditor_sec (se espera: ERROR de permisos) ---'
SET ROLE auditor_sec;
SELECT fn_resetear_password('admin@foodstore.com', 'clave-intruso');
RESET ROLE;
