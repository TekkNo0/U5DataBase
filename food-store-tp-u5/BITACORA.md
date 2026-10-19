# BITÁCORA — Uso de IA en el TP Unidad 5 (Food Store)

**Alumno:** Maximiliano Nardez
**Materia:** Base de Datos II — Unidad 5
**Base:** `foodstore_u5_tp` (copia de `foodstore_u4`) · PostgreSQL 17
**Asistente:** OpenCode (agente de IA con acceso a shell, archivos y base de datos)

Esta bitácora registra, **por cada parte del TP**, qué se le pidió a la IA
(prompt), qué devolvió (a grandes rasgos) y cómo se validó o corrigió su
respuesta. Al final se documenta el caso exigido por la consigna: **una
ocasión en que la IA propuso un privilegio más amplio de lo necesario y el
equipo decidió no aplicarlo tal cual**, más una reflexión general.

---

## Parte A — Roles y permisos de mínimo privilegio

**Prompt (1 — auditoría):**
> "Actuá como auditor de seguridad de bases de datos PostgreSQL 17. Leé
> `sql/roles.sql` […] auditá el archivo y proponé mejoras o correcciones
> concretas, priorizadas, indicando qué SQL agregarías y por qué."

**Respuesta de la IA (resumen):** encontró dos hallazgos **P0**, entre ellos
que en PostgreSQL `EXECUTE` sobre funciones se otorga a `PUBLIC` **por
defecto**, por lo que cualquier rol con LOGIN (incluido `auditor_sec`) podía
ejecutar las funciones `SECURITY DEFINER` del bootstrap y, con
`fn_resetear_password`, **cambiar la contraseña de cualquier usuario y
suplantarlo** (account takeover). También propuso: sacar `rol_reportes` del
`ALTER DEFAULT PRIVILEGES` de tablas (para que nunca reciba PII cruda de
tablas futuras), agregar `admin_datos` a las tablas futuras, y endurecer
`INSERT/UPDATE` de `usuario` a nivel de columna.

**Validación / corrección humana:**
- **Aplicado (verificado):** `REVOKE EXECUTE ON ALL FUNCTIONS/PROCEDURES IN
  SCHEMA public FROM PUBLIC` + `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON
  FUNCTIONS FROM PUBLIC` en `sql/roles.sql`. Se volvió a ejecutar
  `roles.sql` y el bootstrap; se agregó la **sección 7** a
  `docs/evidencias/verificacion_permisos.sql`, que ahora demuestra
  `public_ejecuta = f`, `app_web = t`, `auditor_sec = f`, y que un intento
  real de `auditor_sec` da *"permiso denegado a la función fn_resetear_password"*.
- **Aplicado:** `rol_reportes` **excluido** del SELECT por defecto en tablas
  futuras (coherente con la spec: reportes solo vistas/agregados).
- **Aplicado:** `admin_datos` agregado al `ALTER DEFAULT PRIVILEGES` de tablas.

**Prompt (2 — simplificación):**
> "El bloque de GRANT es muy repetitivo […]. Proponé una versión más simple
> y corta, consolidando las sentencias."

**Respuesta de la IA (resumen):** consolidó sentencias idénticas en un solo
`GRANT … TO rol_a, rol_b`, y **se negó explícitamente** a fusionar lo que
implicaba ampliar privilegios (p. ej. no unir los sets de tablas de roles
distintos). Es decir, mantuvo mínimo privilegio.

**Validación humana:** se tomó como confirmación de que el diseño no tenía
sobre-otorgamientos evitables. No se reescribió el archivo porque la
reducción (14→13 sentencias) era marginal y el original es más legible por
sección.

**Prompt (3 — permiso más amplio propuesto por la IA):** dentro de la
auditoría (P2) la IA sugirió:
> `GRANT TEMPORARY ON DATABASE foodstore_u5_tp TO rol_app_escritura, rol_soporte;`

**Decisión del equipo: NO aplicar.** Ver sección "Caso exigido" más abajo.

---

## Parte B — Configuración de auditoría (write-ahead log / logging)

**Uso de IA:** apoyo para interpretar qué parámetros del servidor cubren cada
necesidad de la consigna (`log_connections`, `log_disconnections`,
`log_statement = 'mod'`, `log_line_prefix`) y para elegir un
`log_line_prefix` que incluyera usuario, base y host.

**Respuesta de la IA (resumen):** recomendó
`log_line_prefix = '%m [%p] %q%u@%d %h '` y remarcó que `log_statement`
requiere `SIGHUP` (reload) y que el propio archivo de log es un **activo
sensible** (contiene DDL, PII y hasta contraseñas en texto).

**Validación humana:**
- Se aplicó la configuración vía `ALTER SYSTEM … ; SELECT pg_reload_conf();`
  (`sql/auditoria_config.sql`) y se verificó con `sql/auditoria_test.sql`.
- **Corrección del alumno:** tras cambiar `log_statement` a `'mod'`, `SHOW`
  seguía devolviendo `'all'` en la **misma sesión** (el backend ya conectado
  no reprocesa el `SIGHUP`); se validó en una conexión **nueva** (`SELECT
  setting, source FROM pg_settings …` → `mod / configuration file`). La IA no
  advirtió este detalle del reload y se detectó en la verificación.
- La afirmación "el log es un activo sensible" se usó para responder los
  puntos 3 y 4 en `docs/informe_auditoria.md` (permisos a nivel de SO del
  archivo, rotación, no exponerlo a IA).

---

## Parte C — Simulacro de incidente y reconstrucción

**Prompt (reconstrucción independiente):**
> "Reconstruí las funciones `fn_autenticar` y `fn_resetear_password` a partir
> de los registros de auditoría […] sin contexto previo del proyecto."

**Respuesta de la IA (resumen):** reconstruyó funciones plausibles
(SECURITY DEFINER, `md5`, `SET search_path = public`) y —el punto clave—
**afirmó qué llamadas a `fn_autenticar` habían tenido éxito** basándose en
las etiquetas anonimizadas del log (`pwd-valida-X`, `pwd-fallida-A/B/C`).

**Validación humana / corrección:**
- Se contrastó contra el log crudo: el log de PostgreSQL **no registra el
  resultado** de la función, solo la sentencia. La IA completó con
  plausibilidad lo que el log no puede saber. Se corrigió en
  `docs/informe_incidente.md` marcando esos valores como **inferencia**, no
  como evidencia.
- El simulacro confirmó el **fracaso de la escalada**: `SET ROLE app_web;
  GRANT admin_datos TO app_web;` falló (*"permiso denegado para otorgar el
  rol admin_datos"*) y `CREATE TABLE backdoor_persistencia` falló por
  `REVOKE CREATE ON SCHEMA public FROM PUBLIC`.

**⚠️ Error más significativo de la IA (obligatorio):** en la Parte C la IA
presentó como **hechos** (llamadas exitosas/fallidas de autenticación)
resultados que el log **no puede contener**, y solo al ser confrontada
admitió que no podía determinarlos. Es un caso de **alucinación por
plausibilidad**: rellenó el vacío de información con lo verosímil. Lección:
todo dato "recuperado" por IA sin traza en la evidencia debe tratarse como
hipótesis, no como hallazgo.

---

## Parte D — Tabla anónima y equivalencia

**Prompt (generación de consultas):**
> "Esquema real `usuario(id,nombre,apellido,email,contrasena,activo)` y
> anónimo `usuario_anon(…,…, rol, mes_alta)` con la regla de derivación/anonimización.
> Devolvé (1) la agregación por `rol` y `mes_alta` sobre el anónimo y (2) la
> consulta equivalente sobre la tabla real."

**Respuesta de la IA (resumen):** devolvió las dos consultas correctas,
aplicando a la tabla real las mismas funciones de derivación de cohorte.

**Validación humana:**
- Se ejecutó `usuario_anon.sql` (20 000 filas, determinística) y ambas
  consultas: **mismos 12 grupos y mismos conteos**.
- La equivalencia se **probó**, no se afirmó: `EXCEPT` en ambas direcciones
  → **0** filas de diferencia (`docs/verificacion_equivalencia.md`).

---

## Caso exigido por la consigna — la IA propuso un permiso MÁS amplio de lo necesario

En la auditoría (Parte A, ítem P2) la IA recomendó:
```sql
GRANT TEMPORARY ON DATABASE foodstore_u5_tp TO rol_app_escritura, rol_soporte;
```
argumentando que "muchos drivers/ORMs usan tablas temporales". En la práctica
esto **amplía** la superficie: concede creación de objetos temporales a dos
roles que, en este proyecto, **no la necesitan** (la app no usa staging ni
temporales; el soporte solo actualiza columnas puntuales).

**Decisión del equipo: no aplicarlo.** El principio de mínimo privilegio
manda; si más adelante aparece una necesidad real y documentada de temporales,
se otorgará entonces, de forma **explícita y acotada**. Dejar el `REVOKE
TEMPORARY … FROM PUBLIC` sin grant posterior es la postura correcta y quedó
asentada como decisión en `sql/roles.sql` (sección 5), no como efecto
colateral.

> Nota: al pedírsele una segunda pasada de "simplificación", la IA se negó a
> fusionar GRANT que implicaran ampliar privilegios. Esto es deseable, pero
> **no** exime de auditar cada sugerencia: la propuesta de `TEMPORARY` muestra
> que la IA sí puede proponer permisos más amplios cuando los justifica con un
> caso de uso genérico.

---

## Reflexión general sobre el uso de IA

- **Sirve muy bien para:** detectar huecos que un humano pasa por alto (el
  `EXECUTE` por defecto de `PUBLIC` sobre funciones `SECURITY DEFINER` fue un
  hallazgo real y crítico), redactar y consolidar SQL, y generar consultas
  equivalentes.
- **Riesgo principal:** **rellenar** con datos plausibles lo que la evidencia
  no respalda (Parte C). Toda salida de la IA debe poder **verificarse contra
  la base o el log**; lo no verificable se marca como hipótesis.
- **Regla de trabajo adoptada:** la IA propone, el humano **ejecuta y
  comprueba** (tests positivos y negativos), y solo entonces la respuesta pasa
  a ser un entregable. Ninguna afirmación del asistente se tomó como verdad
  sin una consulta que la respaldara.
