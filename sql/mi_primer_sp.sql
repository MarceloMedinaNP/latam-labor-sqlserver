USE LatamLabor;
GO

CREATE OR ALTER PROCEDURE rpt.usp_pais_anio
    @pais  CHAR(3),
    @anio  SMALLINT
AS
BEGIN
    -- Devuelve los 3 indicadores de un país en un año

IF NOT EXISTS (SELECT 1 FROM dw.dim_pais WHERE country_iso3 = @pais)
    THROW 50010, N'No existe el pais.', 1;

IF @anio < 1990 OR @anio>2025
    THROW 50011, N'No tengo datos para ese año.', 1;



    SELECT indicador, valor
    FROM dw.fct_participacion
    WHERE country_iso3 = @pais 
    AND anio =  @anio;
END;

GO