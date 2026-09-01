# Byway

Español · [English](README.md)

Byway es una capa de datos privada para Atajos de Apple. Guarda variables globales tipadas, historial estructurado y el estado de navegación, estacionamiento, música y Casa para que tus automatizaciones compartan contexto persistente sin una cuenta de Byway ni servicios de analíticas.

## Instalación casi plug and play

1. Instala Byway 0.4.0 desde la [fuente de Byway para AltStore](https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source-es.json).
2. Abre Byway una vez.
3. Descarga y abre [Byway-Schema-3.byway](Distribution/Variables/Byway-Schema-3.byway), y selecciona **Sobrescribir claves coincidentes**.
4. Importa los 30 atajos firmados de [Distribution/Shortcuts/es](Distribution/Shortcuts/es).
5. En Atajos, ejecuta una vez **BYWAY — Inicializar sistema** y autoriza los permisos de Apple que solicite.

La colección de atajos en inglés está disponible en [Distribution/Shortcuts/en](Distribution/Shortcuts/en).

## Idioma

Abre **Byway → Ajustes → Idioma** y elige Predeterminado del sistema, English o Español. La selección se guarda localmente y se aplica de inmediato.

## AltStore

- Fuente en español: `https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source-es.json`
- Fuente en inglés: `https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source.json`
- IPA manual: consulta la versión más reciente en Releases de GitHub.

La compilación para AltStore utiliza almacenamiento en el dispositivo para que pueda volver a firmarse sin el permiso privado de iCloud del desarrollador. La importación, exportación y la integración con Atajos siguen disponibles.

## Requisitos

- iOS o iPadOS 17 o posterior
- AltStore Classic u otro instalador de IPA compatible
- Atajos de Apple

## Compilación y pruebas

```sh
./Tests/run-core-tests.sh
./Tests/run-intent-tests.sh
./Tests/run-shortcut-audit.sh
xcodebuild -project Xcode/byway.xcodeproj -scheme byway -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Consulta [Distribution/README.es.md](Distribution/README.es.md) para conocer el contenido del paquete.
