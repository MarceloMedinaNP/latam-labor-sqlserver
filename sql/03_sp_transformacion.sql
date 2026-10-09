/* =========================================================================
   03 - dw.usp_transformar
   -------------------------------------------------------------------------
   Valida los datos de raw y los pasa a las tablas tipadas de dw.
   Demuestra: validaciones de calidad antes de cargar, MERGE (upsert
              idempotente), TRY_CAST, transacción y bitácora.

   Uso:
       EXEC dw.usp_transformar;
   ========================================================================= */
USE LatamLabor;
GO

CREATE OR ALTER PROCEDURE dw.usp_transformar
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio       DATETIME2(0) = SYSDATETIME(),
            @errores      NVARCHAR(2000) = N'',
            @n            INT,
            @filas_pais   INT,
            @filas_hechos INT;

    BEGIN TRY
        /* ---------------- 1. Validaciones de calidad ---------------------- */

        -- Valores que no son número (ignorando vacíos, que son "sin dato")
        SELECT @n = COUNT(*)
        FROM raw.participacion
        WHERE NULLIF(LTRIM(RTRIM(REPLACE([value], CHAR(13), N''))), N'') IS NOT NULL
          AND TRY_CAST(REPLACE([value], CHAR(13), N'') AS FLOAT) IS NULL;
        IF @n > 0 SET @errores += CONCAT(N'- ', @n, N' valores no numéricos. ');

        -- Valores fuera del rango 0-100 (son porcentajes)
        SELECT @n = COUNT(*)
        FROM raw.participacion
        WHERE TRY_CAST(REPLACE([value], CHAR(13), N'') AS FLOAT) NOT BETWEEN 0 AND 100;
        IF @n > 0 SET @errores += CONCAT(N'- ', @n, N' valores fuera de 0-100. ');

        -- Duplicados por país + año + indicador
        SELECT @n = COUNT(*)
        FROM (
            SELECT country_iso3, [year], indicator_label
            FROM raw.participacion
            GROUP BY country_iso3, [year], indicator_label
            HAVING COUNT(*) > 1
        ) AS d;
        IF @n > 0 SET @errores += CONCAT(N'- ', @n, N' combinaciones país+año+indicador duplicadas. ');

        -- Países en la serie que no tienen metadatos
        SELECT @n = COUNT(DISTINCT p.country_iso3)
        FROM raw.participacion AS p
        LEFT JOIN raw.paises AS m ON m.country_iso3 = p.country_iso3
        WHERE m.country_iso3 IS NULL;
        IF @n > 0 SET @errores += CONCAT(N'- ', @n, N' países sin metadatos. ');

        IF LEN(@errores) > 0
        BEGIN
            SET @errores = N'Validación fallida: ' + @errores;
            THROW 50002, @errores, 1;
        END;

        /* ---------------- 2. Carga a dw ---------------------------------- */
        BEGIN TRANSACTION;

        -- Dimensión de países
        MERGE dw.dim_pais AS t
        USING (
            SELECT LTRIM(RTRIM(country_iso3))       AS country_iso3,
                   LTRIM(RTRIM(country_name))       AS country_name,
                   NULLIF(LTRIM(RTRIM(region_name)), N'')        AS region_name,
                   NULLIF(LTRIM(RTRIM(income_level_name)), N'')  AS income_level_name,
                   NULLIF(LTRIM(RTRIM(capital_city)), N'')       AS capital_city
            FROM raw.paises
        ) AS s
            ON t.country_iso3 = s.country_iso3
        WHEN MATCHED AND (
                 t.country_name <> s.country_name
              OR ISNULL(t.region_name, N'')       <> ISNULL(s.region_name, N'')
              OR ISNULL(t.income_level_name, N'') <> ISNULL(s.income_level_name, N'')
              OR ISNULL(t.capital_city, N'')      <> ISNULL(s.capital_city, N''))
            THEN UPDATE SET country_name        = s.country_name,
                            region_name         = s.region_name,
                            income_level_name   = s.income_level_name,
                            capital_city        = s.capital_city,
                            fecha_actualizacion = SYSDATETIME()
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (country_iso3, country_name, region_name, income_level_name, capital_city)
                 VALUES (s.country_iso3, s.country_name, s.region_name, s.income_level_name, s.capital_city);

        SET @filas_pais = @@ROWCOUNT;

        -- Hechos: solo filas con valor (los vacíos son "sin dato")
        MERGE dw.fct_participacion AS t
        USING (
            SELECT LTRIM(RTRIM(country_iso3))                                AS country_iso3,
                   TRY_CAST([year] AS SMALLINT)                              AS anio,
                   LTRIM(RTRIM(indicator_label))                             AS indicador,
                   TRY_CAST(NULLIF(LTRIM(RTRIM(REPLACE([value], CHAR(13), N''))), N'')
                            AS DECIMAL(9, 4))                                AS valor
            FROM raw.participacion
        ) AS s
            ON  t.country_iso3 = s.country_iso3
            AND t.anio         = s.anio
            AND t.indicador    = s.indicador
        WHEN MATCHED AND s.valor IS NOT NULL AND t.valor <> s.valor
            THEN UPDATE SET valor = s.valor
        WHEN NOT MATCHED BY TARGET AND s.valor IS NOT NULL AND s.anio IS NOT NULL
            THEN INSERT (country_iso3, anio, indicador, valor)
                 VALUES (s.country_iso3, s.anio, s.indicador, s.valor);

        SET @filas_hechos = @@ROWCOUNT;

        COMMIT TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_transformar', @inicio, SYSDATETIME(), @filas_pais + @filas_hechos, N'OK',
                CONCAT(N'dim_pais: ', @filas_pais, N' filas nuevas o cambiadas; ',
                       N'fct_participacion: ', @filas_hechos, N' filas nuevas o cambiadas'));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_transformar', @inicio, SYSDATETIME(), NULL, N'ERROR', ERROR_MESSAGE());

        THROW;
    END CATCH
END;
GO
