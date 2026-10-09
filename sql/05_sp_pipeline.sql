/* =========================================================================
   05 - dw.usp_pipeline
   -------------------------------------------------------------------------
   Ejecuta el flujo completo en orden: carga -> transformación -> refresco.
   Si un paso falla, se detiene y el error queda en la bitácora.
   Demuestra: orquestación de procedimientos y manejo de errores en cadena.

   Uso:
       EXEC dw.usp_pipeline @carpeta = N'/workspaces/latam-labor-sqlserver/data/raw';
   ========================================================================= */
USE LatamLabor;
GO

CREATE OR ALTER PROCEDURE dw.usp_pipeline
    @carpeta NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio DATETIME2(0) = SYSDATETIME(),
            @paso   NVARCHAR(100);

    BEGIN TRY
        SET @paso = N'usp_cargar_csv';
        EXEC dw.usp_cargar_csv @carpeta = @carpeta;

        SET @paso = N'usp_transformar';
        EXEC dw.usp_transformar;

        SET @paso = N'usp_refrescar_brecha';
        EXEC rpt.usp_refrescar_brecha;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_pipeline', @inicio, SYSDATETIME(), NULL, N'OK', N'Pipeline completo');
    END TRY
    BEGIN CATCH
        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_pipeline', @inicio, SYSDATETIME(), NULL, N'ERROR',
                CONCAT(N'Falló en el paso ', @paso, N': ', ERROR_MESSAGE()));
        THROW;
    END CATCH

    -- Resumen de esta ejecución
    SELECT proceso, inicio, fin, filas, estado, mensaje
    FROM dw.log_carga
    WHERE inicio >= @inicio
    ORDER BY id;
END;
GO
