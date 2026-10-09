/* =========================================================================
   00 - Base de datos y esquemas
   -------------------------------------------------------------------------
   raw : copia fiel de los CSV, todo como texto (zona de aterrizaje)
   dw  : datos limpios y tipados (dimensión, hechos y bitácora)
   rpt : tablas y procedimientos que alimentan reportes
   ========================================================================= */

IF DB_ID(N'LatamLabor') IS NULL
    CREATE DATABASE LatamLabor;
GO

USE LatamLabor;
GO

IF SCHEMA_ID(N'raw') IS NULL EXEC (N'CREATE SCHEMA raw');
IF SCHEMA_ID(N'dw')  IS NULL EXEC (N'CREATE SCHEMA dw');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt');
GO
