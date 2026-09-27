# byway TestFlight preflight / Preflight de TestFlight

## English

byway should be uploaded only after the protected branch passes release-contract validation, core integration tests, App Intent tests, Shortcut localization audit, Release Simulator build, Release iPhoneOS build, and IPA packaging.

### Physical acceptance

- Create, update, move, rename, and delete variables of every supported type.
- Verify folders, selection operations, history, transactions, import/export, and attachments.
- Verify App Intents and Siri/Shortcuts actions from the real Shortcuts app.
- Verify iCloud persistence across two signed devices.
- Verify fallback/local configuration without iCloud.
- Test encrypted archive export/import with correct and incorrect passphrases.
- Verify archive migration/compatibility and large attachments.
- Test English, Spanish, and System language modes.

### Export compliance

byway uses **CryptoKit** for user-requested encrypted archives. Do not blindly declare that the app uses no encryption. Before the first App Store Connect upload, review Apple's current export-compliance questionnaire and determine whether this use qualifies for an exemption. Record the selected answer and, if Apple provides/requests documentation, keep it with the release notes. Only add `ITSAppUsesNonExemptEncryption` after that determination is made.

### Archive

1. Pull protected `main` after CI is green.
2. Open `Xcode/byway.xcodeproj`.
3. Select the paid Apple Developer Team.
4. Confirm the iCloud container and production provisioning profile include the committed iCloud entitlements.
5. Product > Archive.
6. Organizer > Validate App.
7. Upload to App Store Connect and begin with Internal Testing.

The unsigned/AltStore path intentionally uses the local entitlement set and is not proof that the iCloud production entitlement profile is valid.

---

## Español

byway sólo debe subirse cuando la rama protegida pase contrato de release, tests de core, App Intents, auditoría de Atajos, Release Simulator, Release iPhoneOS y empaquetado IPA.

### Aceptación física

- Crear, modificar, mover, renombrar y eliminar variables de todos los tipos.
- Verificar carpetas, selección, historial, transacciones, import/export y adjuntos.
- Probar App Intents y Siri/Atajos desde la app Atajos real.
- Verificar persistencia iCloud entre dos dispositivos firmados.
- Verificar configuración local/fallback.
- Probar exportación/importación cifrada con contraseña correcta e incorrecta.
- Probar migraciones y adjuntos grandes.
- Probar Sistema, English y Español.

### Export compliance

byway usa **CryptoKit** para archivos cifrados solicitados por el usuario. No se debe declarar automáticamente que la app no usa cifrado. Antes de la primera subida revisa el cuestionario vigente de export compliance de Apple y determina si el uso es exento. Guarda la decisión con las notas de release. Sólo agrega `ITSAppUsesNonExemptEncryption` después de tomar esa decisión.

### Archive

1. Actualiza el `main` protegido cuando CI esté verde.
2. Abre `Xcode/byway.xcodeproj`.
3. Selecciona el Team de Apple Developer de pago.
4. Confirma que el perfil de producción incluye los entitlements iCloud del repo.
5. Product > Archive.
6. Organizer > Validate App.
7. Sube a App Store Connect y comienza con Internal Testing.

La ruta AltStore/sin firma usa intencionalmente entitlements locales y no valida el perfil iCloud de producción.
