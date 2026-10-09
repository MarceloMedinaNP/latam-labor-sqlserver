#!/usr/bin/env bash
# Descarga los datos, crea la base, las tablas y los stored procedures.
# Uso (desde la raíz del proyecto):  bash scripts/montar_todo.sh
set -e

echo ">> 1/2 Descargando datos del Banco Mundial..."
python fetch_worldbank.py

echo ">> 2/2 Creando base, tablas y procedimientos..."
python scripts/run_sql.py \
  sql/00_crear_base.sql \
  sql/01_tablas.sql \
  sql/02_sp_carga.sql \
  sql/03_sp_transformacion.sql \
  sql/04_sp_reportes.sql \
  sql/05_sp_pipeline.sql

echo
echo "Todo listo. Ahora ejecuta las pruebas:"
echo "  python scripts/run_sql.py --seguir sql/99_pruebas.sql"
