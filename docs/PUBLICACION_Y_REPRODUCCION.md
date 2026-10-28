# Publicación y niveles de reproducción

Esta entrega es local. No hay todavía commit remoto, etiqueta, DOI ni licencia elegida para el código propio. CITATION.cff identifica la preparación y deberá actualizarse al publicar una versión real. Las dependencias conservan sus licencias.

## Archivos de gran volumen

Los dos ZIP de paquetes/eventos están preparados aparte, con manifiestos internos y SHA-256 por CSV. Su contenido se leyó de OCTUBRE.zip y se comparó contra las huellas de los manifiestos de ejecución. El ZIP de eventos contiene 12 CSV, no 128: no se inventan registros que la campaña no exportó. El manifiesto externo registra también el SHA-256 del ZIP completo.

Publicarlos como archivos de una Release conserva un repositorio manejable. Ambos superan 100 MiB y están por debajo de 2 GiB. GitHub bloquea archivos Git de más de 100 MiB y permite archivos de Release inferiores a 2 GiB. Fuentes oficiales consultadas el 27-10-2026: https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github y https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases . No existe aún una URL de descarga remota verificada.

## Qué se comprobó

1. Recálculo de tablas: `python scripts/verify_release.py`, sin instalar bibliotecas adicionales. Identifica 128 corridas, integridad, denominadores, métricas por nodo y medias/IC95 de 120 réplicas principales.
2. Reejecución: `scripts/replay_ns3.py` prepara un plan por defecto; `--execute` requiere un entorno ns-3 y módulo LoRaWAN con los commits archivados. En esta revisión no se realizaron 128 simulaciones nuevas. Los programas Python históricos pueden contener rutas del entorno original; el lanzador nuevo proporciona una ruta portable explícita.
3. Nueva campaña: volver a conducir es una adquisición independiente y requiere sus propios archivos, metadatos y denominador. La simulación no sustituye ese contraste.

La reconstrucción completa de la optimización MATLAB original requiere recuperar el generador exacto citado como MDPI_Suite_MesoCellular_6.m. Las dos variantes conservadas no se declaran equivalentes. Sí se conservan las matrices y el adaptador C++ exactos usados por la campaña ns-3.
