# LATAM Labor Analytics — SQL Server

Pipeline de datos en **SQL Server** con **stored procedures**: carga, validación, transformación y reportes sobre la participación laboral en 20 países de América Latina (Banco Mundial, estimaciones modeladas de la OIT, 1990–2025).

Es la versión en SQL Server de [latam-labor-analytics](https://github.com/MarceloMedinaNP/latam-labor-analytics), que hace el mismo recorrido con BigQuery y dbt. Los datos de entrada son los mismos dos CSV.

## Qué hace

```
CSV (fetch_worldbank.py)
   │  dw.usp_cargar_csv        BULK INSERT en transacción, con bitácora
   ▼
raw.participacion / raw.paises        (texto, copia fiel del archivo)
   │  dw.usp_transformar       validaciones de calidad + MERGE
   ▼
dw.dim_pais / dw.fct_participacion    (tipado, con claves y restricciones)
   │  rpt.usp_refrescar_brecha  pivote + ranking anual
   ▼
rpt.brecha_genero                     (tabla resumen para reportes)

rpt.usp_indicadores_pais    reporte parametrizado por país, años e indicador
dw.usp_pipeline             ejecuta todo en orden y se detiene si algo falla
dw.log_carga                bitácora de cada ejecución (OK / ERROR)
```

| Procedimiento | Qué demuestra |
|---|---|
| `dw.usp_cargar_csv` | SQL dinámico seguro, `BULK INSERT`, transacción, `TRY/CATCH` con `ROLLBACK` |
| `dw.usp_transformar` | Validaciones de calidad antes de cargar, `MERGE` idempotente, `TRY_CAST` |
| `rpt.usp_indicadores_pais` | Parámetros con valores por defecto, validación con `THROW`, `LAG`, `RANK`, `COUNT OVER` |
| `rpt.usp_refrescar_brecha` | Pivote con agregación condicional, refresco transaccional |
| `dw.usp_pipeline` | Orquestación de procedimientos y manejo de errores en cadena |
| `06_indices.sql` | Índice no agrupado con `INCLUDE`, medición con `STATISTICS IO` y plan de ejecución |

## Cómo ejecutarlo, sin instalar nada

El proyecto corre en **GitHub Codespaces**: una computadora en la nube que se abre en el navegador, con SQL Server 2022 ya configurado (carpeta `.devcontainer/`). No hace falta instalar nada en tu equipo. El plan gratuito de GitHub incluye horas mensuales de Codespaces de sobra para este proyecto.

### Paso 1 — Subir el proyecto a GitHub (10 min)

1. En GitHub, crea un repositorio nuevo llamado **exactamente** `latam-labor-sqlserver` (público, sin README). Los scripts usan ese nombre en la ruta de los datos.
2. En la página del repositorio vacío, usa **uploading an existing file** y arrastra **el contenido** de la carpeta descomprimida (no la carpeta en sí): `.devcontainer`, `scripts`, `sql`, `README.md`, `fetch_worldbank.py`, `requirements.txt` y `.gitignore`.
   - Si Windows oculta `.devcontainer` o `.gitignore`, en el Explorador activa **Vista → Mostrar → Elementos ocultos**.
3. Escribe un mensaje como "Pipeline SQL Server con stored procedures" y presiona **Commit changes**.

### Paso 2 — Abrir el Codespace (5–10 min la primera vez)

1. En el repositorio: botón verde **Code → pestaña Codespaces → Create codespace on main**.
2. Se abre VS Code en el navegador. La primera vez tarda unos minutos mientras descarga SQL Server e instala las dependencias de Python. Espera a que la terminal de abajo termine.

### Paso 3 — Montar todo (5 min)

En la terminal del Codespace:

```
bash scripts/montar_todo.sh
```

Descarga los datos del Banco Mundial, crea la base `LatamLabor`, las tablas y los 5 stored procedures. Si SQL Server todavía está arrancando, el script espera solo.

### Paso 4 — Ejecutar las pruebas (10 min)

```
python scripts/run_sql.py --seguir sql/99_pruebas.sql
```

| Bloque | Qué deberías ver |
|---|---|
| 1. Pipeline | Una tabla con 4 filas en estado `OK` |
| 2. Conteos | `dim_pais` = 20; `fct_participacion` cerca de 2.100 |
| 3. Reporte | La serie de Bolivia con variación anual y ranking |
| 4. Parámetros | Dos `ERROR` con mensajes claros: **es lo esperado** |
| 5. Idempotencia | Los mismos conteos; `usp_transformar` dice 0 filas nuevas |
| 6. Error de carpeta | Un `ERROR`, y la bitácora lo registra |
| 8. Hallazgo | Bolivia en el primer lugar de participación femenina |

### Paso 5 — Explorar con la extensión de SQL Server (15 min)

El Codespace trae la extensión **SQL Server (mssql)**, que funciona como un SSMS dentro del navegador:

1. Abre la extensión desde el ícono de base de datos de la barra izquierda y agrega una conexión:
   - Server: `localhost` · Authentication: **SQL Login** · User: `sa` · Password: `Practica_SQL_2026!`
   - Si pregunta por el certificado, acepta **Trust server certificate**.
2. Abre `sql/06_indices.sql`, conéctalo a esa conexión y ejecútalo. En la pestaña de mensajes compara las *logical reads* antes y después del índice. Con este volumen la mejora es pequeña: lo que importa es practicar el método de medir, indexar y volver a medir.
3. Prueba tus propias consultas, por ejemplo `EXEC rpt.usp_indicadores_pais @pais = 'ARG';`.

### Paso 6 — Detener el Codespace

Cuando termines, en **github.com/codespaces** detén el Codespace (**Stop**) para no gastar horas del plan gratuito. Puedes volver a abrirlo cuando quieras y todo sigue ahí.

### Paso 7 — Dejarlo presentable

En la página del repositorio agrega una descripción y los temas `sql-server`, `t-sql`, `stored-procedures`, `data-engineering`, y fíjalo en tu perfil junto a los otros repositorios de datos.

> **¿Con SQL Server instalado en Windows?** También funciona: copia los CSV a `C:\datos\latam\raw\`, ejecuta los scripts de `sql/` en orden con SSMS y usa esa ruta en los `EXEC`.

---

## Si algo falla

| Síntoma | Causa probable | Solución |
|---|---|---|
| `No se pudo conectar a SQL Server` | El contenedor de la base no arrancó | En la terminal: `docker ps`. Si no aparece `mssql`, reconstruye el Codespace: **Ctrl+Shift+P → Codespaces: Rebuild Container** |
| `Cannot bulk load ... Operating system error code 3` | La ruta no existe | Revisa que el repositorio se llame exactamente `latam-labor-sqlserver` y que exista `data/raw/` |
| `fetch_worldbank.py` falla | La API del Banco Mundial no respondió | Espera un minuto y vuelve a correr `bash scripts/montar_todo.sh` |
| No aparece `.devcontainer` al subir archivos | Windows oculta carpetas que empiezan con punto | Activa **Mostrar elementos ocultos** en el Explorador |
| `Validación fallida: ...` | Los datos tienen algún problema | Es la validación funcionando; el mensaje dice qué revisar |

---

## Para el CV y las entrevistas

**Línea para el CV, en la sección de proyectos:**

> **LATAM Labor Analytics — SQL Server** (proyecto personal, 2026): pipeline en T-SQL con 5 stored procedures para carga (`BULK INSERT`), validación de calidad, transformación con `MERGE`, reportes parametrizados y bitácora de ejecución, con manejo de errores y transacciones. github.com/MarceloMedinaNP/latam-labor-sqlserver

**En competencias:** `Stored procedures en SQL Server*` (*nivel inicial, aplicado en proyecto personal).

**Si te preguntan en una entrevista, la respuesta corta:**

> "En mi trabajo uso SQL principalmente para consultas y análisis. Para fortalecer la parte de SQL Server armé un proyecto con stored procedures: uno carga los archivos con BULK INSERT dentro de una transacción, otro valida la calidad y hace un MERGE para que se pueda correr varias veces sin duplicar, y otros alimentan reportes con parámetros. Todos registran cada ejecución en una bitácora y hacen rollback si algo falla. Está en mi GitHub."

Preguntas probables y el archivo donde está la respuesta:

| Pregunta | Dónde mirar |
|---|---|
| ¿Cómo manejas errores en un stored procedure? | `TRY/CATCH`, `ROLLBACK` y `THROW` en `02` y `03` |
| ¿Qué es un MERGE y para qué sirve? | `03`: inserta lo nuevo y actualiza lo que cambió, sin duplicar |
| ¿Cómo evitas inyección SQL con SQL dinámico? | `02`: la ruta se escapa duplicando comillas simples |
| ¿Cómo optimizarías una consulta lenta? | `06`: medir con `STATISTICS IO` y el plan, indexar, volver a medir |
| ¿Qué diferencia hay entre una vista y un stored procedure? | Una vista es una consulta guardada sin parámetros ni lógica; un stored procedure acepta parámetros, valida, usa transacciones y puede modificar datos |

## Fuente de datos

World Bank Open Data — Labor force participation rate (% of population ages 15+), estimaciones modeladas de la OIT: `SL.TLF.CACT.FE.ZS`, `SL.TLF.CACT.MA.ZS`, `SL.TLF.CACT.ZS`.
