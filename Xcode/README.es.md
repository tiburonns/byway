# byway

**[English](README.md) · Español**

`byway` convierte valores de Apple Shortcuts en variables globales y persistentes que pueden reutilizarse entre atajos, automatizaciones personales, dispositivos y ejecuciones futuras.

La aplicación es SwiftUI nativa para iPhone, iPad y Mac. No tiene dependencias externas, sistema de cuentas, analítica ni servidor propio. Las variables se guardan localmente y se trasladan al contenedor privado de iCloud Drive cuando iCloud está disponible.

## Tipos de variable

- Texto
- Booleano
- Entero de 64 bits
- Número decimal
- Duración
- Medición con unidad
- Array y JSON anidado
- Diccionario y JSON anidado
- Fecha
- Ubicación
- URL
- Datos binarios
- Archivo con nombre y content type
- Null explícito

Imágenes, PDF, audio, vídeo, contactos y otro contenido de Shortcuts puede conservarse usando el tipo **File**, manteniendo bytes y content type.

## Acciones de Shortcuts

La app incluye acciones para crear, obtener, buscar, renombrar y eliminar variables; alternar booleanos; incrementar números; trabajar con arrays y diccionarios; consultar eventos; obtener metadatos; inicializar sólo si una clave no existe; generar UUID; ejecutar operaciones por lote/transacciones con rollback; eliminar expiradas; importar/exportar archivos `.byway`; y gestionar carpetas, movimientos y borrado múltiple.

Las acciones tipadas pueden ejecutarse sin abrir byway.

## JSON estructurado

Las acciones avanzadas infieren valores JSON y admiten envoltorios `$type` cuando es necesario preservar tipos nativos como fecha, ubicación o medición. Las transacciones de múltiples variables restauran el estado anterior si una validación/escritura falla y utilizan un pequeño journal en disco para recuperar interrupciones.

## Compartir configuraciones

**Export Variables** y **Settings → Export all variables** producen un documento `.byway` registrado con iOS que puede incluir valores, metadatos, carpetas y archivos adjuntos. La importación permite conservar claves existentes, sobrescribir coincidencias o reemplazar el conjunto.

Las copias opcionales `.bywaye` pueden protegerse con passphrase. Antes de importar se puede previsualizar el impacto y la última importación exitosa puede deshacerse desde Ajustes.

## Almacenamiento

Cuando el contenedor `iCloud.com.tiburonns.byway` está disponible, byway usa iCloud Drive; de lo contrario utiliza Application Support local. Los conflictos/corrupción se manejan mediante validación, cuarentena y recuperación explícita.

## Requisitos

- iOS/iPadOS 17 o posterior.
- Xcode reciente para compilar.
- iCloud configurado y capacidades adecuadas para probar sincronización entre dispositivos.
- Apple Shortcuts para las acciones App Intent.

## Pruebas

Desde la raíz del repositorio:

```sh
./Tests/run-core-tests.sh
./Tests/run-intent-tests.sh
./Tests/run-shortcut-audit.sh
xcodebuild -project Xcode/byway.xcodeproj -scheme byway -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

CI cubre las rutas deterministas y de compilación; la sincronización real de iCloud entre dispositivos firmados se valida con el plan físico en `../docs/TESTING.es.md`.
