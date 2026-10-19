# Design (Kiro) — Esquema de roles y permisos de Food Store

**Deriva de:** `requirements.md`
**Artefacto que produce:** `sql/roles.sql`

## 1. Inventario de objetos (esquema `public`, base `foodstore_u5_tp`)

Tablas de negocio:

`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`,
`deposito`, `lote`, `deposito_responsable`, `control_lote_responsable`,
`control_lote_almacen_compat`, `venta_categoria_diaria`.

Vistas de seguridad / reporting:

`v_productos_vigentes`, `v_pedidos_usuario`, `v_detalle_pedido_producto`,
`v_usuarios_sin_contrasena`.

Secuencias transaccionales: `usuario_id_seq`, `pedido_id_seq`,
`detalle_pedido_id_seq`.

> Se trabaja sobre una **copia** (`foodstore_u5_tp`, creada con
> `TEMPLATE foodstore_u4`) según el protocolo de seguridad del proyecto.

## 2. Matriz de privilegios

| Objeto | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` | `rol_auditor` | `admin_datos` |
|---|---|---|---|---|---|---|
| `categoria` | SELECT | SELECT | SELECT | — | — | ALL |
| `producto` | SELECT | SELECT | SELECT, UPDATE(activo) | — | — | ALL |
| `usuario` (sin `contrasena`) | SELECT cols | SELECT cols + INSERT, UPDATE | SELECT cols | — | SELECT cols | ALL |
| `pedido` | SELECT | SELECT, INSERT, UPDATE, DELETE | SELECT, UPDATE(estado) | — | SELECT | ALL |
| `detalle_pedido` | SELECT | SELECT, INSERT, UPDATE, DELETE | SELECT | — | SELECT | ALL |
| `deposito`, `lote`, `*_responsable`, `control_lote_*` | SELECT | — | SELECT | — | — | ALL |
| `venta_categoria_diaria` | — | — | SELECT | SELECT | — | ALL |
| vistas `v_*` | — | — | — | SELECT | SELECT | ALL |
| secuencias tx | — | USAGE | — | — | — | ALL |

Convenciones de la matriz:

- **`SELECT cols`** = `GRANT SELECT (id, nombre, apellido, email, activo) ON
  usuario` — **excluye `contrasena`** (R2).
- **`UPDATE(col)`** = privilegio a nivel de columna (sin `SELECT` de la fila).
- **`—`** = sin privilegio alguno (mínimo privilegio).
- `admin_datos` = `ALL` sobre el esquema de negocio, **no** superusuario.

## 3. Grafo de membresías

```
app_web  ──miembro──▶ rol_app_escritura ──miembro──▶ rol_app_lectura
auditor_sec ──miembro──▶ rol_auditor
admin_datos (privilegios directos sobre el esquema, sin grupo)
```

## 4. Orden de ejecución de `roles.sql`

1. **Limpieza idempotente:** `DROP OWNED BY` + `DROP ROLE IF EXISTS` de los
   roles de login y de grupo (permite re-ejecutar el script sin errores).
2. **Creación** de roles de grupo (`NOLOGIN`) y de login (`LOGIN PASSWORD`).
3. **Membresías** (`GRANT rol … TO …`).
4. **Privilegios de objeto** (tablas, columnas, secuencias, vistas).
5. **`REVOKE` explícitos** (columna sensible y `CREATE ON SCHEMA public FROM
   PUBLIC`).
6. **`ALTER DEFAULT PRIVILEGES`** para objetos futuros.

## 5. Decisiones de diseño y su justificación

- **DDL por columnas en lugar de tabla completa** para `usuario`: es la única
  forma en PostgreSQL de impedir la lectura de `contrasena` sin dejar de leer
  el resto del registro (un `GRANT SELECT` a nivel tabla expone todas las
  columnas).
- **`UPDATE` a nivel de columna** en `rol_soporte`: corrige estados sin poder
  alterar montos ni datos personales.
- **`rol_reportes` solo ve vistas y agregados:** el reporting nunca necesita
  PII cruda; consumir `v_usuarios_sin_contrasena` reduce la superficie.
- **`admin_datos` sin `SUPERUSER`:** administra datos, no el motor; un
  administrador de datos comprometido no debe poder reescribir la seguridad.
- **`ALTER DEFAULT PRIVILEGES`:** evita que una tabla nueva creada por
  `postgres` quede, por omisión, inaccesible para unos o abierta para otros.

## 6. Criterios de verificación (R6)

1. `\du` muestra cada rol con su tipo y membresías.
2. `information_schema.role_table_grants` (filtrado a los roles del TP)
   reproduce exactamente la matriz de §2.
3. Pruebas negativas:
   - `SET ROLE app_web; SELECT contrasena FROM usuario;` → **falla**.
   - `SET ROLE app_web; GRANT admin_datos TO app_web;` → **falla**
     (sin `ADMIN OPTION`).
