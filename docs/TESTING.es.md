# Plan de aceptación física de Byway

Esta lista valida las partes de Byway que las pruebas portátiles por sí solas no pueden demostrar. Debe ejecutarse antes de considerar una compilación lista para distribución.

## Entorno

- Dos dispositivos Apple con la misma cuenta de iCloud y iCloud Drive activado.
- Una compilación de Byway firmada para desarrollo usando `byway.entitlements`.
- Un segundo dispositivo o compilación para pruebas sin conexión y reconexión.
- Conserva un archivo cifrado v1 conocido y un respaldo cifrado v2 actual.

## 1. Propagación por iCloud

1. En el dispositivo A, crea `QA.Sync.Text` con un valor único.
2. Confirma que aparezca en el dispositivo B.
3. Cámbialo en B y confirma que A reciba la nueva revisión.
4. Repite con Boolean, Integer, Array, Dictionary, Date, Location y File.
5. Mueve variables a una carpeta en A y confirma que la pertenencia a la carpeta se propague a B.

Aprobado: valores, metadatos, carpetas, revisiones y archivos adjuntos convergen sin variables duplicadas ni pérdida silenciosa de datos.

## 2. Conflicto por edición simultánea

1. Deja ambos dispositivos sin conexión.
2. Edita la misma variable en ambos con valores distintos.
3. Haz que una edición tenga una revisión mayor.
4. Reconecta ambos dispositivos.
5. Repite con la misma revisión pero distintos valores de `updatedAt`.
6. Repite con misma revisión y misma fecha usando datos de prueba controlados.

Aprobado: ambos dispositivos convergen usando la precedencia determinista de `VariableConflictResolver`: revisión, después `updatedAt` y finalmente UUID. Ningún conflicto queda sin resolver indefinidamente.

## 3. Recuperación ante corrupción

1. En una compilación de pruebas, coloca un JSON inválido en el directorio activo de Variables.
2. Actualiza Byway.
3. Confirma que las variables sanas sigan cargando.
4. Confirma que el archivo dañado salga del directorio activo solamente después de conservar sus bytes originales en `Quarantine`.
5. Abre Ajustes y confirma que aumente el contador de archivos dañados recuperados.
6. Repite con un registro de carpeta dañado.

Aprobado: los datos sanos siguen disponibles y los bytes dañados se conservan en lugar de desaparecer silenciosamente.

## 4. Compatibilidad de respaldos cifrados

1. Importa un archivo cifrado v1 conocido con la contraseña correcta.
2. Confirma las cantidades de la vista previa antes de importar.
3. Impórtalo y verifica valores y adjuntos.
4. Repite con una contraseña incorrecta y confirma que no cambie ningún dato.
5. Exporta un respaldo cifrado nuevo.
6. Confirma que sea v2 con PBKDF2-HMAC-SHA256 + ChaCha20-Poly1305.
7. Importa el respaldo nuevo en el segundo dispositivo.

Aprobado: v1 sigue siendo legible; los archivos nuevos son v2; una contraseña incorrecta nunca produce una importación parcial.

## 5. Reversión de importación

1. Exporta el estado actual.
2. Modifica varias variables.
3. Importa el archivo exportado usando Sobrescribir.
4. Usa Deshacer última importación.
5. Verifica que valores, carpetas, adjuntos e historial regresen al estado anterior a la importación.

Aprobado: el punto de recuperación restaura el estado previo sin adjuntos huérfanos.

## 6. Trabajo sin conexión y reconexión

1. Desactiva la red.
2. Crea y modifica variables locales.
3. Cierra y vuelve a abrir Byway sin conexión.
4. Restaura la red.
5. Confirma que iCloud finalmente converja sin bloqueos de interfaz ni registros duplicados.

Aprobado: Byway sigue funcionando localmente sin conexión y la recuperación de sincronización no destruye datos.

## Puerta de lanzamiento

Una versión solo debe considerarse validada físicamente cuando todas las secciones aplicables pasen en dispositivos reales. Un CI exitoso por sí solo no cumple esta condición.
