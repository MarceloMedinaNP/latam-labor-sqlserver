/* =========================================================================
   01 - Tablas
   ========================================================================= */
USE LatamLabor;
GO

/* ---------- raw: todo NVARCHAR para que la carga nunca falle por tipos --- */

DROP TABLE IF EXISTS raw.participacion;
CREATE TABLE raw.participacion (
    country_iso3     NVARCHAR(10),
    country_name     NVARCHAR(150),
    indicator_id     NVARCHAR(50),
    indicator_label  NVARCHAR(20),
    [year]           NVARCHAR(10),
    [value]          NVARCHAR(50)
);

DROP TABLE IF EXISTS raw.paises;
CREATE TABLE raw.paises (
    country_iso3       NVARCHAR(10),
    country_name       NVARCHAR(150),
    region_id          NVARCHAR(20),
    region_name        NVARCHAR(150),
    income_level_id    NVARCHAR(20),
    income_level_name  NVARCHAR(150),
    capital_city       NVARCHAR(150),
    longitude          NVARCHAR(50),
    latitude           NVARCHAR(50)
);
GO

/* ---------- dw: tablas tipadas, con claves y restricciones ---------------- */

DROP TABLE IF EXISTS rpt.brecha_genero;
DROP TABLE IF EXISTS dw.fct_participacion;
DROP TABLE IF EXISTS dw.dim_pais;
DROP TABLE IF EXISTS dw.log_carga;
GO

CREATE TABLE dw.dim_pais (
    country_iso3         CHAR(3)        NOT NULL CONSTRAINT PK_dim_pais PRIMARY KEY,
    country_name         NVARCHAR(150)  NOT NULL,
    region_name          NVARCHAR(150)  NULL,
    income_level_name    NVARCHAR(150)  NULL,
    capital_city         NVARCHAR(150)  NULL,
    fecha_actualizacion  DATETIME2(0)   NOT NULL CONSTRAINT DF_dim_pais_fecha DEFAULT SYSDATETIME()
);

CREATE TABLE dw.fct_participacion (
    country_iso3  CHAR(3)       NOT NULL
        CONSTRAINT FK_fct_pais REFERENCES dw.dim_pais (country_iso3),
    anio          SMALLINT      NOT NULL,
    indicador     VARCHAR(20)   NOT NULL
        CONSTRAINT CK_fct_indicador CHECK (indicador IN ('femenina', 'masculina', 'total')),
    valor         DECIMAL(9, 4) NOT NULL
        CONSTRAINT CK_fct_valor CHECK (valor BETWEEN 0 AND 100),
    CONSTRAINT PK_fct_participacion PRIMARY KEY (country_iso3, anio, indicador)
);

CREATE TABLE dw.log_carga (
    id       INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_log_carga PRIMARY KEY,
    proceso  NVARCHAR(100)  NOT NULL,
    inicio   DATETIME2(0)   NOT NULL,
    fin      DATETIME2(0)   NULL,
    filas    INT            NULL,
    estado   NVARCHAR(20)   NOT NULL,   -- OK / ERROR
    mensaje  NVARCHAR(4000) NULL
);
GO

/* ---------- rpt: tabla resumen para reportes ----------------------------- */

CREATE TABLE rpt.brecha_genero (
    country_iso3             CHAR(3)       NOT NULL,
    country_name             NVARCHAR(150) NOT NULL,
    anio                     SMALLINT      NOT NULL,
    participacion_femenina   DECIMAL(9, 4) NOT NULL,
    participacion_masculina  DECIMAL(9, 4) NOT NULL,
    brecha_pp                DECIMAL(9, 4) NOT NULL,
    ranking_femenino         INT           NOT NULL,
    fecha_refresco           DATETIME2(0)  NOT NULL,
    CONSTRAINT PK_brecha_genero PRIMARY KEY (country_iso3, anio)
);
GO
