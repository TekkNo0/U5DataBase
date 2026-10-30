# Trabajo Práctico — Unidad 5: Administración y Seguridad de Food Store

**Asignatura:** Base de Datos II — Tecnicatura Universitaria en Programación (Ciclo Lectivo 2026)  
**Alumno:** Maximiliano Nardez  
**Motor:** PostgreSQL 17  
**Base de datos:** `foodstore_u5_tp` (entorno local de desarrollo)  
**Herramientas:** OpenCode (asistente de IA de terminal), Kiro (especificación asistida), Git (control de versiones)  

---

## 📌 Estructura del Repositorio y Entregables

El proyecto cumple estrictamente la estructura consolidada requerida por la cátedra (Página 6 del TP):

```
food-store-tp-u5/
├── sql/
│   ├── roles.sql                     # [Parte A] DDL de roles, grants, revokes y default privileges
│   ├── auditoria_test.sql            # [Parte B] Secuencia de prueba para log de auditoría
│   ├── simulacro_incidente.sql       # [Parte C] Script que reproduce el intento de acceso y escalamiento
│   ├── usuario_anon.sql              # [Parte D] Creación determinista de la tabla anonimizada
│   ├── 00_funciones_bootstrap.sql    # [Paso previo] Reconstrucción de fn_autenticar y fn_resetear_password
│   └── auditoria_config.sql          # [Parte B] Sentencias de configuración de logging del motor
├── docs/
│   ├── kiro_roles_spec/
│   │   ├── requirements.md           # [Parte A] Especificación breve de roles y justificaciones (Kiro)
│   │   └── design.md                 # [Parte A] Matriz de permisos, grafo y decisiones de diseño (Kiro)
│   ├── informe_auditoria.md          # [Parte B] Informe de configuración, alcance de log y activo sensible
│   ├── log_auditoria_prueba.txt      # [Parte B] Fragmento de log capturado de las operaciones de prueba
│   ├── informe_incidente.md          # [Parte C] Reconstrucción ciega, contraste crítico y contención
│   ├── log_simulacro_anonimizado.txt # [Parte C] Fragmento de log del simulacro sanitizado y anonimizado
│   ├── verificacion_equivalencia.md  # [Parte D] Consultas comparadas y prueba matemática con EXCEPT
│   ├── verificacion_permisos.txt     # [Parte A] Salida completa de \du y role_table_grants
│   └── evidencias/                   # Scripts auxiliares y salidas crudas de ejecución
│       ├── run_simulacro.ps1
│       ├── verificacion_permisos.sql
│       ├── verificacion_permisos.txt
│       ├── verificacion_equivalencia.sql
│       └── verificacion_equivalencia.txt
└── BITACORA.md                       # [Parte E] Bitácora consolidada con tabla de 3 columnas obligatoria
```

---

## 🚀 Resumen de Cumplimiento por Parte

### Parte A — Roles y Permisos de Mínimo Privilegio
- **Especificación Kiro:** Archivos `requirements.md` y `design.md` en `docs/kiro_roles_spec/` con justificación en una oración de cada rol (grupo: `rol_app_lectura`, `rol_app_escritura`, `rol_soporte`, `rol_reportes`, `rol_auditor`; login: `app_web`, `admin_datos`, `auditor_sec`).
- **Implementación SQL (`sql/roles.sql`):** Bloque idempotente, control granular a nivel de columna sobre `usuario` (excluyendo `contrasena`), restricción sobre `PUBLIC`, y `ALTER DEFAULT PRIVILEGES` para tablas, secuencias y funciones futuras.
- **Verificación empírica:** Validado con `\du`, `information_schema.role_table_grants` y pruebas negativas con `has_column_privilege` (`docs/verificacion_permisos.txt`).

### Parte B — Activación y Prueba de la Auditoría
- **Parámetros configurados:** `log_connections = on`, `log_disconnections = on`, `log_statement = 'mod'` y `log_line_prefix = '%m [%p] %q%u@%d %h '` aplicados en PostgreSQL 17 (`sql/auditoria_config.sql`).
- **Trazas y análisis:** Operaciones ejecutadas con `app_web` capturadas en `docs/log_auditoria_prueba.txt`. Análisis de alcance (quién, qué, cuándo, desde dónde) y comparación conceptual con `pgAudit` en `docs/informe_auditoria.md`.
- **Protección del log:** Respuestas fundamentadas sobre la sensibilidad del archivo de log y su protección restrictiva a nivel de permisos de sistema operativo (NTFS/POSIX).

### Parte C — Laboratorio: Simulacro de Incidente de Acceso Indebido
- **Simulacro orquestado:** Reproducción controlada en entorno de desarrollo (`sql/simulacro_incidente.sql` + `run_simulacro.ps1`): reintentos de login fallidos contra `fn_autenticar`, login exitoso de `app_web`, exfiltración masiva de columnas no sensibles de `usuario`, e intento de escalamiento a `admin_datos` y persistencia con `CREATE TABLE`.
- **Bloqueo efectivo:** Constancia de que ambos intentos de escalamiento **fallaron por denegación de privilegios**.
- **Anonimización previa:** Sustitución de correos y credenciales por valores sintéticos deterministas antes de entregar el log a la IA (`docs/log_simulacro_anonimizado.txt`).
- **Lectura crítica de la respuesta de IA:** Detección de aciertos, omisiones y el **error crítico de la IA** (alucinación donde afirmó resultados de retorno de funciones PL/pgSQL que el log nativo no registra).
- **Informe de contención:** Propuesta fundamentada por el equipo con criterio humano (`docs/informe_incidente.md`).

### Parte D — Protección de Datos: Anonimización y Equivalencia
- **Tabla anónima (`sql/usuario_anon.sql`):** Generación determinista de 20.000 registros sintéticos preservando identificadores subrogantes y el atributo estructural `activo`.
- **Demostración de equivalencia:** Consultas de agregación agrupadas por cohorte (`rol` y `mes_alta`) sobre `usuario_anon` y sobre `usuario` real. Se demostró igualdad absoluta con `EXCEPT` bidireccional (0 filas de discrepancia) en `docs/verificacion_equivalencia.md`.
- **Frontera de datos sensibles:** Redacción de las directrices de seguridad sobre qué datos jamás deben ser compartidos con asistentes externos de IA.

### Parte E — Consolidación de Bitácora y Control de Versiones
- **Tabla obligatoria de 3 columnas:** Registro completo en `BITACORA.md` de prompts, respuestas resumidas y validaciones/correcciones humanas.
- **Caso exigido de propuesta excesiva:** Documentación del rechazo al `GRANT TEMPORARY ON DATABASE` sugerido por la IA.
- **Caso más significativo de error:** Análisis del sesgo de plausibilidad alucinado por la IA en la Parte C.
- **Historial Git:** Árbol limpio con 5 commits atómicos descriptivos correspondientes a cada hito de avance.
