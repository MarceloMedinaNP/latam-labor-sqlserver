/* =========================================================================
   99 - Pruebas
   -------------------------------------------------------------------------
   En el Codespace:  python scripts/run_sql.py --seguir sql/99_pruebas.sql
   (--seguir hace que continúe después de los errores provocados a propósito)
   En SSMS: ejecuta cada bloque por separado y usa la ruta de Windows.
   ========================================================================= */
USE LatamLabor;
GO

/* 1. Pipeline completo ---------------------------------------------------- */
EXEC dw.usp_pipeline @carpeta = N'/workspaces/latam-labor-sqlserver/data/raw';
GO

/* 2. Conteos esperados ----------------------------------------------------
      dim_pais: 20 filas. fct_participacion: hasta 2.160 (20 x 36 x 3),
      menos los años sin dato. */
SELECT 'dim_pais' AS tabla, COUNT(*) AS filas FROM dw.dim_pais
UNION ALL
SELECT 'fct_participacion', COUNT(*) FROM dw.fct_participacion
UNION ALL
SELECT 'brecha_genero', COUNT(*) FROM rpt.brecha_genero;
GO

/* 3. Reporte parametrizado ------------------------------------------------ */
EXEC rpt.usp_indicadores_pais @pais = 'BOL';
EXEC rpt.usp_indicadores_pais @pais = 'BOL', @desde = 2015, @hasta = 2025;
EXEC rpt.usp_indicadores_pais @pais = 'PER', @indicador = 'masculina';
GO

/* 4. Validación de parámetros: estos DEBEN fallar con un mensaje claro ---- */
EXEC rpt.usp_indicadores_pais @pais = 'XXX';                    -- país inexistente
GO
EXEC rpt.usp_indicadores_pais @pais = 'BOL', @desde = 2020, @hasta = 2010;  -- rango invertido
GO

/* 5. Idempotencia: correr el pipeline otra vez no duplica nada ------------
      Los conteos del paso 2 deben quedar iguales, y la bitácora debe decir
      0 filas nuevas o cambiadas en usp_transformar. */
EXEC dw.usp_pipeline @carpeta = N'/workspaces/latam-labor-sqlserver/data/raw';
GO

/* 6. Manejo de errores: una carpeta que no existe ------------------------
      Debe fallar, y la bitácora debe registrar el ERROR. */
EXEC dw.usp_pipeline @carpeta = N'/workspaces/carpeta/que/no/existe';
GO

/* 7. Bitácora ------------------------------------------------------------- */
SELECT TOP (20) * FROM dw.log_carga ORDER BY id DESC;
GO

/* 8. El hallazgo: ranking de participación femenina, último año ---------- */
SELECT TOP (5) country_name, anio, participacion_femenina, brecha_pp, ranking_femenino
FROM rpt.brecha_genero
WHERE anio = (SELECT MAX(anio) FROM rpt.brecha_genero)
ORDER BY ranking_femenino;
GO
