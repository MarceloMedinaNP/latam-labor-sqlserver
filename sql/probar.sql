USE LatamLabor
GO

EXEC rpt.usp_pais_anio @pais = Bolivia, @anio = 2025;
GO
EXEC rpt.usp_pais_anio @pais = 'PER', @anio = 2000;
GO
EXEC rpt.usp_pais_anio @pais = 'BOL', @anio = 1985;
GO
EXEC rpt.usp_pais_anio @pais = 'XXX', @anio = 2025;
GO