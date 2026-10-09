/* =========================================================================
   02 - dw.usp_cargar_csv
   -------------------------------------------------------------------------
   Carga los dos CSV que genera fetch_worldbank.py en las tablas raw.
   Demuestra: SQL dinámico seguro, BULK INSERT, transacción,
              TRY/CATCH con ROLLBACK y registro en bitácora.

   Uso:
       EXEC dw.usp_cargar_csv @carpeta = N'/workspaces/latam-labor-sqlserver/data/raw';   -- Codespaces
       EXEC dw.usp_cargar_csv @carpeta = N'C:\datos\latam\raw';                         -- Windows

   Nota: la ruta se lee desde el servidor SQL. En el Codespace, la carpeta
   del proyecto está montada en el contenedor de SQL Server en la misma ruta.
   ========================================================================= */
USE LatamLabor;
GO

CREATE OR ALTER PROCEDURE dw.usp_cargar_csv
    @carpeta NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio      DATETIME2(0) = SYSDATETIME(),
            @sql         NVARCHAR(MAX),
            @ruta        NVARCHAR(500),
            @opciones    NVARCHAR(400),
            @filas_part  INT,
            @filas_pais  INT;

    -- Normaliza la carpeta para que termine en separador.
    -- Acepta rutas de Windows (C:\datos\...) y de Linux (/workspaces/...).
    DECLARE @sep NCHAR(1) = CASE WHEN CHARINDEX(N'/', @carpeta) > 0 THEN N'/' ELSE N'\' END;
    IF RIGHT(@carpeta, 1) NOT IN (N'/', N'\') SET @carpeta += @sep;

    -- Opciones comunes de BULK INSERT.
    -- ROWTERMINATOR 0x0a acepta archivos con fin de línea LF o CRLF;
    -- el CR sobrante se limpia después, en la transformación.
    SET @opciones = N' WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'', '
                  + N'ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', TABLOCK);';

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE raw.participacion;
        TRUNCATE TABLE raw.paises;

        -- La ruta se escapa duplicando comillas simples (evita inyección SQL)
        SET @ruta = REPLACE(@carpeta + N'participacion.csv', N'''', N'''''');
        SET @sql  = N'BULK INSERT raw.participacion FROM ''' + @ruta + N'''' + @opciones;
        EXEC sys.sp_executesql @sql;

        SET @ruta = REPLACE(@carpeta + N'paises.csv', N'''', N'''''');
        SET @sql  = N'BULK INSERT raw.paises FROM ''' + @ruta + N'''' + @opciones;
        EXEC sys.sp_executesql @sql;

        SELECT @filas_part = COUNT(*) FROM raw.participacion;
        SELECT @filas_pais = COUNT(*) FROM raw.paises;

        IF @filas_part = 0 OR @filas_pais = 0
            THROW 50001, N'Uno de los CSV llegó vacío. Revisa la carpeta y los archivos.', 1;

        COMMIT TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_cargar_csv', @inicio, SYSDATETIME(), @filas_part + @filas_pais, N'OK',
                CONCAT(N'participacion: ', @filas_part, N' filas; paises: ', @filas_pais, N' filas'));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_cargar_csv', @inicio, SYSDATETIME(), NULL, N'ERROR', ERROR_MESSAGE());

        THROW;   -- relanza el error original a quien llamó
    END CATCH
END;
GO
