# CV Coach V77 — Exercise Library Lote A

## Estado

Objetivo del lote: preparar 28 ejercicios prioritarios para ampliar el catálogo activo de 47 a 75 después de QA.

Estado en Supabase al 13/09/2026:
- 28/28 ejercicios existen en `public.exercises`.
- 16/28 ya superaron QA de metadata + asset nuevo y están `active=true`.
- 12/28 permanecen en staging `active=false`.
- La biblioteca global pasó de 47 a 63 ejercicios activos.
- 28/28 tienen instrucciones técnicas, tempo y descanso por defecto.
- 25/28 tienen `image_path`.
- 16 assets nuevos están alojados como WebP en Drive con permiso público por enlace y URL directa validada externamente.
- 9 ejercicios conservan `image_path` heredado del staging anterior y requieren corroboración visual antes de activarse.
- 3 assets nuevos fueron rechazados por QA visual y permanecen sin imagen/activación.

## Bloqueos visuales detectados

- `extension-triceps-unilateral-polea`: la imagen generada representa una extensión sobre cabeza y no el pressdown unilateral esperado.
- `prensa-horizontal`: la imagen representa una prensa inclinada/45°, no una prensa horizontal real.
- `curl-femoral-unilateral-maquina`: la imagen representa extensión de rodilla y no curl femoral.

## Regla de activación

Ningún ejercicio de V77 se activa únicamente por existir en staging. Para pasar a `active=true` debe completar:
1. revisión de nombre/slug/taxonomía;
2. exposición mecánica aplicable;
3. imagen oficial CV Coach horizontal de dos fases;
4. revisión visual biomecánica;
5. URL de imagen pública funcional;
6. confirmación de que no duplica una variante activa sin aportar cobertura útil.

## Pendiente inmediato

1. Regenerar correctamente los 3 assets rechazados.
2. Auditar visualmente los 9 `image_path` heredados del staging.
3. Activar únicamente los 12 restantes cuando pasen QA.
4. Confirmar el objetivo final de 75 ejercicios activos.

## Resultado actual

V77 está parcialmente desplegado de forma segura: 63 ejercicios activos, sin publicar ninguno de los tres assets visualmente incorrectos y conservando en staging todo contenido todavía no verificable.
