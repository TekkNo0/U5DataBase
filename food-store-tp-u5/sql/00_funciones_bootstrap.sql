-- ============================================================
-- Food Store - TP Unidad 5
-- 00_funciones_bootstrap.sql
-- Reconstruccion de artefactos de la Clase 2 que no se
-- conservaron: fn_autenticar y fn_resetear_password.
-- (El enunciado autoriza reconstruirlos como paso previo a la
--  Parte A; la reconstruccion se deja asentada en BITACORA.md.)
-- Ejecutar como postgres sobre foodstore_u5_tp.
-- ============================================================
BEGIN;

-- ------------------------------------------------------------
-- fn_autenticar: valida credenciales contra usuario.
-- SECURITY DEFINER: se ejecuta con los privilegios del duenio
-- (postgres), lo que le permite leer usuario.contrasena aunque
-- el rol que la invoca (p. ej. app_web) no tenga ese privilegio
-- de columna. Devuelve TRUE solo si el email existe, la cuenta
-- esta activa y el hash del password coincide.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_autenticar(p_email TEXT, p_contrasena TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hash   TEXT;
    v_activo BOOLEAN;
BEGIN
    SELECT contrasena, activo
      INTO v_hash, v_activo
      FROM usuario
     WHERE email = p_email;

    IF NOT FOUND THEN
        RETURN FALSE;           -- usuario inexistente
    END IF;
    IF NOT v_activo THEN
        RETURN FALSE;           -- cuenta dada de baja
    END IF;

    -- Patron de la catedra: la columna guarda md5(password plano).
    RETURN v_hash = md5(p_contrasena);
END;
$$;

-- ------------------------------------------------------------
-- fn_resetear_password: fija una nueva contrasena (hasheada).
-- Devuelve TRUE si el email existia y se actualizo.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resetear_password(p_email TEXT, p_nueva TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE usuario
       SET contrasena = md5(p_nueva)
     WHERE email = p_email;
    RETURN FOUND;
END;
$$;

-- El uso de las funciones se autoriza a los roles de aplicacion.
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT)        TO rol_app_escritura, rol_soporte;
GRANT EXECUTE ON FUNCTION fn_resetear_password(TEXT, TEXT) TO rol_app_escritura;

COMMIT;
