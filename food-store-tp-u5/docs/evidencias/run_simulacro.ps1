# ============================================================
# Food Store - TP Unidad 5 - PARTE C
# run_simulacro.ps1: orquestador del simulacro de incidente.
# SOLO contra la base de desarrollo propia (foodstore_u5_tp).
#
# Secuencia:
#   1) marcador de inicio en el log
#   2) 3 intentos de login FALLIDOS a nivel motor como app_web
#   3) una sesion EXITOSA como app_web que ejecuta
#      simulacro_incidente.sql (intentos fn_autenticar + login ok +
#      lectura masiva + intento de escalamiento)
#   4) marcador de fin en el log
# ============================================================
$psql = "C:\Program Files\PostgreSQL\17\bin\psql.exe"
$env:PGCLIENTENCODING = "UTF8"
$db = "foodstore_u5_tp"

# --- Marcador de inicio ---
$env:PGPASSWORD = "barcala1947"
$env:PGAPPNAME  = "SIM_MARCA_INICIO"
& $psql -h localhost -U postgres -d $db -Atc "SELECT 1;" | Out-Null

# --- (1) Intentos fallidos de login (brute force a nivel motor) ---
$env:PGPASSWORD = "clave-incorrecta"
$env:PGAPPNAME  = "app_web_bruteforce"
for ($i = 1; $i -le 3; $i++) {
    & $psql -h localhost -U app_web -d $db -Atc "SELECT 1;" 2>&1 | Out-Null
}

# --- (2) Sesion exitosa del 'atacante' ejecutando el simulacro ---
$env:PGPASSWORD = "AppWeb#2026"
$env:PGAPPNAME  = "app_web_simulacro"
& $psql -h localhost -U app_web -d $db `
    -f "C:\Users\maxim\Desktop\U5DataBase\food-store-tp-u5\sql\simulacro_incidente.sql" `
    -o NUL 2>&1 | Out-Null

# --- Marcador de fin ---
$env:PGPASSWORD = "barcala1947"
$env:PGAPPNAME  = "SIM_MARCA_FIN"
& $psql -h localhost -U postgres -d $db -Atc "SELECT 1;" | Out-Null

Write-Output "Simulacro finalizado."
