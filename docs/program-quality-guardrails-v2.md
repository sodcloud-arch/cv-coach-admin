# CV Coach — Program Quality Guardrails V2

## Principio
La IA propone. CV Coach valida de forma determinística. El coach publica.

## Restricciones mecánicas
- `training_constraint_catalog`: exposiciones mecánicas descriptivas, no diagnósticos.
- `exercise_mechanical_exposures`: relación ejercicio ↔ exposición.
- `client_training_constraints`: acción vigente `caution` o `avoid` por cliente.
- `avoid`: excluye el ejercicio del catálogo utilizable por IA y bloquea publicación si aparece manualmente.
- `caution`: no excluye automáticamente, pero exige revisión del coach y se muestra en auditoría.

## Tiempo
- La duración efectiva usa el mayor valor entre la duración declarada del día y la estimación determinística.
- Con al menos 3 sesiones completadas válidas se aprende un factor por cliente a partir de la mediana de duración real / duración de referencia.
- El factor aprendido nunca reduce la estimación y queda limitado a 1.50x.

## Disponibilidad
- La disponibilidad habitual vigente permanece separada del onboarding histórico.
- `available_days_next_week` es temporal: informa y genera revisión, pero no reescribe la frecuencia habitual ni bloquea por sí sola un programa de largo plazo.

## Seguridad
- Sin auto-publicación.
- Restricciones médicas no se infieren automáticamente desde texto libre.
- El coach debe convertir información relevante en restricciones operativas explícitas.
