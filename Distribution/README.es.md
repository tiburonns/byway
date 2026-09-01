# Paquete de configuración de Byway

Español · [English](README.md)

Este directorio contiene los datos portátiles y los atajos necesarios para el flujo completo de Byway.

- `Variables/Byway-Schema-3.byway`: 36 variables inicializadas del Esquema 3.
- `Shortcuts/es`: 30 atajos firmados en español.
- `Shortcuts/en`: 30 atajos firmados en inglés.

Importa solamente un idioma de atajos, salvo que quieras conservar ambas colecciones. Los dos utilizan las mismas claves de variables y los mismos valores canónicos para los modos.

La primera ejecución puede pedir permiso para usar Byway, Ubicación, Mapas, Música, Casa o notificaciones. Son avisos de privacidad de Apple; las ejecuciones posteriores no deberían volver a pedir confirmación. Byway guarda automáticamente las fechas y `SYS.LastAction`.

Las automatizaciones personales, como conexión con CarPlay, cambios de Concentración o llegada a Casa, no pueden distribuirse dentro de un archivo `.shortcut`. Créelas en la pestaña Automatización y selecciona el atajo de modo correspondiente.
