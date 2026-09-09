# CV Coach Client Portal

Este directorio conserva una copia exacta y versionada del portal cliente que está públicamente en producción.

## Fuente pública canónica

- Producción pública: `https://cv-coach-roan.vercel.app`
- El dominio `cv-coach-sodcloud-1237.vercel.app` no debe usarse para clientes porque puede quedar detrás de Vercel Authentication.

## Archivos generados

- `index.html`: snapshot exacto del HTML público.
- `SHA256`: huella del snapshot.
- `snapshot.json`: procedencia, fecha UTC, tamaño y hash.

El workflow `Snapshot CV Coach Client Portal` descarga producción, valida que realmente sea CV Coach y rechaza respuestas de autenticación o artefactos anormalmente pequeños antes de versionar.

## Regla de estabilización

La consolidación del portal debe partir desde este snapshot y preservar comportamiento existente: login Supabase, rutina, registro por series, historial anterior, técnica, descansos, sonidos/vibración, hábitos, nutrición, misiones CV12 y responsive mobile/tablet/desktop.

No se debe volver a construir producción mediante capas de preview no versionadas. Los siguientes cambios deben poder auditarse como diff reproducible antes de desplegarse.
