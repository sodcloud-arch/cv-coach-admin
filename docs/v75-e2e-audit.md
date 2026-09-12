# CV Coach V75 — Auditoría E2E

## Objetivo
Proteger el viaje real del cliente desde la sesión de entrenamiento hasta la visibilidad del coach, sin introducir una capa runtime paralela.

## Contratos cubiertos
- hidratación del portal cliente;
- inicio/reanudación de entrenamiento;
- edición y persistencia de series;
- feedback post-entrenamiento v2;
- cierre de sesión vía `complete-workout`;
- rehidratación e historial de entrenamiento;
- secuenciación de próxima sesión;
- hábitos, nutrición, check-in semanal y fotos de progreso;
- lectura de sesiones y feedback en Ficha 360 e Informes del coach;
- conservación del hardening V74.

## Hallazgo de datos
La auditoría detectó tres sesiones históricas abandonadas con `finished_at` válido pero `duration_seconds` nulo. V75 incluye una migración determinística que deriva únicamente esos valores desde `finished_at - started_at`.

## Gate
`scripts/test-client-journey-v75.py` debe emitir:

`CV_CLIENT_JOURNEY_V75_OK`

La comprobación queda ejecutada por `.github/workflows/client-journey-v75.yml` en PR y `main`.
