-- Parte D: equivalencia de agregados entre usuario_anon y usuario real.

\echo '=== CONSULTA 1 - sobre usuario_anon (por rol y mes_alta) ==='
SELECT rol, mes_alta, count(*) AS cantidad
FROM usuario_anon
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;

\echo '=== CONSULTA 2 - equivalente sobre usuario real ==='
SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1 + (id % 4)] AS rol,
       (id % 12) + 1                                                   AS mes_alta,
       count(*)                                                        AS cantidad
FROM usuario
GROUP BY 1, 2
ORDER BY rol, mes_alta;

\echo '=== PRUEBA DE EQUIVALENCIA (EXCEPT en ambas direcciones; se esperan 0) ==='
SELECT 'anon EXCEPT real' AS direccion, count(*) AS filas_diferentes FROM (
    SELECT rol, mes_alta, count(*) AS cantidad FROM usuario_anon GROUP BY 1, 2
    EXCEPT
    SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1 + (id % 4)],
           (id % 12) + 1, count(*)
    FROM usuario GROUP BY 1, 2
) d
UNION ALL
SELECT 'real EXCEPT anon', count(*) FROM (
    SELECT (ARRAY['comprador','vendedor','soporte','admin'])[1 + (id % 4)],
           (id % 12) + 1, count(*)
    FROM usuario GROUP BY 1, 2
    EXCEPT
    SELECT rol, mes_alta, count(*) FROM usuario_anon GROUP BY 1, 2
) d;

\echo '=== CONTROL: total de filas en ambas tablas ==='
SELECT (SELECT count(*) FROM usuario)      AS total_real,
       (SELECT count(*) FROM usuario_anon) AS total_anon;
