# 3DMSAGA_NS3Validation

Entrega local preparada para https://github.com/sacuriom/3DMSAGA_NS3Validation. Contiene codigo y evidencia de la cohorte de 2153 puntos y diez gateways usada en la tesis. No presenta la simulacion como validacion de propagacion fisica.

## Comprobar resultados sin volver a simular

Desde esta carpeta:

```sh
python scripts/verify_release.py
```

El programa identifica 128 corridas por huella del codigo y de la matriz, comprueba las metricas y recalcula medias e intervalos principales. Son 120 corridas principales (30 por combinacion de dos entradas RF y SF7/SF9) y ocho exploratorias. Usa solo la biblioteca estandar de Python.

## Codigo y configuraciones

- `experiments/ns3_archive/validacion_lorawan_v02.cc`: adaptador C++ exacto del manifiesto de compilacion.
- `experiments/ns3_archive/inputs/`: matrices y sus manifiestos; `gateways.csv`: sitios.
- `experiments/ns3_archive/produccion/`: configuracion, manifiesto y metricas por corrida, nodo, hora y gateway de las 128 ejecuciones aceptadas.
- `src/matlab_archived/`: dos variantes MATLAB recibidas; no se afirma identidad con el generador historico citado como `MDPI_Suite_MesoCellular_6.m`, no encontrado por nombre en el ZIP.
- `data/simulation/`: tablas de evidencia y matriz afirmacion-evidencia de la tesis.

Entorno original: ns-3 commit f576896f5c2387874f49be221c13ae371e4f8f86; lorawan commit 67bcaefdeb45d367010e09a80083b9a0527f766b; configuracion Ubuntu/WSL conservada en build_manifest.json. No se ejecuta una instalacion ni una descarga al auditar tablas.

## Repetir simulaciones

`python scripts/replay_ns3.py --help` describe la preparacion y la ejecucion explicita de una corrida. Por defecto solo imprime el plan. La recompilacion debe realizarse contra las revisiones indicadas; repetir una corrida no equivale a repetir la campana de campo.

Los datos de gran volumen se han preparado en dos artefactos locales: `ns3_packets_128corridas.zip` (128 CSV de paquetes) y `ns3_events_128corridas.zip` (los 12 CSV de eventos que conserva la campana). Las 128 corridas no exportaron todas un detalle de eventos. `provenance/release_assets_prepared.json` identifica tamanos y SHA-256; `provenance/large_artifacts_inventory.json` relaciona cada CSV con su huella original comprobada. Su publicacion remota esta pendiente. Se destinan a archivos de una Release, separados del historial Git. Ver `docs/PUBLICACION_Y_REPRODUCCION.md`.

## Interpretacion

El PDR cuenta mensajes unicos recibidos en el servidor, no copias de varios gateways. Las comparaciones de SF mantienen la topologia; las de propagacion cambian una entrada del simulador, no una medicion de verdad. El escenario principal usa TX27 dBm, 51 bytes, periodo3600 s, 24 horas y ocho canales; no prueba equivalencia fisica con el FT101.

Consulte CITATION.cff, LICENSE_PENDING.md y docs/THIRD_PARTY.md antes de la publicacion. No se muestra una insignia de pruebas remotas: el flujo CI esta preparado y no se afirma que ya haya corrido en GitHub.


## Entrega y referencias de tesis — 28-10-2026

Ver [entorno Linux y ejecución](docs/ENTORNO_LINUX_Y_EJECUCION.md), [inventario](docs/INVENTARIO_CODIGO_Y_DATOS.csv) y [correspondencia de repositorios](docs/REFERENCIAS_TESIS.md). El programa de simulación está escrito en C++, no C. El repositorio remoto se consultó vacío; esta carpeta constituye material preparado localmente.
