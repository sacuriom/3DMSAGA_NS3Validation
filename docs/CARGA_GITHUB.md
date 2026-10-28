# Carga del estudio ns-3 en GitHub

Destino: https://github.com/sacuriom/3DMSAGA_NS3Validation

## Qué subir

Descomprimir `3DMSAGA_NS3Validation_codigo_datos.zip` y subir su contenido a la raíz del repositorio. Deben quedar directamente `README.md`, `scripts/`, `experiments/`, `data/`, `docs/`, `provenance/`, `verification/` y `.github/`. No subir el ZIP de fuentes como único archivo: eso impide consultar el código y ejecutar la auditoría automática. Conservar los archivos ocultos `.gitattributes`, `.gitignore` y `.github/workflows/audit.yml`.

El programa principal es C++: `experiments/ns3_archive/validacion_lorawan_v02.cc`. Las entradas y resultados de las 128 corridas se conservan junto con su procedencia. Las instrucciones originales y portables están en `docs/ENTORNO_LINUX_Y_EJECUCION.md`.

## Opción recomendada: Git desde la carpeta preparada

Estos comandos son instrucciones para la publicación; no se ejecutaron durante la preparación. Requieren Git y autenticación del autor. Ejecutar en la carpeta `3DMSAGA_NS3Validation`, que contiene el README, y comprobar primero que no pertenece ya a otro repositorio.

```powershell
git init -b main
git add .
git status --short
git commit -m "Add reproducible ns-3 validation study"
git remote add origin https://github.com/sacuriom/3DMSAGA_NS3Validation.git
git push -u origin main
```

Si el repositorio remoto ya tiene contenido, clonarlo primero y copiar allí los archivos revisados; no forzar un push ni borrar su historial. Si la carpeta ya tiene `.git`, revisar su remoto y rama antes de usar las instrucciones. `.gitattributes` conserva los bytes archivados para que las huellas SHA-256 sean estables al clonar en Linux.

## Trazas como activos separados

Después de subir las fuentes y comprobar la auditoría en Actions, crear una Release vinculada al commit publicado. Adjuntar los dos archivos de la carpeta hermana `release_assets/`:

- `ns3_packets_128corridas.zip`: 128 CSV de paquetes.
- `ns3_events_128corridas.zip`: doce CSV de eventos disponibles.

No añadir estos ZIP al historial Git. Sus tamaños y SHA-256 figuran en el manifiesto de entrega. La descripción puede tomarse de `DESCRIPCION_RELEASE.md`; actualizar las URL verificables una vez creadas. La entrega no atribuye trazas de eventos inexistentes a las 128 corridas.

## Verificación después de publicar

Clonar el repositorio en otra carpeta y ejecutar `python scripts/verify_release.py`. Debe informar PASS y 128 corridas. Revisar también la ejecución de Actions; su presencia en esta entrega no significa que ya haya pasado en GitHub.

Registrar el SHA del commit mediante `git rev-parse HEAD` e incorporarlo a las referencias de la tesis. El identificador de la entrega no es un DOI. `CITATION.cff` identifica una versión de preparación, que debe actualizarse si se publica una versión formal.

## Derechos y alcance

Se conserva `LICENSE_PENDING.md`: no se ha asignado una licencia nueva al código propio. Las dependencias y datos conservan sus condiciones y atribuciones; ver `docs/THIRD_PARTY.md`. Puede prepararse la carga sin atribuir permisos de reutilización no decididos por el autor.

La comprobación reproduce métricas archivadas, no 128 simulaciones nuevas ni mediciones de campo. La evidencia de FT101/TTS pertenece al repositorio separado 3DMSAGA-2GATEWAYS.
