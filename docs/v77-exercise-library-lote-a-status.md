# CV Coach V77 — Exercise Library Lote A

## Estado

Objetivo del lote: preparar 28 ejercicios prioritarios para ampliar el catálogo activo de 47 a 75 después de QA.

Estado en Supabase al 13/09/2026:
- 28/28 ejercicios existen en `public.exercises`.
- 28/28 permanecen `active=false`.
- 28/28 tienen instrucciones técnicas.
- 28/28 tienen tempo y descanso por defecto.
- 9/28 ya tienen `image_path` heredado del staging anterior.
- 19/28 todavía requieren imagen CV Coach.
- Exposiciones mecánicas claras del catálogo actual fueron registradas para press de hombros, elevaciones laterales, hack squat, Smith, prensa horizontal y zancada reversa.

## Regla de activación

Ningún ejercicio de V77 se activa únicamente por existir en staging. Para pasar a `active=true` debe completar:
1. revisión de nombre/slug/taxonomía;
2. exposición mecánica aplicable;
3. imagen oficial CV Coach horizontal de dos fases;
4. revisión visual móvil y Admin;
5. confirmación de que no duplica una variante activa sin aportar cobertura útil.

## Pendiente inmediato

1. Producir/validar los 19 recursos visuales faltantes.
2. Auditar los 9 `image_path` heredados para comprobar que no sean imágenes reutilizadas de otro ejercicio.
3. Ejecutar QA visual móvil + Admin para los 28.
4. Activar únicamente los ejercicios aprobados.

## Resultado esperado

Cuando los 28 superen QA, la biblioteca pasará de 47 a 75 ejercicios activos sin introducir ejercicios incompletos en el motor de programación.
