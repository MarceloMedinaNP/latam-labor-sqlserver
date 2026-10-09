"""
Ingesta de participación laboral desde la API del Banco Mundial.

Fuente: World Bank Open Data (estimaciones modeladas de la OIT).
API pública, sin autenticación.

Genera dos archivos en data/raw/:
  - participacion.csv : serie larga país x año x indicador
  - paises.csv        : metadatos de país para la dimensión

Uso:
    python fetch_worldbank.py
"""

from __future__ import annotations

import time
from pathlib import Path

import pandas as pd
import requests

# --------------------------------------------------------------------------
# Configuración
# --------------------------------------------------------------------------

BASE_URL = "https://api.worldbank.org/v2"

# 20 países de América Latina (ISO3)
PAISES = [
    "ARG", "BOL", "BRA", "CHL", "COL", "CRI", "CUB", "DOM", "ECU", "SLV",
    "GTM", "HTI", "HND", "MEX", "NIC", "PAN", "PRY", "PER", "URY", "VEN",
]

# Tasa de participación en la fuerza laboral, % de población de 15+ años
INDICADORES = {
    "SL.TLF.CACT.FE.ZS": "femenina",
    "SL.TLF.CACT.MA.ZS": "masculina",
    "SL.TLF.CACT.ZS": "total",
}

ANIO_INICIO = 1990
ANIO_FIN = 2025

PER_PAGE = 20000          # una sola página para este volumen
REINTENTOS = 3
ESPERA_REINTENTO = 3      # segundos

SALIDA = Path("data/raw")


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

def pedir(url: str, params: dict) -> list:
    """GET con reintentos. Devuelve el cuerpo JSON ya parseado."""
    for intento in range(1, REINTENTOS + 1):
        try:
            r = requests.get(url, params=params, timeout=60)
            r.raise_for_status()
            cuerpo = r.json()
        except (requests.RequestException, ValueError) as e:
            if intento == REINTENTOS:
                raise RuntimeError(f"Falló la petición a {url}: {e}") from e
            print(f"  reintento {intento}/{REINTENTOS} tras error: {e}")
            time.sleep(ESPERA_REINTENTO)
            continue

        # La API responde [metadata, datos]. Si algo salió mal, devuelve
        # un solo elemento con el mensaje de error.
        if not isinstance(cuerpo, list) or len(cuerpo) < 2:
            raise RuntimeError(f"Respuesta inesperada de la API: {cuerpo}")

        meta, datos = cuerpo[0], cuerpo[1]
        if datos is None:
            raise RuntimeError(f"La API no devolvió datos. Metadata: {meta}")

        # Aviso si quedaron páginas sin traer
        if meta.get("pages", 1) > 1:
            print(f"  ATENCIÓN: la respuesta tiene {meta['pages']} páginas; "
                  f"sube PER_PAGE para traerlas todas.")

        return datos

    raise RuntimeError("Reintentos agotados")


# --------------------------------------------------------------------------
# Extracción
# --------------------------------------------------------------------------

def traer_indicador(indicador: str, etiqueta: str) -> pd.DataFrame:
    """Serie de un indicador para todos los países del listado."""
    print(f"Descargando {indicador} ({etiqueta})...")

    url = f"{BASE_URL}/country/{';'.join(PAISES)}/indicator/{indicador}"
    datos = pedir(url, {
        "date": f"{ANIO_INICIO}:{ANIO_FIN}",
        "format": "json",
        "per_page": PER_PAGE,
    })

    filas = [
        {
            "country_iso3": d.get("countryiso3code") or d["country"]["id"],
            "country_name": d["country"]["value"],
            "indicator_id": d["indicator"]["id"],
            "indicator_label": etiqueta,
            "year": int(d["date"]),
            "value": d["value"],          # None cuando no hay dato
        }
        for d in datos
    ]

    df = pd.DataFrame(filas)
    print(f"  {len(df)} filas, {df['value'].notna().sum()} con valor")
    return df


def traer_paises() -> pd.DataFrame:
    """Metadatos de país: región, grupo de ingreso, capital, coordenadas."""
    print("Descargando metadatos de país...")

    url = f"{BASE_URL}/country/{';'.join(PAISES)}"
    datos = pedir(url, {"format": "json", "per_page": PER_PAGE})

    filas = [
        {
            "country_iso3": d["id"],
            "country_name": d["name"],
            "region_id": d["region"]["id"],
            "region_name": d["region"]["value"],
            "income_level_id": d["incomeLevel"]["id"],
            "income_level_name": d["incomeLevel"]["value"],
            "capital_city": d.get("capitalCity"),
            "longitude": d.get("longitude") or None,
            "latitude": d.get("latitude") or None,
        }
        for d in datos
    ]

    df = pd.DataFrame(filas)
    print(f"  {len(df)} países")
    return df


# --------------------------------------------------------------------------
# Validaciones mínimas antes de escribir
# --------------------------------------------------------------------------

def validar(participacion: pd.DataFrame, paises: pd.DataFrame) -> None:
    errores = []

    duplicados = participacion.duplicated(
        subset=["country_iso3", "year", "indicator_id"]
    ).sum()
    if duplicados:
        errores.append(f"{duplicados} filas duplicadas por país+año+indicador")

    fuera_rango = participacion["value"].dropna()
    fuera_rango = fuera_rango[(fuera_rango < 0) | (fuera_rango > 100)]
    if len(fuera_rango):
        errores.append(f"{len(fuera_rango)} valores fuera del rango 0-100")

    faltantes = set(PAISES) - set(paises["country_iso3"])
    if faltantes:
        errores.append(f"países sin metadatos: {sorted(faltantes)}")

    if errores:
        raise SystemExit("Validación fallida:\n  - " + "\n  - ".join(errores))

    print("Validaciones OK")


# --------------------------------------------------------------------------

def main() -> None:
    participacion = pd.concat(
        [traer_indicador(ind, etq) for ind, etq in INDICADORES.items()],
        ignore_index=True,
    ).sort_values(["country_iso3", "indicator_id", "year"])

    paises = traer_paises().sort_values("country_iso3")

    validar(participacion, paises)

    SALIDA.mkdir(parents=True, exist_ok=True)
    participacion.to_csv(SALIDA / "participacion.csv", index=False)
    paises.to_csv(SALIDA / "paises.csv", index=False)

    print(f"\nEscrito en {SALIDA.resolve()}")
    print(f"  participacion.csv : {len(participacion)} filas")
    print(f"  paises.csv        : {len(paises)} filas")

    # Vista rápida del hallazgo: ranking femenino del último año con datos
    fem = participacion[
        (participacion["indicator_label"] == "femenina")
        & participacion["value"].notna()
    ]
    if not fem.empty:
        ultimo = fem["year"].max()
        top = (fem[fem["year"] == ultimo]
               .nlargest(5, "value")[["country_name", "value"]])
        print(f"\nTop 5 participación femenina, {ultimo}:")
        for _, r in top.iterrows():
            print(f"  {r['country_name']:<25} {r['value']:.1f}%")


if __name__ == "__main__":
    main()
