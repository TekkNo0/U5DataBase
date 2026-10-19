# Spec (Kiro) — Esquema de roles y permisos de Food Store

**Proyecto:** Food Store — Base de Datos II, Unidad 5, Parte A
**Motor:** PostgreSQL 17
**Objetivo:** definir, con el principio de mínimo privilegio, los roles que
necesita Food Store y el privilegio exacto que recibe cada uno. Cada permiso
existe porque habilita una operación concreta y necesaria; nada se otorga
"por comodidad".

> Esta spec se redacta **antes** de escribir `roles.sql`. Justificar cada
> permiso *antes* de otorgarlo es, en sí mismo, una aplicación de mínimo
> privilegio: no se otorga primero y se justifica después.

## Glosario

- **Rol de grupo (NOLOGIN):** agrupa privilegios. No se conecta; se hereda.
- **Rol de login (LOGIN):** identidad con la que un proceso o persona se
  autentica contra el motor. Es miembro de uno o más roles de grupo.
- **Mínimo privilegio:** cada identidad recibe *solo* los privilegios que su
  función exige, ni uno más.

## R1 — Catálogo de roles

El esquema DEBE definir, como mínimo, estos roles:

| Rol | Tipo | Función |
|---|---|---|
| `rol_app_lectura` | grupo | Lectura del negocio para la aplicación. |
| `rol_app_escritura` | grupo | Lectura + escritura transaccional de la aplicación. |
| `rol_soporte` | grupo | Operación de soporte sobre pedidos/catálogo. |
| `rol_reportes` | grupo | Lectura agregada para reporting; sin datos sensibles. |
| `rol_auditor` | grupo | Lectura forense de rendición de cuentas (rol adicional). |
| `app_web` | login | Identidad del backend web. |
| `admin_datos` | login | Administración de datos del negocio. |
| `auditor_sec` | login | Identidad del analista de seguridad (rol adicional). |

### R1.1 — Justificación por rol (una oración cada uno)

- `rol_app_lectura`: habilita `SELECT` sobre catálogo y ventas porque el
  frontend necesita mostrar productos y pedidos, y **no** otras operaciones.
- `rol_app_escritura`: habilita `INSERT/UPDATE/DELETE` sobre pedidos y líneas
  porque el checkout crea y modifica pedidos, y nada más.
- `rol_soporte`: habilita `UPDATE` acotado a columnas de estado
  (`pedido.estado`, `producto.activo`) porque soporte corrige estado/vigencia,
  no montos ni datos personales.
- `rol_reportes`: habilita `SELECT` sobre vistas y agregados porque BI consume
  resultados ya resumidos y no debe tocar tablas crudas de usuarios.
- `rol_auditor`: habilita `SELECT` de lectura sobre pedidos y sobre `usuario`
  **sin** `contrasena`, porque auditar exige reconstruir quién hizo qué sin
  exponer credenciales.
- `app_web`: es la única identidad de login que hereda `rol_app_escritura`,
  porque es el único cliente que ejecuta la lógica transaccional.
- `admin_datos`: recibe privilegios amplios sobre el esquema de negocio
  (no superusuario) porque administra datos; es el objetivo legítimo del
  intento de escalamiento de la Parte C.
- `auditor_sec`: hereda `rol_auditor` porque el analista de seguridad solo
  necesita lectura forense.

## R2 — Privilegio a nivel de columna

El esquema DEBE restringir `usuario.contrasena` mediante privilegios a nivel
de columna. Ningún rol de aplicación (`rol_app_lectura`, `rol_soporte`,
`rol_auditor`, `rol_reportes`, `app_web`, `auditor_sec`) DEBE poder leer
`usuario.contrasena`.

**Criterio de aceptación:** `SELECT contrasena FROM usuario` ejecutado como
`app_web` falla con `permission denied for column contrasena`.

## R3 — Membresías

- `app_web` ES miembro de `rol_app_escritura` (que a su vez hereda
  `rol_app_lectura`).
- `auditor_sec` ES miembro de `rol_auditor`.
- Ningún rol de grupo se conecta (`NOLOGIN`).

## R4 — Herencia de política para objetos futuros

El esquema DEBE declarar `ALTER DEFAULT PRIVILEGES` para que las tablas y
secuencias creadas a futuro hereden la misma política, sin re-otorgar a mano.

## R5 — Endurecimiento del esquema

El esquema DEBE revocar `CREATE` sobre el esquema `public` de `PUBLIC`, para
que ningún rol de aplicación pueda crear objetos.

## R6 — Verificabilidad

Los privilegios otorgados DEBEN poder verificarse con `\du` y con una
consulta a `information_schema.role_table_grants` que demuestre que cada rol
tiene **exactamente** los privilegios previstos — ni más, ni menos.

## R7 — Registro de la auditoría de la IA

La revisión de `roles.sql` por parte del asistente (OpenCode) DEBE quedar
registrada en `BITACORA.md`, señalando al menos un caso en que la IA propuso
un privilegio **más amplio** de lo necesario y el equipo decidió no aplicarlo.
