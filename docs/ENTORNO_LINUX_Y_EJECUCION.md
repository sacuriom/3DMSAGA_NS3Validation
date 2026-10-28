# Entorno Linux y ejecución identificada

## Evidencia archivada

La plataforma registrada en `experiments/ns3_archive/build_manifest.json` es Linux sobre WSL2, con compilador g++ 13.3.0 de Ubuntu 24.04 y Python 3.12.3. La ruta histórica es `/home/pucesa/ns-3`; el programa se copió a `scratch/validacion_lorawan_v02.cc`. No hay evidencia suficiente en estos archivos para identificar una máquina remota, IP, acceso SSH o servidor institucional. Estas rutas son referencias del entorno original, no requisitos de instalación en otra máquina.

- ns-3: `f576896f5c2387874f49be221c13ae371e4f8f86` (descripción archivada `ns-3.48-96-gf576896f5`).
- LoRaWAN: `67bcaefdeb45d367010e09a80083b9a0527f766b` (descripción archivada `v0.3.7-1-g67bcaef`).
- Código C++: `experiments/ns3_archive/validacion_lorawan_v02.cc`; su SHA-256 debe coincidir con el manifiesto de compilación y las 128 corridas.
- Fuente oficial del simulador: https://gitlab.com/nsnam/ns-3-dev ; módulo: https://github.com/signetlabdei/lorawan . Fijar las revisiones anteriores; no usar por defecto la versión más reciente para declarar reproducción histórica.

## Auditoría de datos sin Linux ni nueva simulación

Desde la raíz de esta entrega:

```sh
python3 scripts/verify_release.py
```

Recalcula 128 corridas, 120 principales y ocho exploratorias. No vuelve a simular ni descarga dependencias.

## Plan y reejecución en una instalación Linux existente

Con ns-3 y el módulo LoRaWAN preparados en las revisiones archivadas, indicar la ubicación real:

```sh
python3 scripts/verify_linux_environment.py --ns3-root /home/pucesa/ns-3
python3 scripts/replay_ns3.py --ns3-root /home/pucesa/ns-3 --run-index 0
```

El primer comando comprueba versiones y árbol de trabajo sin instalar software. El segundo imprime un plan: no ejecuta la simulación. Revisarlo antes de solicitar:

```sh
python3 scripts/replay_ns3.py --ns3-root /home/pucesa/ns-3 --run-index 0 --execute
```

El lanzador comprueba revisiones y fuente, conserva entradas archivadas y escribe en una carpeta nueva de `outputs`. No sobrescribe una fuente diferente. Si el perfil de compilación produce otro nombre de binario, utilizar `--binary` con su ruta real. No es un instalador completo. La repetición de las 128 corridas requiere ejecutar cada índice 0--127 y conservar sus manifiestos; esta revisión no la ha realizado.

El manifiesto identifica la revisión Git; para atribuir equivalencia del entorno también deben revisarse los cambios locales. El inspector registra `git status --porcelain` del árbol principal y del módulo; no aplica parches ni modifica ninguno.

## Entradas, métricas y trazas

El escenario principal utiliza 2153 dispositivos, diez gateways, SF7/SF9, 27 dBm simulados, 51 bytes, periodo 3600 s, 86400 s de generación y observación adicional. El detalle exacto se conserva por corrida. La propagación reproduce una matriz externa; no realiza un ray tracing nuevo en cada transmisión.

`generated` cuenta mensajes generados y `server_unique` mensajes únicos observados en el servidor simulado; `100*server_unique/generated` es el PDR principal. Las copias recibidas en distintos gateways se mantienen como eventos y se deduplican para la entrega única. Las medias e intervalos principales se calculan entre treinta réplicas completas por condición, no entre paquetes individuales.

Los dos ZIP de `release_assets` se entregan fuera del historial de fuentes: 128 CSV de paquetes y doce CSV de eventos, con huellas verificadas. No existen trazas de eventos completas para las 128 corridas. Todavía no hay URL de Release verificada.
