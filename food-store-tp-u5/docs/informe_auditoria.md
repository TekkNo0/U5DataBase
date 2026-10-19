# Informe de auditoría — Parte B

**Proyecto:** Food Store — Base de Datos II, Unidad 5
**Base:** `foodstore_u5_tp` (copia de trabajo) · **Motor:** PostgreSQL 17 · **SO:** Windows
**Script de configuración:** `sql/auditoria_config.sql`
**Script de prueba:** `sql/auditoria_test.sql`
**Evidencia:** `docs/log_auditoria_prueba.txt`

---

## 1. Parámetros de auditoría modificados

Se aplicaron con `ALTER SYSTEM` (persisten en `postgresql.auto.conf`) y se
recargaron con `SELECT pg_reload_conf();` **sin reiniciar** el servidor.

| Parámetro | Valor previo | Valor nuevo | Por qué |
|---|---|---|---|
| `log_connections` | `off` | `on` | Registrar cada intento/establecimiento de conexión (origen, usuario). |
| `log_disconnections` | `off` | `on` | Registrar el cierre de sesión y su duración. |
| `log_statement` | `none` | `mod` | Registrar `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `COPY` y DDL. |
| `log_line_prefix` | `%t ` | `%m [%p] %q%u@%d %h ` | Añadir pid, usuario, base y host remoto a cada línea (quién/desde dónde/cuándo). |

Valores efectivos verificados con `SHOW`:

```
log_connections   = on
log_disconnections = on
log_statement     = mod
log_line_prefix   = %m [%p] %q%u@%d %h
```

> `log_statement = 'mod'` fue la decisión de mínimo privilegio de logging:
> registra **modificaciones**, que es el nivel pedido. No registra `SELECT`
> (ver §3).

## 2. Secuencia de prueba y fragmento de log

Script `sql/auditoria_test.sql` ejecutado como el rol de login `app_web`
(u: `app_web`, base `foodstore_u5_tp`). Contiene las cuatro operaciones
pedidas:

1. **Lectura** — `SELECT count(*) … FROM pedido`
2. **Inserción** — `INSERT INTO pedido (…) VALUES (1, 0, 'PENDIENTE');`
3. **Actualización** — `UPDATE pedido SET total = 123.45 …`
4. **Login fallido** — conexión de `app_web` con contraseña incorrecta.

La transacción se cierra con `ROLLBACK`: el objetivo era dejar traza, no
persistir datos.

Fragmento resultante (`docs/log_auditoria_prueba.txt`, entre los marcadores
`MARCA_INICIO_AUDITORIA` y `MARCA_FIN_AUDITORIA`):

```
2026-10-19 16:41:04.729 [19316] app_web@foodstore_u5_tp ::1 LOG:  conexión autenticada: identidad=«app_web» método=scram-sha-256 (…pg_hba.conf:117)
2026-10-19 16:41:04.729 [19316] app_web@foodstore_u5_tp ::1 LOG:  conexión autorizada: usuario=app_web base_de_datos=foodstore_u5_tp nombre_de_aplicación=app_web_tp_u5
2026-10-19 16:41:04.733 [19316] app_web@foodstore_u5_tp ::1 LOG:  sentencia: INSERT INTO pedido (usuario_id, total, estado)
	VALUES (1, 0, 'PENDIENTE');
2026-10-19 16:41:04.747 [19316] app_web@foodstore_u5_tp ::1 LOG:  sentencia: UPDATE pedido
	SET total = 123.45
	WHERE id = (SELECT max(id) FROM pedido);
2026-10-19 16:41:04.755 [19316] app_web@foodstore_u5_tp ::1 LOG:  desconexión: duración de sesión: 0:00:00.050 usuario=app_web base=foodstore_u5_tp host=::1 port=58700
2026-10-19 16:41:04.896 [20096] app_web@foodstore_u5_tp ::1 FATAL:  la autentificación password falló para el usuario «app_web»
2026-10-19 16:41:04.896 [20096] app_web@foodstore_u5_tp ::1 DETALLE:  La conexión coincidió con el archivo «…pg_hba.conf» línea 117: «host all all ::1/128 scram-sha-256»
```

## 3. Qué es útil para auditoría y qué queda fuera de alcance

**Útil (quién / qué / cuándo / desde dónde):**

- **Cuándo:** el prefijo `%m` da fecha-hora con milisegundos en cada línea;
  la duración de sesión permite acotar ventanas de actividad.
- **Quién:** `%u@%d` identifica usuario y base; el nombre de aplicación
  (`app_web_tp_u5`) identifica el cliente lógico.
- **Desde dónde:** `%h` registra el host remoto (`::1`, o una IP real).
- **Qué:** `log_statement=mod` guarda el **texto** del `INSERT`/`UPDATE`
  (y DDL). El `FATAL` de autenticación deja constancia del login fallido y
  de la regla de `pg_hba.conf` aplicada.

**Fuera de alcance de este mecanismo nativo:**

- Los **`SELECT` no se registran** con nivel `mod`. La lectura
  `SELECT count(*) … FROM pedido` de la secuencia **no aparece** en el log:
  el log nativo no responde "quién leyó qué". Para eso haría falta
  `pgAudit` (o `log_statement='all'`, más intrusivo).
- No hay **detalle fila por fila ni valores antes/después**: se ve la
  sentencia, no el estado previo de la fila. Reconstruir un cambio exacto
  exige correlacionar tablas de historial propias (triggers de auditoría).
- No hay **contexto de negocio** (por qué se ejecutó) ni un vínculo
  garantizado entre la sesión y la persona física detrás del login; solo la
  identidad de base.

> **`pgAudit` (a nivel de nociones):** es una extensión que extiende la
> auditoría nativa a nivel de **objeto y sesión** (p. ej. auditar `SELECT`
> sobre `usuario`), con control fino por rol y por tabla, produciendo
> registros legibles para rendición de cuentas. Complementa —no reemplaza—
> el logging nativo aquí activado.

## 4. ¿El archivo de log es un activo sensible?

**Sí.** El log es en sí mismo un activo sensible: contiene identidades
(usuarios, bases, hosts de origen), el **texto de las sentencias**
—que puede incluir datos personales en los `WHERE`/`INSERT`— y errores que
revelan estructura interna.

Deberían poder leerlo **solo** los administradores de la base y el rol de
seguridad/auditoría, y la protección es fundamentalmente del **sistema
operativo**: el directorio de logs
(`…/PostgreSQL/17/data/log/`) debe tener ACL de NTFS que excluyan a usuarios
comunes y permitan lectura solo a la cuenta del servicio PostgreSQL y al
grupo de administradores de BD. A nivel **motor**, no existe un privilegio
SQL para leer los archivos de log; sí existen funciones como
`pg_read_file()`/`pg_read_server_files` **reservadas a superusuario**, que
por eso conviene no otorgar. En síntesis: el log se protege con permisos de
SO y no se expone vía SQL.
