# BITÁCORA — Uso de IA en el TP Unidad 5 (Food Store)

**Alumno:** Maximiliano Nardez  
**Materia:** Base de Datos II — Unidad 5: Administración y Seguridad  
**Base de datos:** `foodstore_u5_tp` (copia de trabajo de `foodstore_u4`) · PostgreSQL 17  
**Asistente de IA:** OpenCode (asistente de terminal con acceso a shell, código y base de datos)  
**Planificación asistida:** Kiro (especificación de requerimientos y diseño de seguridad)  
**Control de versiones:** Git  

---

## 1. Tabla consolidada de uso de IA (Formato obligatorio de 3 columnas)

A continuación se presenta la tabla de tres columnas requerida por la cátedra, resumiendo todas las interacciones clave con el asistente de IA a lo largo de las distintas etapas del trabajo práctico:

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| **[Paso previo — Reconstrucción de funciones]:** *"Reconstruí las funciones `fn_autenticar` y `fn_resetear_password` de la Clase 2 con lógica `SECURITY DEFINER` y hash MD5 sobre `usuario.contrasena`."* | Generó ambas funciones en PL/pgSQL marcadas como `SECURITY DEFINER` y con hash `md5()`. | **Aplicado con hardening:** Se agregó `SET search_path = public` para mitigar ataques de search-path hijack, y se revocó preventivamente su ejecución a `PUBLIC` para evitar account takeover. |
| **[Parte A — Auditoría de seguridad de roles]:** *"Actuá como auditor de seguridad de bases de datos PostgreSQL 17. Leé `sql/roles.sql`, auditá el archivo y proponé mejoras o correcciones concretas de mínimo privilegio."* | Hallazgo crítico (P0): en PostgreSQL `PUBLIC` posee `EXECUTE` por defecto sobre funciones, permitiendo que cualquier rol suplante usuarios vía `fn_resetear_password`. Sugirió revocar `EXECUTE` a `PUBLIC`, excluir `rol_reportes` de tablas futuras y granularizar `usuario`. | **Aplicado y verificado:** Se implementó `REVOKE EXECUTE ON ALL FUNCTIONS ... FROM PUBLIC` y `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE`. Se comprobó mediante prueba negativa con `auditor_sec` (`permiso denegado a la función fn_resetear_password`). |
| **[Parte A — Simplificación de sentencias]:** *"El bloque de GRANT es repetitivo. Proponé una versión más simple y corta, consolidando las sentencias."* | Consolidó sentencias idénticas (`GRANT ... TO rol_a, rol_b`) y se rehusó explícitamente a fusionar tablas de roles disímiles para no ampliar privilegios. | **Validación:** Confirmó solidez conceptual del diseño. Se optó por mantener el archivo original separado por bloques por mayor claridad de lectura y trazabilidad. |
| **[Parte A — Permiso excesivo propuesto (CASO EXIGIDO)]:** *"Revisá los privilegios sobre la base de datos `foodstore_u5_tp` para roles de aplicación."* | Propuso otorgar: `GRANT TEMPORARY ON DATABASE foodstore_u5_tp TO rol_app_escritura, rol_soporte;` argumentando conveniencia para ORMs y procesos batch. | **RECHAZADO / CORREGIDO:** Se rechazó la propuesta. Ni la app ni el soporte requieren tablas temporales en Food Store. Otorgarlo viola el principio de mínimo privilegio ampliando la superficie de ataque. Se mantuvo `REVOKE TEMPORARY ON DATABASE ... FROM PUBLIC`. |
| **[Parte B — Configuración de auditoría nativa]:** *"Cómo configurar auditoría nativa en PostgreSQL 17 para registrar conexiones, desconexiones y modificaciones de datos con usuario, PID, base y host."* | Sugirió `log_connections = on`, `log_disconnections = on`, `log_statement = 'mod'` y prefijo `log_line_prefix = '%m [%p] %q%u@%d %h '`. Advirtió que el archivo de log es en sí mismo un activo sensible. | **Validación y corrección:** Se aplicó vía `ALTER SYSTEM` + reload. Se detectó que las sesiones preexistentes no refrescan `log_statement` sin reconectar (la IA no advirtió esto; el alumno lo descubrió al verificar con una nueva sesión). |
| **[Parte C — Reconstrucción ciega de incidente]:** *"Analizá este fragmento de log anonimizado (sin contexto adicional): reconstruí qué ocurrió, el orden cronológico y proponé una hipótesis de contención."* | Identificó la secuencia (reintentos fallidos de login → acceso exitoso → volcado de `usuario` → intento de escalamiento a `admin_datos` y creación de tabla bloqueados). Propuso contención inmediata (`pg_terminate_backend`, `ALTER ROLE app_web NOLOGIN`). | **Lectura crítica (ERROR SIGNIFICATIVO):** La IA afirmó que en `fn_autenticar` hubo *"tres contraseñas fallidas y una válida"*. El log nativo NO registra retornos de funciones (solo sentencias SQL). La IA alucinó esa certeza guiada por las etiquetas sintéticas (`pwd-fallida-*`). Se corrigió en el informe marcándolo como inferencia y no como evidencia. |
| **[Parte D — Consultas de agregación equivalentes]:** *"Esquema real `usuario` y anónimo `usuario_anon` con cohortes `rol` y `mes_alta` derivadas de `id`. Devolvé (1) agregación sobre `usuario_anon` y (2) consulta equivalente sobre la tabla real."* | Devolvió ambas consultas agrupando por `rol` y `mes_alta`, calculando las cohortes sintéticas en la tabla real de manera idéntica. | **Validación empírica:** Se ejecutaron ambas sobre 20.000 filas y se compararon con `EXCEPT` bidireccional, obteniendo exactamente 0 diferencias (equivalencia demostrada matemáticamente). |
| **[Parte E — Planificación del historial de Git]:** *"Revisar la convención de commits para reflejar el avance por partes (A a E) de forma atómica y legible."* | Recomendó mensajes descriptivos con prefijo por parte (`Parte A: ...`, `Parte B: ...`) y aislamiento de cambios por hito técnico. | **Validado:** El repositorio refleja una línea de tiempo limpia con 5 commits atómicos verificados con `git log`. |

---

## 2. Desarrollo detallado por partes

### Parte A — Roles y permisos de mínimo privilegio

- **Prompt (1 — auditoría de seguridad):**
  > "Actuá como auditor de seguridad de bases de datos PostgreSQL 17. Leé `sql/roles.sql` […] auditá el archivo y proponé mejoras o correcciones concretas, priorizadas, indicando qué SQL agregarías y por qué."
  
  **Respuesta de la IA:** Detectó dos hallazgos prioritarios (P0). El más grave: en PostgreSQL `EXECUTE` sobre funciones se otorga a `PUBLIC` por defecto, de modo que cualquier rol con LOGIN (incluso roles de sólo lectura como `auditor_sec`) podía ejecutar funciones `SECURITY DEFINER` y, mediante `fn_resetear_password`, cambiar la contraseña de cualquier usuario (account takeover). También recomendó excluir `rol_reportes` de tablas futuras y granularizar `usuario`.
  
  **Validación humana:**
  - Se aplicó `REVOKE EXECUTE ON ALL FUNCTIONS/PROCEDURES IN SCHEMA public FROM PUBLIC` y `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`.
  - Se verificó con la sección 7 de `docs/evidencias/verificacion_permisos.sql`: `public_ejecuta = f`, `auditor_sec = f`, comprobando que un intento de ejecución de `auditor_sec` genera error de denegación de permisos.
  - Se excluyó `rol_reportes` del `ALTER DEFAULT PRIVILEGES` de tablas futuras para garantizar que solo acceda a vistas anonimizadas/agregadas.

- **Prompt (2 — simplificación):**
  > "El bloque de GRANT es muy repetitivo […]. Proponé una versión más simple y corta, consolidando las sentencias."
  
  **Respuesta de la IA:** Consolidó sentencias idénticas en un solo `GRANT … TO rol_a, rol_b`, y se negó explícitamente a fusionar tablas de roles distintos para evitar sobre-otorgamiento.
  
  **Validación humana:** Se confirmó la solidez del diseño. Se prefirió conservar la separación por bloques funcionales para facilitar la lectura del código SQL.

---

### Parte B — Configuración de auditoría (logging nativo)

- **Uso de IA:** Asistencia para definir los parámetros nativos de auditoría en PostgreSQL (`log_connections`, `log_disconnections`, `log_statement = 'mod'` y estructura de `log_line_prefix`).
- **Respuesta de la IA:** Sugirió `log_line_prefix = '%m [%p] %q%u@%d %h '` y recalcó que el archivo de log es un activo sensible que expone sentencias en texto claro.
- **Validación y corrección humana:**
  - Se aplicó mediante `ALTER SYSTEM` y `SELECT pg_reload_conf();`.
  - **Detección de fallo de la IA:** La IA omitió señalar que las sesiones abiertas previamente a la recarga no aplican el cambio de `log_statement` sin reconectarse. El equipo lo detectó durante las pruebas de verificación al observar discrepancias entre `SHOW` en sesiones viejas vs. sesiones nuevas.
  - Se incorporó la noción de protección del archivo de log a nivel de permisos de sistema operativo (NTFS/POSIX) en el informe técnico.

---

### Parte C — Simulacro de incidente de acceso indebido

- **Prompt (reconstrucción ciega):**
  > "Analizá este fragmento de log anonimizado (sin contexto adicional): reconstruí qué ocurrió, el orden cronológico y proponé una hipótesis de contención."
- **Respuesta de la IA:** Identificó el ataque de fuerza bruta, el login válido, la lectura masiva de `usuario` y el intento fallido de escalamiento a `admin_datos` y persistencia con `CREATE TABLE`. Propuso contención inmediata.
- **Validación humana / corrección:**
  - El simulacro verificó que el escalamiento **falla efectivamente** gracias a las restricciones aplicadas en la Parte A (`permiso denegado para otorgar el rol admin_datos` y `permiso denegado al esquema public`).
  - La lectura crítica reveló que la IA asumió el resultado interno de las funciones `fn_autenticar` basándose en los nombres de las etiquetas sintéticas (`pwd-valida-X`, `pwd-fallida-*`), cuando el log nativo no registra el valor de retorno.

---

### Parte D — Protección de datos: anonimización y equivalencia

- **Prompt (consultas analíticas):**
  > "Esquema real `usuario(id,nombre,apellido,email,contrasena,activo)` y anónimo `usuario_anon(…,…, rol, mes_alta)` con la regla de derivación/anonimización. Devolvé (1) la agregación por `rol` y `mes_alta` sobre el anónimo y (2) la consulta equivalente sobre la tabla real."
- **Respuesta de la IA:** Proporcionó ambas consultas de agregación aplicando exactamente las mismas fórmulas de cohorte sobre ambas fuentes.
- **Validación humana:**
  - Se pobló `usuario_anon` con 20.000 filas generadas de forma determinista a partir de `usuario`.
  - Se contrastaron los resultados con `EXCEPT` bidireccional (`anon EXCEPT real` y `real EXCEPT anon`): **0 filas de diferencia**. La equivalencia agregada quedó rigurosamente probada.

---

## 3. Caso exigido por la consigna — Permiso MÁS amplio propuesto por la IA

Durante la fase de auditoría de la Parte A (ítem P2), la IA recomendó incorporar la siguiente instrucción:

```sql
GRANT TEMPORARY ON DATABASE foodstore_u5_tp TO rol_app_escritura, rol_soporte;
```

**Justificación de la IA:** Argumentó que *"muchos frameworks ORM y drivers de base de datos requieren crear tablas temporales para optimizar transacciones batch o procesos de staging"*.

**Decisión y corrección del equipo (NO APLICAR):**
El equipo decidió **rechazar enfáticamente** esta sugerencia. El principio rector de la Unidad 5 es el **mínimo privilegio**:
1. La aplicación Food Store no utiliza ni requiere tablas temporales en sus flujos transaccionales ni de soporte.
2. Otorgar `TEMPORARY` a nivel base de datos amplía la superficie de ataque, permitiendo a un rol comprometido consumir almacenamiento en disco creando objetos temporales no supervisados.
3. Se ratificó la postura de mantener `REVOKE TEMPORARY ON DATABASE foodstore_u5_tp FROM PUBLIC;` sin conceder grants posteriores. Si a futuro un requerimiento formal justificara tablas temporales, se concederá de manera acotada y justificada.

---

## 4. Error más significativo de la IA detectado durante el trabajo

El error más relevante ocurrió durante la **Parte C (Reconstrucción del incidente)**:

- **Descripción del error:** La IA presentó como hechos comprobados que las llamadas a `fn_autenticar` correspondían a *"tres intentos con contraseñas fallidas y un intento con contraseña válida"*.
- **Cómo se lo detectó:** El equipo cotejó la afirmación con el archivo de log real (`docs/log_simulacro_anonimizado.txt`). El motor PostgreSQL configurado con `log_statement = 'all'` registra **únicamente la sentencia enviada por el cliente**, pero **jamás registra el valor retornado** por una función escalar PL/pgSQL (a menos que se use un sistema de tracing especializado o una tabla de auditoría de aplicación).
- **Causa raíz:** La IA incurrió en una **alucinación por plausibilidad**: al leer los parámetros anonimizados `pwd-fallida-A` y `pwd-valida-X`, dedujo el resultado y lo presentó como una evidencia observada en el log, confundiendo una etiqueta semántica con una prueba fáctica.
- **Acción tomada:** El equipo documentó en `docs/informe_incidente.md` que dicha afirmación carecía de respaldo probatorio en el log, calificándola como una hipótesis deductiva pero no un hecho verificado.

---

## 5. Revisión del historial de Git del repositorio (Parte E, Punto 3)

Se auditó el árbol de commits del repositorio mediante `git log --oneline --graph`:

```text
* d4fa58a Parte E: BITACORA de uso de IA (prompts, validacion y error significativo)
* 953ae54 Parte D: tabla usuario_anon deterministica + prueba de equivalencia de agregados
* 9e9e6dc Parte C: simulacro de incidente, reconstruccion de funciones y contencion + informe
* 9cecd31 Parte B: configuracion de auditoria (log_connections/disconnections/statement) + informe
* 6aa7f8b Parte A: roles y permisos de minimo privilegio + evidencia (spec, roles.sql, verificacion)
```

**Evaluación:**
- El repositorio refleja fielmente el **avance progresivo y estructurado por partes**, evitando la práctica prohibida de subir un commit único monolítico al final.
- Cada mensaje de commit describe con precisión el alcance del hito técnico desarrollado y los artefactos generados.
- El historial es completamente lineal, limpio y trazable, cumpliendo de forma estricta las pautas de control de versiones de la materia.

---

## 6. Reflexión metodológica sobre el trabajo asistido por IA

1. **Acelerador de hipótesis:** La IA demostró una excelente capacidad para señalar vectores de ataque sutiles (como el permiso de ejecución a `PUBLIC` en funciones `SECURITY DEFINER`) y para construir consultas complejas de verificación.
2. **Imprescindibilidad del juicio humano:** La IA tiende a rellenar vacíos de información con conjeturas verosímiles y a proponer configuraciones genéricas permisivas ("por si acaso").
3. **Regla de oro adoptada:** Ninguna propuesta de código o diagnóstico generado por IA se da por válida sin una prueba de refutación o verificación empírica contra la base de datos viva.
