# Byway setup bundle

[Español](README.es.md) · English

This directory contains the portable data and Shortcuts required by the complete Byway workflow.

- `Variables/Byway-Schema-3.byway`: 36 initialized Schema 3 variables.
- `Shortcuts/en`: 30 signed English shortcuts.
- `Shortcuts/es`: 30 signed Spanish shortcuts.

Import only one shortcut language unless you intentionally want both collections. Both use the same canonical variable keys and mode values.

The first run may ask for permission to use Byway, Location, Maps, Music, Home, or notifications. Those are Apple privacy prompts; later runs should not request confirmation again. Mode timestamps and `SYS.LastAction` are written automatically by Byway.

Personal automations such as CarPlay connection, Focus changes, or arrival at Home cannot be shipped inside a `.shortcut` file. Create them in the Automation tab and select the appropriate mode shortcut.
