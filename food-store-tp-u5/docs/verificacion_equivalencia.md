# Verificación de equivalencia — Parte D

**Proyecto:** Food Store — Base de Datos II, Unidad 5
**Base:** `foodstore_u5_tp` · PostgreSQL 17
**Scripts:** `sql/usuario_anon.sql` · `docs/evidencias/verificacion_equivalencia.sql`
**Evidencia cruda:** `docs/evidencias/verificacion_equivalencia.txt`

---

## 1. Construcción de `usuario_anon`

Tabla anónima, **sintética y determinista** (patrón de la Clase 2): el mismo
`id` produce siempre el mismo valor. Se conservan el **identificador
subrogante** (`id`, clave de emparejamiento, no es PII) y el atributo
estructural **`activo`**; se reemplazan los datos personales:

| Columna real | Reemplazo sintético |
|---|---|
| `nombre` | nombre de pila de un arreglo fijo, elegido por `id % 6` |
| `apellido` | apellido de un arreglo fijo, elegido por `id % 6` |
| `email` | `'anon' || id || '@anon.invalid'` |
| `contrasena` | `md5('anon-' || id)` |

Las columnas de **cohorte** que se usan para agrupar (`rol`, `mes_alta`) se
derivan determinísticamente de `id` y quedan materializadas en
`usuario_anon`; sobre la tabla real se aplica la **misma** derivación.

> Nota de diseño: la tabla `usuario` del proyecto (Unidades 1–4) no tiene
> columnas `rol` ni fecha de alta; por eso las cohortes se derivan de forma
> determinística a partir de `id`, aplicando la **misma** fórmula a ambas
> tablas para que la comparación sea válida.

## 2. Consultas (generadas por el asistente a partir de los esquemas)

**Consulta 1 — sobre `usuario_anon`:**

```sql
SELECT rol, mes_alta, count(*) AS cantidad
FROM usuario_anon
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;
```

**Consulta 2 — equivalente sobre `usuario` real:**

```sql
SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1 + (id % 4)] AS rol,
       (id % 12) + 1                                                   AS mes_alta,
       count(*)                                                        AS cantidad
FROM usuario
GROUP BY 1, 2
ORDER BY rol, mes_alta;
```

## 3. Resultados lado a lado

Ambos conjuntos son **idénticos** (12 filas):

| rol | mes_alta | cantidad (anon) | cantidad (real) |
|---|---:|---:|---:|
| admin | 4 | 1667 | 1667 |
| admin | 8 | 1667 | 1667 |
| admin | 12 | 1666 | 1666 |
| comprador | 1 | 1666 | 1666 |
| comprador | 5 | 1667 | 1667 |
| comprador | 9 | 1667 | 1667 |
| soporte | 3 | 1667 | 1667 |
| soporte | 7 | 1667 | 1667 |
| soporte | 11 | 1666 | 1666 |
| vendedor | 2 | 1667 | 1667 |
| vendedor | 6 | 1667 | 1667 |
| vendedor | 10 | 1666 | 1666 |

Total de filas: `usuario` = **20000**, `usuario_anon` = **20000**.

## 4. Prueba de equivalencia (no solo afirmada)

```sql
SELECT 'anon EXCEPT real', count(*) FROM (
    SELECT rol, mes_alta, count(*) FROM usuario_anon GROUP BY 1,2
    EXCEPT
    SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1+(id%4)], (id%12)+1, count(*)
    FROM usuario GROUP BY 1,2) d
UNION ALL
SELECT 'real EXCEPT anon', count(*) FROM (
    SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1+(id%4)], (id%12)+1, count(*)
    FROM usuario GROUP BY 1,2
    EXCEPT
    SELECT rol, mes_alta, count(*) FROM usuario_anon GROUP BY 1,2) d;
```

Resultado:

```
    direccion     | filas_diferentes
------------------+------------------
 anon EXCEPT real |                0
 real EXCEPT anon |                0
```

**Conclusión:** anonimizar **no distorsiona** la información agregada. La
diferencia simétrica (`EXCEPT` en ambas direcciones) es **0 filas**: los
mismos grupos, con los mismos conteos.

## 5. Qué información de Food Store no debería salir hacia una IA sin anonimizar

Nunca deberían enviarse a un asistente de IA, sin pasar antes por este
proceso, los **datos personales identificables de `usuario`** (`nombre`,
`apellido`, `email`) y, muy especialmente, las **credenciales**
(`contrasena`/hashes) y cualquier dato que permita reidentificar a una
persona (los correos, por ejemplo, permiten cruzar con otras fuentes). Tampoco
los **extractos de datos de venta ligados a personas** (pedidos con
`usuario_id`) ni los **logs con sentencias en claro**, que exponen PII y
credenciales (ver Parte B/C). El criterio es: si un dato permite señalar a una
persona concreta, no sale sin anonimizar; los **agregados** sí pueden compartirse.
