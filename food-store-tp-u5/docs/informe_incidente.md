# Informe de incidente — Parte C

**Proyecto:** Food Store — Base de Datos II, Unidad 5
**Base:** `foodstore_u5_tp` (entorno de desarrollo propio) · PostgreSQL 17
**Script:** `sql/simulacro_incidente.sql` · **Orquestador:** `docs/evidencias/run_simulacro.ps1`
**Log anonimizado:** `docs/log_simulacro_anonimizado.txt`

> **Alcance ético.** Todo el simulacro se ejecutó **exclusivamente** contra la
> instancia de Food Store propia en el entorno de desarrollo. No se probó
> ninguna técnica contra sistemas de terceros.

---

## 1. Secuencia reproducida

`run_simulacro.ps1` orquesta, con marcadores `SIM_MARCA_INICIO`/`SIM_MARCA_FIN`
en el log, la siguiente cadena (el "kill chain" completo):

1. **Intentos fallidos de inicio de sesión:** tres conexiones de `app_web` con
   contraseña incorrecta (FATAL a nivel motor) y tres llamadas a
   `fn_autenticar` con contraseña inválida (fallo a nivel aplicación).
2. **Inicio de sesión exitoso:** conexión válida como `app_web`
   (`application_name=app_web_simulacro`) y `fn_autenticar` con la contraseña
   correcta.
3. **Lectura masiva de `usuario`:** `SELECT count(*) FROM usuario` y
   `SELECT id, nombre, apellido, email FROM usuario ORDER BY id;` (exfiltración
   de PII).
4. **Intento de escalamiento:** `GRANT admin_datos TO app_web;` y, como
   operación reservada adicional, `CREATE TABLE backdoor_persistencia (id INT);`.

Para poder reconstruir la lectura (los `SELECT` no se registran con nivel
`mod`) se elevó temporalmente `log_statement` a `'all'` durante el simulacro.
Esta es una medida de investigación razonable y se documenta aquí.

## 2. Verificación de que el escalamiento FALLA

Evidencia textual del log (base correcta → sin hallazgo de defecto en la
Parte A):

```
2026-10-19 16:53:10.405 [20948] app_web@foodstore_u5_tp ::1 LOG:  sentencia: GRANT admin_datos TO app_web;
2026-10-19 16:53:10.408 [20948] app_web@foodstore_u5_tp ::1 ERROR:  se ha denegado el permiso para otorgar el rol «admin_datos»
2026-10-19 16:53:10.408 [20948] app_web@foodstore_u5_tp ::1 DETALLE:  Sólo los roles con la opción ADMIN en el rol «admin_datos» pueden otorgar este rol.
2026-10-19 16:53:10.410 [20948] app_web@foodstore_u5_tp ::1 LOG:  sentencia: CREATE TABLE backdoor_persistencia (id INT);
2026-10-19 16:53:10.411 [20948] app_web@foodstore_u5_tp ::1 ERROR:  permiso denegado al esquema public en carácter 14
```

**Conclusión:** ambos intentos fueron **denegados** por el esquema de permisos
de la Parte A (sin `ADMIN OPTION` sobre `admin_datos` y sin `CREATE` sobre el
esquema `public`). **No hay defecto de permisos que corregir.** La única
debilidad real observada es que `app_web` puede leer la tabla `usuario`
completa (aunque **no** la columna `contrasena`).

## 3. Anonimización del log

El fragmento (`docs/log_simulacro_anonimizado.txt`) se anonimizó **antes** de
enviárselo a la IA, siguiendo el criterio de `usuario_anon` de la Clase 2:

| Dato original | Valor sintético |
|---|---|
| `usuario1@mail.com` | `anon_001@example.test` |
| `clave-incorrecta-1/2/3` | `pwd-fallida-A/B/C` |
| `seed-1` (password real del seed) | `pwd-valida-X` |

Los puertos, pids y timestamps se conservaron (no son datos personales y son
necesarios para la reconstrucción temporal).

## 4. Reconstrucción de la IA (respuesta completa)

La IA recibió **únicamente** el fragmento anonimizado, sin contexto adicional
(ni el script, ni los nombres de archivos, ni la explicación del trabajo), y se
le pidió reconstruir lo ocurrido y proponer una contención. Respuesta íntegra:

> **Relato cronológico.** Todo ocurre el 2026-10-19 en apenas 493 ms
> (16:53:09.985 a 16:53:10.478), y todas las conexiones llegan desde `::1`
> (loopback). 1) Se abre la ventana con una conexión de `postgres`
> (`SIM_MARCA_INICIO`) que ejecuta `SELECT 1` y se desconecta. 2) Tres
> conexiones consecutivas fallan la autenticación de `app_web` (~15 ms cada
> una, ~70 ms de separación): patrón de reintentos. 3) Una cuarta conexión
> autentica bien y ejecuta: cuatro llamadas a `fn_autenticar` (tres con
> contraseñas fallidas y una válida), `SELECT count(*)` y volcado de
> `id, nombre, apellido, email` de toda la tabla `usuario`, `GRANT admin_datos
> TO app_web` (denegado), `CREATE TABLE backdoor_persistencia` (denegado).
> 4) Una conexión final de `postgres` (`SIM_MARCA_FIN`) cierra la ventana.
> Interpretación: firma de un simulacro/prueba de intrusión controlada;
> cadena *acceso inicial → fuerza bruta → login válido → exfiltración de PII →
> escalada → persistencia*, con las dos últimas etapas frenadas. La debilidad
> demostrada es que `app_web` puede leer toda la tabla de usuarios y que la
> ventana de login no muestra freno.
>
> **Contención propuesta.** Inmediato: `pg_terminate_backend(20948)` y
> `ALTER ROLE app_web NOLOGIN`; rotar la contraseña de `app_web`; revisar
> `pg_auth_members`/`pg_roles` por intentos exitosos. Corto plazo: auditar el
> histórico de `app_web`; recortar su `SELECT` sobre `usuario`; agregar límite
> de intentos en `fn_autenticar`; revisar `pg_hba.conf` línea 117. Estructural:
> activar `pgAudit`, y **corregir el registro de sentencias en claro** (el log
> expone contraseñas y PII: por sí solo es un incidente).
>
> **Confianza.** Alta (~80%) en la secuencia y en que escalada y persistencia
> fueron bloqueadas; moderada (~65-70%) en que sea un simulacro autorizado.
> **No puede afirmar:** quién lo ejecutó, si la ventana está completa, si
> `fn_autenticar` devolvió éxito o fallo (solo se registran sentencias, no
> resultados), si los datos realmente salieron, ni si hubo éxito en otra
> sesión/momento.

## 5. Contraste: reconstrucción de la IA vs. lo realmente ejecutado

**Qué acertó:**

- La **secuencia de eventos** y el orden (fallos → login → volcado →
  escalada → persistencia), la marca temporal (~0,5 s) y el origen loopback.
- Que **la escalada y la persistencia fueron bloqueadas**: coincide con el
  punto §2 (verificado por el equipo).
- Que el **flag `app_web` puede leer `usuario` completo** es la debilidad real.
- Un hallazgo de valor no pedido: **el propio log expone credenciales y PII en
  claro** (coincide con la Parte B punto 4: el log es un activo sensible).

**Qué omitió:**

- No advirtió que la lectura masiva lista **solo**
  `id, nombre, apellido, email` y **no** `contrasena`: es evidencia de que la
  **restricción a nivel de columna de la Parte A funcionó** y el dato más
  sensible no se exfiltró. La IA describió un "volcado de datos personales"
  sin notar ese límite.
- No mencionó que las conexiones `SIM_MARCA_INICIO`/`SIM_MARCA_FIN` son
  marcadores de harness (lo intuyó como "marca/clavel", pero no lo concluyó
  del formato).

**Afirmaciones que el log NO sustenta (error a destacar):**

- La IA afirmó que de las cuatro llamadas a `fn_autenticar` **"tres
  contraseñas fallidas y una válida"**. **El log no registra los valores de
  retorno** de la función: solo registra el *texto* de las sentencias. La IA
  se apoyó en las **etiquetas sintéticas** `pwd-fallida-*`/`pwd-valida-X` que
  introdujo la anonimización, no en evidencia del log. Es más: párrafos
  después la propia IA admite que "el log no permite saber si `fn_autenticar`
  devolvió éxito o fallo" — una **contradicción interna**. Este es el caso más
  significativo: muestra que un valor sintético "demasiado explicativo" puede
  inducir a la IA a afirmar como observado algo que en realidad infirió.
- Calificó los reintentos como "patrón de reintentos automáticos": la
  separación de ~70 ms es un **artefacto del orquestador**, no un rasgo
  observado del atacante. La afirmación sobre "fuerza bruta" es plausible pero
  no probada por el log.

## 6. Decisión de contención del equipo

**La decisión es del equipo, tomada a partir de la evidencia, y no se ejecutó
automáticamente ninguna acción sugerida por la IA.** Por tratarse de un
**simulacro controlado**, no se aplicó ninguna contención real; se deja
asentado qué haría el equipo ante un caso real:

1. **Rotar la credencial de `app_web`**, no solo bloquearla: el log muestra un
   login **exitoso**, es decir que la credencial era válida y conocida por el
   actor. (`ALTER ROLE app_web PASSWORD '…'`, no `NOLOGIN` permanente.)
2. **Revisar el alcance de lectura** de `app_web` sobre `usuario`. La brecha
   demostrada es la lectura de PII en masa; se evaluaría exponer solo vistas
   (`v_usuarios_sin_contrasena`) en lugar de la tabla. **No** se revoca la
   restricción de columna: funcionó y se mantiene.
3. **Rate limiting / bloqueo por intentos** en `fn_autenticar` (bloqueo
   temporal por email), más alerta sobre ráfagas de `FATAL` de autenticación.
4. **Preservar y restringir el log** como evidencia (permisos de SO), dado que
   el propio log es un activo sensible.
5. **Verificar** que no existan rastros de escalada exitosa fuera de la ventana
   (`pg_auth_members`, `pg_roles`, objetos nuevos) — en este simulacro no los
   hay.

Se **descarta** ejecutar a ciegas lo sugerido por la IA (p. ej.
`pg_terminate_backend` sobre un pid cuya sesión ya había terminado): el
remediar sin verificar el estado es, en sí mismo, un riesgo.
