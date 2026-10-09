"""
Ejecuta uno o más scripts .sql contra el SQL Server del Codespace.

Divide cada archivo en lotes por las líneas "GO" (igual que SSMS),
muestra los resultados de los SELECT y los errores de cada lote.

Uso:
    python scripts/run_sql.py sql/00_crear_base.sql sql/01_tablas.sql
    python scripts/run_sql.py --seguir sql/99_pruebas.sql   # no se detiene ante errores
"""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path

import pymssql

SERVIDOR = "localhost"
USUARIO = "sa"
CLAVE = "Practica_SQL_2026!"   # la misma de .devcontainer/docker-compose.yml


def conectar() -> pymssql.Connection:
    """Conecta con reintentos: SQL Server tarda unos segundos en arrancar."""
    for intento in range(1, 31):
        try:
            return pymssql.connect(server=SERVIDOR, user=USUARIO, password=CLAVE,
                                   database="master", autocommit=True)
        except pymssql.Error:
            if intento == 1:
                print("Esperando a que SQL Server termine de arrancar...")
            time.sleep(3)
    sys.exit("No se pudo conectar a SQL Server. Revisa que el contenedor 'db' esté corriendo.")


def lotes(texto: str) -> list[str]:
    """Separa el script por líneas que contienen solo GO."""
    partes = re.split(r"^\s*GO\s*$", texto, flags=re.IGNORECASE | re.MULTILINE)
    return [p.strip() for p in partes if p.strip()]


def mostrar(cursor: pymssql.Cursor) -> None:
    """Imprime todos los conjuntos de resultados que devolvió el lote."""
    while True:
        if cursor.description:
            columnas = [c[0] for c in cursor.description]
            filas = cursor.fetchall()
            anchos = [max(len(str(c)), *(len(str(f[i])) for f in filas)) if filas else len(str(c))
                      for i, c in enumerate(columnas)]
            print("  " + " | ".join(str(c).ljust(a) for c, a in zip(columnas, anchos)))
            print("  " + "-+-".join("-" * a for a in anchos))
            for f in filas:
                print("  " + " | ".join(str(v).ljust(a) for v, a in zip(f, anchos)))
            print(f"  ({len(filas)} filas)\n")
        if not cursor.nextset():
            break


def main() -> None:
    args = sys.argv[1:]
    seguir = "--seguir" in args
    archivos = [a for a in args if a != "--seguir"]
    if not archivos:
        sys.exit(__doc__)

    conexion = conectar()
    cursor = conexion.cursor()
    hubo_error = False

    for archivo in archivos:
        print(f"\n=== {archivo} ===")
        for n, lote in enumerate(lotes(Path(archivo).read_text(encoding="utf-8")), start=1):
            try:
                cursor.execute(lote)
                mostrar(cursor)
            except pymssql.Error as e:
                hubo_error = True
                print(f"  ERROR en el lote {n}: {e}\n")
                if not seguir:
                    sys.exit(1)

    print("Listo." if not hubo_error else "Terminado, con errores (revisa arriba).")


if __name__ == "__main__":
    main()
