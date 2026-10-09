/* =========================================================================
   04 - Procedimientos de reporte
   -------------------------------------------------------------------------
   rpt.usp_indicadores_pais : consulta parametrizada para un reporte
   rpt.usp_refrescar_brecha : reconstruye la tabla resumen rpt.brecha_genero
   Demuestra: parámetros con valores por defecto y validación,
              funciones de ventana (LAG, RANK, COUNT OVER), pivote con
              agregación condicional y refresco transaccional.
   ========================================================================= */
USE LatamLabor;
GO

/* -------------------------------------------------------------------------
   rpt.usp_indicadores_pais
   Serie de un país con su variación anual y su posición en la región.

   Uso:
       EXEC rpt.usp_indicadores_pais @pais = 'BOL';
       EXEC rpt.usp_indicadores_pais @pais = 'PER', @desde = 2010, @hasta = 2025,
                                     @indicador = 'masculina';
   ------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rpt.usp_indicadores_pais
    @pais       CHAR(3),
    @desde      SMALLINT    = 1990,
    @hasta      SMALLINT    = 2025,
    @indicador  VARCHAR(20) = 'femenina'
AS
BEGIN
    SET NOCOUNT ON;

    -- Validación de parámetros: mensajes claros para quien usa el reporte
    IF NOT EXISTS (SELECT 1 FROM dw.dim_pais WHERE country_iso3 = @pais)
        THROW 50010, N'El país indicado no existe en dw.dim_pais. Usa el código ISO3, por ejemplo BOL.', 1;

    IF @desde > @hasta
        THROW 50011, N'El año inicial no puede ser mayor que el año final.', 1;

    IF @indicador NOT IN ('femenina', 'masculina', 'total')
        THROW 50012, N'Indicador no válido. Usa femenina, masculina o total.', 1;

    WITH base AS (
        SELECT
            f.country_iso3,
            f.anio,
            f.valor,
            -- Se calcula sobre todos los años y países, antes de filtrar,
            -- para que el primer año del rango también tenga variación y ranking
            LAG(f.valor)  OVER (PARTITION BY f.country_iso3 ORDER BY f.anio) AS valor_anterior,
            RANK()        OVER (PARTITION BY f.anio ORDER BY f.valor DESC)    AS ranking_regional,
            COUNT(*)      OVER (PARTITION BY f.anio)                          AS paises_con_dato
        FROM dw.fct_participacion AS f
        WHERE f.indicador = @indicador
    )
    SELECT
        d.country_name                                      AS pais,
        b.anio,
        b.valor                                             AS participacion_pct,
        CAST(b.valor - b.valor_anterior AS DECIMAL(9, 4))   AS variacion_pp,
        b.ranking_regional,
        b.paises_con_dato
    FROM base AS b
    JOIN dw.dim_pais AS d ON d.country_iso3 = b.country_iso3
    WHERE b.country_iso3 = @pais
      AND b.anio BETWEEN @desde AND @hasta
    ORDER BY b.anio;
END;
GO

/* -------------------------------------------------------------------------
   rpt.usp_refrescar_brecha
   Reconstruye la tabla resumen de brecha de género (masculina - femenina)
   con el ranking anual de participación femenina.

   Uso:
       EXEC rpt.usp_refrescar_brecha;
   ------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE rpt.usp_refrescar_brecha
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio DATETIME2(0) = SYSDATETIME(),
            @filas  INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM rpt.brecha_genero;

        WITH pivotado AS (
            SELECT
                f.country_iso3,
                f.anio,
                MAX(CASE WHEN f.indicador = 'femenina'  THEN f.valor END) AS fem,
                MAX(CASE WHEN f.indicador = 'masculina' THEN f.valor END) AS masc
            FROM dw.fct_participacion AS f
            GROUP BY f.country_iso3, f.anio
        )
        INSERT INTO rpt.brecha_genero (
            country_iso3, country_name, anio,
            participacion_femenina, participacion_masculina, brecha_pp,
            ranking_femenino, fecha_refresco)
        SELECT
            p.country_iso3,
            d.country_name,
            p.anio,
            p.fem,
            p.masc,
            p.masc - p.fem,
            RANK() OVER (PARTITION BY p.anio ORDER BY p.fem DESC),
            SYSDATETIME()
        FROM pivotado AS p
        JOIN dw.dim_pais AS d ON d.country_iso3 = p.country_iso3
        WHERE p.fem IS NOT NULL
          AND p.masc IS NOT NULL;

        SET @filas = @@ROWCOUNT;

        COMMIT TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_refrescar_brecha', @inicio, SYSDATETIME(), @filas, N'OK', NULL);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        INSERT INTO dw.log_carga (proceso, inicio, fin, filas, estado, mensaje)
        VALUES (N'usp_refrescar_brecha', @inicio, SYSDATETIME(), NULL, N'ERROR', ERROR_MESSAGE());

        THROW;
    END CATCH
END;
GO
