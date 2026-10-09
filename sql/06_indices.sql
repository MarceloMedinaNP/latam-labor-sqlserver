/* =========================================================================
   06 - Índice y medición de rendimiento
   -------------------------------------------------------------------------
   Los reportes filtran por indicador y ordenan por año. La clave primaria
   empieza por país, así que no ayuda a esa búsqueda. Un índice no agrupado
   con INCLUDE cubre la consulta sin volver a la tabla.

   Con ~2.000 filas la diferencia es pequeña: el objetivo es practicar el
   método (medir, indexar, volver a medir), no el resultado.
   ========================================================================= */
USE LatamLabor;
GO

/* 1. Medición ANTES: ejecuta este bloque y mira la pestaña "Messages".
      Anota las "logical reads" de fct_participacion.
      En SSMS activa también "Include Actual Execution Plan" (Ctrl+M). */
SET STATISTICS IO ON;

SELECT anio, AVG(valor) AS promedio_regional
FROM dw.fct_participacion
WHERE indicador = 'femenina'
GROUP BY anio
ORDER BY anio;

SET STATISTICS IO OFF;
GO

/* 2. Crear el índice */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_fct_indicador_anio'
                 AND object_id = OBJECT_ID(N'dw.fct_participacion'))
    CREATE NONCLUSTERED INDEX IX_fct_indicador_anio
        ON dw.fct_participacion (indicador, anio)
        INCLUDE (valor);
GO

/* 3. Medición DESPUÉS: misma consulta. Compara las "logical reads" y mira
      en el plan que ahora usa "Index Seek" sobre IX_fct_indicador_anio. */
SET STATISTICS IO ON;

SELECT anio, AVG(valor) AS promedio_regional
FROM dw.fct_participacion
WHERE indicador = 'femenina'
GROUP BY anio
ORDER BY anio;

SET STATISTICS IO OFF;
GO
